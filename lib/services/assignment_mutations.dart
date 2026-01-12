import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import 'course_config_service.dart';

class AssignmentMutations {
  static final _cfg = CourseConfigService.instance;

  static CollectionReference<Map<String, dynamic>> _assignmentsCol() =>
      FirebaseFirestore.instance.collection('assignments');

  static CollectionReference<Map<String, dynamic>> _subjectsCol() =>
      FirebaseFirestore.instance.collection('subjects');

  static CollectionReference<Map<String, dynamic>> _studentsCol() =>
      FirebaseFirestore.instance.collection('students');

  static CollectionReference<Map<String, dynamic>> _walletTxnsCol(String studentId) =>
      _studentsCol().doc(studentId).collection('walletTransactions');

  static Future<String> _resolveCourseConfigId(Assignment a) async {
    if (a.courseConfigId.trim().isNotEmpty) return a.courseConfigId.trim();

    // Subject-based config link
    if (a.subjectId.trim().isNotEmpty) {
      final subSnap = await _subjectsCol().doc(a.subjectId).get();
      final data = subSnap.data();
      final v = data?['courseConfigId'] ?? data?['course_config_id'];
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }

    // Soft fallback based on subject name (helps during transition)
    final sn = a.subjectName.toLowerCase();
    if (sn.contains('chem')) return 'general_chemistry_v1';

    return '';
  }

  static String _inferCategoryKeyIfMissing(String configId, String assignmentName) {
    if (configId != 'general_chemistry_v1') return '';
    final n = assignmentName.toLowerCase();

    if (n.contains('reading')) return 'reading_set';
    if (n.contains('lecture') || n.contains('notes')) return 'lecture_notes';
    if (n.contains('problem')) return 'problem_set';
    if (n.contains('worksheet') || n.contains('lab')) return 'worksheet';
    if (n.contains('topic test') || (n.contains('test') && !n.contains('pretest'))) return 'topic_test';

    return '';
  }

  /// The ONE place that should mutate completion state + wallet ledger.
  ///
  /// - If marking complete and a reward hasn't been applied -> deposits points.
  /// - If unchecking complete and a reward WAS applied -> reverses points.
  static Future<void> setCompleted(
    Assignment a, {
    required bool completed,
    int? gradePercent,
  }) async {
    final assignmentRef = _assignmentsCol().doc(a.id);
    final studentRef = _studentsCol().doc(a.studentId);

    final configId = await _resolveCourseConfigId(a);
    final cfg = configId.isEmpty ? null : await _cfg.getConfig(configId);

    // category key (prefer stored, else infer)
    var categoryKey = a.categoryKey.trim();
    categoryKey = categoryKey.isNotEmpty ? categoryKey : _inferCategoryKeyIfMissing(configId, a.name);

    final basePoints = (cfg == null || categoryKey.isEmpty) ? 0 : _cfg.basePointsFor(cfg, categoryKey);
    final mult = (cfg == null || categoryKey.isEmpty) ? 1.0 : _cfg.multiplierFor(cfg, categoryKey: categoryKey, gradePercent: gradePercent);
    final pointsToAward = (basePoints <= 0) ? 0 : (basePoints * mult).round();

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

      // Keep assignment metadata updated even if no points applied yet
      final baseUpdate = <String, dynamic>{
        'completed': completed,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Keep categoryKey if we inferred it (helps future screens / reports)
      if (categoryKey.isNotEmpty && (data['categoryKey'] ?? '').toString().trim().isEmpty) {
        baseUpdate['categoryKey'] = categoryKey;
      }

      // Grade handling (recommended: clear when not completed)
      if (completed) {
        baseUpdate['grade'] = gradePercent; // can be null
      } else {
        baseUpdate['grade'] = null;
      }

      // CASE 1: Marking COMPLETE
      if (completed) {
        // If it was already rewarded, just update completion/grade and exit.
        if (alreadyCompleted && rewardTxnId.isNotEmpty) {
          tx.set(assignmentRef, baseUpdate, SetOptions(merge: true));
          return;
        }

        // Apply wallet reward if we can.
        if (pointsToAward > 0 && a.studentId.trim().isNotEmpty) {
          final txnId = _walletTxnsCol(a.studentId).doc().id;
          final txnRef = _walletTxnsCol(a.studentId).doc(txnId);

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

        // No points applied (missing config/categoryKey/etc) — still mark complete.
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
          final revId = _walletTxnsCol(a.studentId).doc().id;
          final revRef = _walletTxnsCol(a.studentId).doc(revId);

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
  }
}
