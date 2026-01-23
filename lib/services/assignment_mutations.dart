// FILE: lib/services/assignment_mutations.dart
//
// Assignment completion mutations with wallet and progress tracking.
//
// UPDATED: Uses batched writes instead of transactions to avoid
// Windows-specific Firestore threading crashes.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import '../core/firestore/firestore_paths.dart';
import 'course_config_service.dart';

/// Minimum grade percentage required to earn points (90%)
const int kMinGradeForPoints = 90;

/// Streak bonus thresholds
const Map<int, double> kStreakBonuses = {
  30: 0.20, // 30+ days = 20%
  14: 0.15, // 14+ days = 15%
  7: 0.10,  // 7+ days = 10%
  3: 0.05,  // 3+ days = 5%
};

class AssignmentMutations {
  static final _cfg = CourseConfigService.instance;

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

  /// Get today's date as "YYYY-MM-DD"
  static String _todayString() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Calculate streak bonus percentage based on current streak days
  static double _calculateStreakBonus(int streakDays) {
    for (final entry in kStreakBonuses.entries) {
      if (streakDays >= entry.key) {
        return entry.value;
      }
    }
    return 0.0;
  }

  /// Calculate new streak values based on last completion date
  /// Returns (newCurrentStreak, newLongestStreak)
  static (int, int) _calculateNewStreak(
    String lastCompletionDate,
    int currentStreak,
    int longestStreak,
    String today,
  ) {
    // First completion ever
    if (lastCompletionDate.isEmpty) {
      return (1, 1);
    }

    // Same day — no streak change
    if (lastCompletionDate == today) {
      return (currentStreak, longestStreak);
    }

    final lastDt = DateTime.tryParse(lastCompletionDate);
    final todayDt = DateTime.tryParse(today);

    if (lastDt == null || todayDt == null) {
      return (currentStreak, longestStreak);
    }

    final diff = todayDt.difference(lastDt).inDays;

    int newCurrent;
    if (diff == 1) {
      // Consecutive day — increment streak
      newCurrent = currentStreak + 1;
    } else if (diff > 1) {
      // Missed day(s) — reset streak
      newCurrent = 1;
    } else {
      // diff <= 0 (shouldn't happen, but handle it)
      newCurrent = currentStreak;
    }

    final newLongest = newCurrent > longestStreak ? newCurrent : longestStreak;

    return (newCurrent, newLongest);
  }

