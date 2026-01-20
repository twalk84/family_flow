// FILE: lib/services/assignment_mutations.dart
//
// Assignment completion mutations with wallet and progress tracking.
//
// UPDATED: Now integrates with ProgressService for streaks, badges, and metrics.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import '../core/firestore/firestore_paths.dart';
import 'course_config_service.dart';
import 'progress_service.dart';
import '../core/models/progress_models.dart';

class AssignmentMutations {
  static final _cfg = CourseConfigService.instance;
  static final _progress = ProgressService.instance;

  static Future<String> _resolveCourseConfigId(Assignment a) async {
    if (a.courseConfigId.trim().isNotEmpty) return a.courseConfigId.trim();

    // Subject-based config link
    if (a.subjectId.trim().isNotEmpty) {
      final subSnap = await FirestorePaths.subjectsCol().doc(a.subjectId).get();
      final data = subSnap.data();
      final v = data?['courseConfigId'] ?? data?['course_config_id'];
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }

    // Soft fallback based on subject name (helps during transition)
    final sn = a.subjectName.toLowerCase();
    if (sn.contains('chem')) return 'general_chemistry_v1';
    if (sn.contains('typing')) return 'touch_typing_v1';
    if (sn.contains('bio')) return 'biological_science_v1';
    if (sn.contains('brit') && sn.contains('lit')) return 'british_literature_v1';

    return '';
  }

  static String _inferCategoryKeyIfMissing(String configId, String assignmentName) {
    final n = assignmentName.toLowerCase();

    // General patterns
    if (n.contains('reading')) return 'reading_set';
    if (n.contains('lecture') || n.contains('notes')) return 'lecture_notes';
    if (n.contains('problem')) return 'problem_set';
    if (n.contains('worksheet') || n.contains('lab')) return 'worksheet';
    if (n.contains('topic test') || (n.contains('test') && !n.contains('pretest'))) return 'topic_test';
    if (n.contains('chapter quiz') || n.contains('quiz')) return 'chapter_quiz';

    // Typing-specific
    if (configId == 'touch_typing_v1') {
      if (n.contains('practice')) return 'daily_practice';
      if (n.contains('activity')) return 'activity';
      if (n.contains('end of lesson') || n.contains('final test')) return 'end_of_lesson_test';
      if (n.contains('lesson')) return 'lesson_completion';
    }

    return '';
  }

