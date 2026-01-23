// FILE: lib/services/subject_delete_service.dart
//
// Deletes:
// - /subjects/{subjectId}
// - /assignments/* where subjectId == subjectId
// - /students/{studentId}/subjectProgress/{courseConfigId}  (your enrollment docs)
// - collectionGroup('badgesEarned') where subjectId == subjectId
//
// Optional:
// - reversePoints: creates a reversing wallet transaction and decrements walletBalance

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/firestore/firestore_paths.dart';

class SubjectDeleteResult {
  final int assignmentsDeleted;
  final int progressDocsDeleted;
  final int badgesDeleted;
  final int pointsReversed;
  final bool subjectDeleted;

  const SubjectDeleteResult({
    required this.assignmentsDeleted,
    required this.progressDocsDeleted,
    required this.badgesDeleted,
    required this.pointsReversed,
    required this.subjectDeleted,
  });
}

class SubjectDeleteService {
  SubjectDeleteService._();
  static final SubjectDeleteService instance = SubjectDeleteService._();

  static const int _batchLimit = 450;
  static const String _walletBalanceField = 'walletBalance';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<SubjectDeleteResult> deleteSubjectCascade({
    required String subjectId,
    String? courseConfigId,
    List<String>? studentIds,
    bool reversePoints = false,
  }) async {
    final sid = subjectId.trim();
    if (sid.isEmpty) {
      return const SubjectDeleteResult(
        assignmentsDeleted: 0,
        progressDocsDeleted: 0,
        badgesDeleted: 0,
        pointsReversed: 0,
        subjectDeleted: false,
      );
    }

    final cfgId = (courseConfigId ?? '').trim().isEmpty ? null : courseConfigId!.trim();
    final resolvedStudentIds = studentIds ?? await _fetchStudentIds();

    // 1) Fetch assignments for this subject (we need docs for point reversal).
    final assignmentsSnap = await FirestorePaths.assignmentsCol()
        .where('subjectId', isEqualTo: sid)
        .get();

    final assignmentDocs = assignmentsSnap.docs;

    // 1a) Reverse points (optional) BEFORE deleting assignments.
    int totalPointsReversed = 0;
    if (reversePoints) {
      final pointsByStudent = <String, int>{};

      for (final d in assignmentDocs) {
        final data = d.data();
        final studentId = (data['studentId'] ?? data['student_id'] ?? '').toString().trim();
        if (studentId.isEmpty) continue;

        final completed = (data['completed'] == true) || (data['isCompleted'] == true);
        if (!completed) continue;

        final rawPts =
            data['rewardPointsApplied'] ??
            data['reward_points_applied'] ??
            data['pointsApplied'] ??
            data['points_applied'] ??
            0;

        final pts = rawPts is num ? rawPts.toInt() : int.tryParse(rawPts.toString()) ?? 0;
        if (pts <= 0) continue;

        pointsByStudent[studentId] = (pointsByStudent[studentId] ?? 0) + pts;
      }

      totalPointsReversed = pointsByStudent.values.fold(0, (a, b) => a + b);

      // apply reversals + create walletTransactions
      await _applyWalletReversals(
        pointsByStudent: pointsByStudent,
        subjectId: sid,
        courseConfigId: cfgId,
      );
    }

    // 2) Delete assignments
    final assignmentRefs = assignmentDocs.map((d) => d.reference).toList();
    await _deleteRefsInBatches(assignmentRefs);

    // 3) Delete progress docs (your enroll docs are /subjectProgress/{configId})
    final progressRefs = <DocumentReference>[];

    for (final studentId in resolvedStudentIds) {
      final col = FirestorePaths.subjectProgressCol(studentId);

      if (cfgId != null) {
        progressRefs.add(col.doc(cfgId));
      }

      // Backward-compat cleanup: also try doc(subjectId)
      if (cfgId == null || cfgId != sid) {
        progressRefs.add(col.doc(sid));
      }
    }
    await _deleteRefsInBatches(progressRefs);

    // 4) Delete badgesEarned for this subject
    final badgesSnap = await _db
        .collectionGroup('badgesEarned')
        .where('subjectId', isEqualTo: sid)
        .get();
    final badgeRefs = badgesSnap.docs.map((d) => d.reference).toList();
    await _deleteRefsInBatches(badgeRefs);

    // 5) Delete subject doc
    await FirestorePaths.subjectsCol().doc(sid).delete();

    return SubjectDeleteResult(
      assignmentsDeleted: assignmentRefs.length,
      progressDocsDeleted: progressRefs.length,
      badgesDeleted: badgeRefs.length,
      pointsReversed: totalPointsReversed,
      subjectDeleted: true,
    );
  }

  Future<List<String>> _fetchStudentIds() async {
    final snap = await FirestorePaths.studentsCol().get();
    return snap.docs.map((d) => d.id).toList();
  }

  Future<void> _applyWalletReversals({
    required Map<String, int> pointsByStudent,
    required String subjectId,
    required String? courseConfigId,
  }) async {
    if (pointsByStudent.isEmpty) return;

    final entries = pointsByStudent.entries.toList();
    var i = 0;

    while (i < entries.length) {
      final end = (i + 200) > entries.length ? entries.length : (i + 200);
      final chunk = entries.sublist(i, end);

      final batch = _db.batch();

      for (final e in chunk) {
        final studentId = e.key;
        final pts = e.value;
        if (pts <= 0) continue;

        // decrement wallet balance
        final studentRef = FirestorePaths.studentsCol().doc(studentId);
        batch.update(studentRef, {
          _walletBalanceField: FieldValue.increment(-pts),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // add reversal transaction
        final txnRef = studentRef.collection('walletTransactions').doc();
        batch.set(txnRef, {
          'delta': -pts,
          'type': 'reversal',
          'reason': 'subject_delete',
          'subjectId': subjectId,
          if (courseConfigId != null) 'courseConfigId': courseConfigId,
          'createdAt': FieldValue.serverTimestamp(),
          'note': 'Reversed points due to subject deletion',
        });
      }

      await batch.commit();
      i = end;
    }
  }

  Future<void> _deleteRefsInBatches(List<DocumentReference> refs) async {
    if (refs.isEmpty) return;

    var index = 0;
    while (index < refs.length) {
      final end = (index + _batchLimit) > refs.length ? refs.length : (index + _batchLimit);
      final chunk = refs.sublist(index, end);

      final batch = _db.batch();
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
      index = end;
    }
  }
}
