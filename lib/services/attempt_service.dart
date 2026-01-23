import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore/firestore_paths.dart';
import '../core/models/models.dart';

class AttemptService {
  AttemptService._();
  static final AttemptService instance = AttemptService._();

  /// Creates an attempt doc with TRUE server time, and updates the assignment's:
  /// - bestGrade (max of existing + new)
  /// - grade (kept as "current best" for compatibility)
  /// - attemptCount (+1)
  /// - lastAttemptAt (server timestamp)
  Future<void> addAttempt({
    required String assignmentId,
    required int grade,
  }) async {
    final db = FirebaseFirestore.instance;

    final assignmentRef = FirestorePaths.assignmentsCol().doc(assignmentId);
    final attemptRef = FirestorePaths.assignmentAttemptsCol(assignmentId).doc();

    final today = normalizeDueDate(DateTime.now());

    await db.runTransaction((tx) async {
      final snap = await tx.get(assignmentRef);
      final data = snap.data() ?? <String, dynamic>{};

      final existingBest = data['bestGrade'] == null
          ? (data['grade'] == null ? 0 : asInt(data['grade'], fallback: 0))
          : asInt(data['bestGrade'], fallback: 0);

      final nextBest = grade > existingBest ? grade : existingBest;

      // TRUE server time lives on the attempt doc:
      tx.set(attemptRef, <String, dynamic>{
        'grade': grade,
        'date': today,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Keep assignment fields updated for fast UI:
      tx.update(assignmentRef, <String, dynamic>{
        'bestGrade': nextBest,
        'grade': nextBest, // keep "grade" as current/best for existing UI
        'attemptCount': FieldValue.increment(1),
        'lastAttemptAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