  /// Complete or uncomplete an assignment.
  ///
  /// Uses batched writes instead of transactions to avoid Windows crashes.
  /// This is slightly less atomic but much more stable.
  static Future<CompletionResult> setCompleted(
    Assignment a, {
    required bool completed,
    int? gradePercent,
    String? completionDate,
    int? wpm,
    double? accuracy,
    int? minutesPracticed,
    bool isRetest = false,
  }) async {
    final assignmentRef = FirestorePaths.assignmentsCol().doc(a.id);
    final studentRef = FirestorePaths.studentsCol().doc(a.studentId);

    final configId = await _resolveCourseConfigId(a);
    final cfg = configId.isEmpty ? null : await _cfg.getConfig(configId);

    // Category key (prefer stored, else infer)
    var categoryKey = a.categoryKey.trim();
    categoryKey = categoryKey.isNotEmpty ? categoryKey : _inferCategoryKeyIfMissing(configId, a.name);

    // Get base points from config or assignment
    int basePoints;
    if (cfg != null && categoryKey.isNotEmpty) {
      basePoints = _cfg.basePointsFor(cfg, categoryKey);
    } else if (a.pointsBase > 0) {
      basePoints = a.pointsBase;
    } else {
      basePoints = 0;
    }

    final today = _todayString();
    final effectiveCompletionDate = completionDate?.trim().isNotEmpty == true ? completionDate! : today;

    // Read current state
    final assignmentSnap = await assignmentRef.get();
    final studentSnap = await studentRef.get();

    final assignmentData = assignmentSnap.data() ?? <String, dynamic>{};
    final studentData = studentSnap.data() ?? <String, dynamic>{};

    final alreadyCompleted = (assignmentData['completed'] == true);
    final existingRewardTxnId =
        (assignmentData['rewardTxnId'] ?? assignmentData['reward_txn_id'] ?? '').toString().trim();
    final existingRewardPointsApplied = (() {
      final v = assignmentData['rewardPointsApplied'] ?? assignmentData['reward_points_applied'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    })();

    // Get current student streak info
    final currentStreak = asInt(studentData['currentStreak'] ?? studentData['current_streak'], fallback: 0);
    final longestStreak = asInt(studentData['longestStreak'] ?? studentData['longest_streak'], fallback: 0);
    final lastCompletionDate =
        (studentData['lastCompletionDate'] ?? studentData['last_completion_date'] ?? '').toString();

    // Determine if assignment is gradable
    final isGradable = asBool(assignmentData['gradable'], fallback: true);

    int pointsAwarded = 0;
    int newStreak = currentStreak;
    int newLongest = longestStreak;
    double streakBonusPercent = 0.0;

    // =========================================
    // CASE 1: Marking COMPLETE
    // =========================================
    if (completed) {
      // Calculate streak
      final (calculatedStreak, calculatedLongest) = _calculateNewStreak(
        lastCompletionDate,
        currentStreak,
        longestStreak,
        today,
      );
      newStreak = calculatedStreak;
      newLongest = calculatedLongest;
      streakBonusPercent = _calculateStreakBonus(newStreak);

      // Determine effective grade for points calculation
      int? effectiveGrade = gradePercent;
      if (!isGradable) {
        effectiveGrade = 100; // Pass/fail earns full points
      }

      // Calculate points
      bool qualifiesForPoints = false;
      if (!isGradable) {
        qualifiesForPoints = true;
      } else if (effectiveGrade != null && effectiveGrade >= kMinGradeForPoints) {
        qualifiesForPoints = true;
      }

      if (qualifiesForPoints && basePoints > 0) {
        final streakBonus = (basePoints * streakBonusPercent).round();
        pointsAwarded = basePoints + streakBonus;
      }

      // Skip if already rewarded and not a retest
      if (alreadyCompleted && existingRewardTxnId.isNotEmpty && !isRetest) {
        // Just update metadata
        await assignmentRef.update({
          'completed': true,
          'grade': gradePercent,
          'completionDate': effectiveCompletionDate,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update streak if needed
        if (lastCompletionDate != today) {
          await studentRef.update({
            'currentStreak': newStreak,
            'longestStreak': newLongest,
            'lastCompletionDate': today,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        return CompletionResult(
          pointsAwarded: 0,
          currentStreak: newStreak,
          streakBonusPercent: streakBonusPercent,
          meetsGradeThreshold: true,
        );
      }

      // Use a batch for atomic-ish writes
      final batch = FirebaseFirestore.instance.batch();

      // Update assignment
      batch.update(assignmentRef, {
        'completed': true,
        'grade': gradePercent,
        'completionDate': effectiveCompletionDate,
        'categoryKey': categoryKey.isNotEmpty ? categoryKey : FieldValue.delete(),
        'courseConfigId': configId.isNotEmpty ? configId : FieldValue.delete(),
        'pointsEarned': pointsAwarded,
        if (wpm != null) 'wpm': wpm,
        if (accuracy != null) 'accuracy': accuracy,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Update student wallet and streak
      final studentUpdate = <String, dynamic>{
        'currentStreak': newStreak,
        'longestStreak': newLongest,
        'lastCompletionDate': today,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (pointsAwarded > 0) {
        studentUpdate['walletBalance'] = FieldValue.increment(pointsAwarded);

        // Create wallet transaction
        final txnRef = FirestorePaths.walletTransactionsCol(a.studentId).doc();
        batch.set(txnRef, {
          'type': 'deposit',
          'points': pointsAwarded,
          'source': 'assignment_completion',
          'studentId': a.studentId,
          'subjectId': a.subjectId,
          'subjectName': a.subjectName,
          'assignmentId': a.id,
          'assignmentName': a.name,
          'categoryKey': categoryKey,
          'gradePercent': gradePercent,
          'basePoints': basePoints,
          'streakBonus': (basePoints * streakBonusPercent).round(),
          'streakDays': newStreak,
          'courseConfigId': configId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update assignment with transaction reference
        batch.update(assignmentRef, {
          'rewardTxnId': txnRef.id,
          'rewardPointsApplied': pointsAwarded,
        });
      }

      batch.update(studentRef, studentUpdate);

      await batch.commit();

      return CompletionResult(
        pointsAwarded: pointsAwarded,
        currentStreak: newStreak,
        streakBonusPercent: streakBonusPercent,
        meetsGradeThreshold: gradePercent == null || gradePercent >= kMinGradeForPoints,
      );
    }

    // =========================================
    // CASE 2: Marking INCOMPLETE (uncheck)
    // =========================================
    if (!completed) {
      final batch = FirebaseFirestore.instance.batch();

      // Update assignment
      batch.update(assignmentRef, {
        'completed': false,
        'grade': null,
        'completionDate': '',
        'pointsEarned': 0,
        'rewardTxnId': FieldValue.delete(),
        'rewardPointsApplied': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reverse wallet if points were applied
      if (existingRewardTxnId.isNotEmpty && existingRewardPointsApplied > 0 && a.studentId.trim().isNotEmpty) {
        // Create reversal transaction
        final revRef = FirestorePaths.walletTransactionsCol(a.studentId).doc();
        batch.set(revRef, {
          'type': 'reversal',
          'points': -existingRewardPointsApplied,
          'source': 'assignment_uncomplete',
          'studentId': a.studentId,
          'subjectId': a.subjectId,
          'subjectName': a.subjectName,
          'assignmentId': a.id,
          'assignmentName': a.name,
          'categoryKey': categoryKey,
          'refTxnId': existingRewardTxnId,
          'courseConfigId': configId,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Decrement wallet balance
        batch.update(studentRef, {
          'walletBalance': FieldValue.increment(-existingRewardPointsApplied),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      return CompletionResult(
        pointsAwarded: 0,
        currentStreak: currentStreak,
        streakBonusPercent: 0.0,
        meetsGradeThreshold: true,
      );
    }

    return CompletionResult(
      pointsAwarded: 0,
      currentStreak: currentStreak,
      streakBonusPercent: 0.0,
      meetsGradeThreshold: true,
    );
  }

  /// Create a new assignment with proper defaults
  static Future<String> createAssignment({
    required String studentId,
    required String subjectId,
    required String name,
    required String dueDate,
    int pointsBase = 10,
    bool gradable = true,
    String courseConfigId = '',
    String categoryKey = '',
    int orderInCourse = 0,

    // ✅ Added (optional): store display names for consistent UI rendering
    // even if a screen doesn't resolve subjectsById at runtime.
    String studentName = '',
    String subjectName = '',
  }) async {
    final docRef = FirestorePaths.assignmentsCol().doc();

    await docRef.set({
     // IDs (write both camelCase + snake_case for compatibility)
     'studentId': studentId,
     'student_id': studentId,
   
     'subjectId': subjectId,
     'subject_id': subjectId,
   
     // Optional display names (write both)
     'studentName': studentName,
     'student_name': studentName,
   
     'subjectName': subjectName,
     'subject_name': subjectName,
   
     // Core
     'name': name,
     'nameLower': name.toLowerCase(),
     'dueDate': dueDate,
     'completionDate': '',
     'completed': false,
     'grade': null,
   
     // Curriculum link (write both)
     'courseConfigId': courseConfigId,
     'course_config_id': courseConfigId,
   
     'categoryKey': categoryKey,
     'category_key': categoryKey,
   
     'orderInCourse': orderInCourse,
     'order_in_course': orderInCourse,
   
     // Points
     'pointsBase': pointsBase,
     'points_base': pointsBase,
   
     'pointsEarned': 0,
     'points_earned': 0,
   
     'gradable': gradable,
   
     // Legacy
     'pointsPossible': pointsBase,
     'points_possible': pointsBase,
   
     'weight': 1.0,
   
     // Retest tracking
     'attempts': [],
     'bestGrade': null,
   
     // Wallet tracking
     'rewardTxnId': '',
     'reward_txn_id': '',
   
     'rewardPointsApplied': 0,
     'reward_points_applied': 0,
   
     'createdAt': FieldValue.serverTimestamp(),
     'updatedAt': FieldValue.serverTimestamp(),
   });


    return docRef.id;
  }
}

/// Result from completing an assignment
class CompletionResult {
  final int pointsAwarded;
  final int currentStreak;
  final double streakBonusPercent;
  final bool meetsGradeThreshold;

  const CompletionResult({
    required this.pointsAwarded,
    this.currentStreak = 0,
    this.streakBonusPercent = 0.0,
    this.meetsGradeThreshold = true,
  });

  /// Whether the grade was below 90% (no points earned for gradable)
  bool get gradeWasBelowThreshold => !meetsGradeThreshold;
}