  /// The ONE place that should mutate completion state + wallet ledger + progress.
  ///
  /// - If marking complete and a reward hasn't been applied -> deposits points.
  /// - If unchecking complete and a reward WAS applied -> reverses points.
  /// - NEW: Updates progress tracking (streaks, badges, metrics).
  ///
  /// Optional parameters for skill courses:
  /// - [wpm]: Words per minute (for typing)
  /// - [accuracy]: Accuracy percentage (for typing)
  /// - [minutesPracticed]: Minutes spent practicing
  static Future<CompletionResult> setCompleted(
    Assignment a, {
    required bool completed,
    int? gradePercent,
    int? wpm,
    double? accuracy,
    int? minutesPracticed,
  }) async {
    final assignmentRef = FirestorePaths.assignmentsCol().doc(a.id);
    final studentRef = FirestorePaths.studentsCol().doc(a.studentId);

    final configId = await _resolveCourseConfigId(a);
    final cfg = configId.isEmpty ? null : await _cfg.getConfig(configId);

    // category key (prefer stored, else infer)
    var categoryKey = a.categoryKey.trim();
    categoryKey = categoryKey.isNotEmpty ? categoryKey : _inferCategoryKeyIfMissing(configId, a.name);

    final basePoints = (cfg == null || categoryKey.isEmpty) ? 0 : _cfg.basePointsFor(cfg, categoryKey);
    final mult = (cfg == null || categoryKey.isEmpty)
        ? 1.0
        : _cfg.multiplierFor(cfg, categoryKey: categoryKey, gradePercent: gradePercent);
    final pointsToAward = (basePoints <= 0) ? 0 : (basePoints * mult).round();

    // Track progress result for return value
    ProgressUpdateResult? progressResult;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      final data = snap.data() ?? <String, dynamic>{};

      final alreadyCompleted = (data['completed'] == true);
      final rewardTxnId = (data['rewardTxnId'] ?? data['reward_txn_id'] ?? '').toString().trim();
      final rewardPointsApplied = (() {
        final v = data['rewardPointsApplied'] ?? data['reward_points_applied'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      })();

      // Keep assignment metadata updated
      final baseUpdate = <String, dynamic>{
        'completed': completed,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Keep categoryKey if we inferred it
      if (categoryKey.isNotEmpty && (data['categoryKey'] ?? '').toString().trim().isEmpty) {
        baseUpdate['categoryKey'] = categoryKey;
      }

      // Grade handling
      if (completed) {
        baseUpdate['grade'] = gradePercent;
      } else {
        baseUpdate['grade'] = null;
      }

      // Store WPM/accuracy if provided (for typing courses)
      if (wpm != null) baseUpdate['wpm'] = wpm;
      if (accuracy != null) baseUpdate['accuracy'] = accuracy;

      // CASE 1: Marking COMPLETE
      if (completed) {
        // If it was already rewarded, just update completion/grade and exit.
        if (alreadyCompleted && rewardTxnId.isNotEmpty) {
          tx.set(assignmentRef, baseUpdate, SetOptions(merge: true));
          return;
        }

        // Apply wallet reward if we can.
        if (pointsToAward > 0 && a.studentId.trim().isNotEmpty) {
          final txnId = FirestorePaths.studentsCol()
              .doc(a.studentId)
              .collection('walletTransactions')
              .doc()
              .id;
          final txnRef = FirestorePaths.studentsCol()
              .doc(a.studentId)
              .collection('walletTransactions')
              .doc(txnId);

          tx.set(txnRef, <String, dynamic>{
            'type': 'deposit',
            'points': pointsToAward,
            'source': 'assignment_completion',
            'studentId': a.studentId,
            'subjectId': a.subjectId,
            'subjectName': a.subjectName,
            'assignmentId': a.id,
            'assignmentName': a.name,
            'categoryKey': categoryKey,
            'gradePercent': gradePercent,
            'courseConfigId': configId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          tx.set(studentRef, <String, dynamic>{
            'walletBalance': FieldValue.increment(pointsToAward),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          tx.set(assignmentRef, <String, dynamic>{
            ...baseUpdate,
            'rewardTxnId': txnId,
            'rewardPointsApplied': pointsToAward,
            'courseConfigId': configId,
          }, SetOptions(merge: true));

          return;
        }

        // No points applied — still mark complete.
        tx.set(assignmentRef, <String, dynamic>{
          ...baseUpdate,
          'courseConfigId': configId,
        }, SetOptions(merge: true));
        return;
      }

      // CASE 2: Marking INCOMPLETE (uncheck)
      if (!completed) {
        // If a reward was applied before, reverse it.
        if (rewardTxnId.isNotEmpty && rewardPointsApplied > 0 && a.studentId.trim().isNotEmpty) {
          final revId = FirestorePaths.studentsCol()
              .doc(a.studentId)
              .collection('walletTransactions')
              .doc()
              .id;
          final revRef = FirestorePaths.studentsCol()
              .doc(a.studentId)
              .collection('walletTransactions')
              .doc(revId);

          tx.set(revRef, <String, dynamic>{
            'type': 'reversal',
            'points': -rewardPointsApplied,
            'source': 'assignment_uncomplete',
            'studentId': a.studentId,
            'subjectId': a.subjectId,
            'subjectName': a.subjectName,
            'assignmentId': a.id,
            'assignmentName': a.name,
            'categoryKey': categoryKey,
            'refTxnId': rewardTxnId,
            'courseConfigId': configId,
            'createdAt': FieldValue.serverTimestamp(),
          });

          tx.set(studentRef, <String, dynamic>{
            'walletBalance': FieldValue.increment(-rewardPointsApplied),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          tx.set(assignmentRef, <String, dynamic>{
            ...baseUpdate,
            'rewardTxnId': FieldValue.delete(),
            'rewardPointsApplied': FieldValue.delete(),
          }, SetOptions(merge: true));

          return;
        }

        // No reward to reverse; just update completion/grade.
        tx.set(assignmentRef, baseUpdate, SetOptions(merge: true));
      }
    });

    // =====================
    // NEW: Progress Tracking (outside transaction for simplicity)
    // =====================
    if (completed) {
      // Build an updated assignment with resolved categoryKey
      final updatedAssignment = Assignment(
        id: a.id,
        studentId: a.studentId,
        subjectId: a.subjectId,
        name: a.name,
        dueDate: a.dueDate,
        isCompleted: true,
        grade: gradePercent,
        categoryKey: categoryKey,
        pointsPossible: a.pointsPossible,
        weight: a.weight,
        courseConfigId: configId,
        rewardTxnId: a.rewardTxnId,
        rewardPointsApplied: pointsToAward,
        studentName: a.studentName,
        subjectName: a.subjectName,
      );

      progressResult = await _progress.recordActivity(
        assignment: updatedAssignment,
        gradePercent: gradePercent,
        wpm: wpm,
        accuracy: accuracy,
        minutesPracticed: minutesPracticed,
      );
    } else {
      // Reverse progress tracking
      await _progress.reverseActivity(assignment: a);
    }

    return CompletionResult(
      pointsAwarded: completed ? pointsToAward : 0,
      progressResult: progressResult,
    );
  }
}

/// Result from completing an assignment
class CompletionResult {
  final int pointsAwarded;
  final ProgressUpdateResult? progressResult;

  const CompletionResult({
    required this.pointsAwarded,
    this.progressResult,
  });

  /// New badges earned from this completion
  List<BadgeEarned> get newBadges => progressResult?.newBadges ?? [];

  /// Current streak after this completion
  int get currentStreak => progressResult?.streakCurrent ?? 0;

  /// Streak bonus percentage
  double get streakBonusPercent => progressResult?.streakBonusPercent ?? 0.0;

  /// WPM improvement bonus points (for typing)
  int get improvementBonusPoints => progressResult?.improvementBonusPoints ?? 0;

  /// WPM improvement since baseline (for typing)
  int get wpmImprovement => progressResult?.wpmImprovement ?? 0;

  /// Whether any badges were earned
  bool get hasBadges => newBadges.isNotEmpty;

  /// Whether an improvement bonus was earned
  bool get hasImprovementBonus => improvementBonusPoints > 0;
}