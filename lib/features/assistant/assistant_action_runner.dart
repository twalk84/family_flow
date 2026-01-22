// FILE: lib/features/assistant/assistant_action_runner.dart
//
// Runs structured assistant "actions" by writing to Firestore.
// This keeps the assistant cloud stateless and the app authoritative.
//
// Expected action format (example):
// { "type": "add_assignment", "name": "...", "dueDate": "2025-12-18", "studentName": "...", "subjectName": "..." }

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firestore_paths.dart';
import 'models.dart';

class AssistantActionRunner {
  static Future<String?> run(dynamic action) async {
    final a = _coerceToMap(action);
    if (a == null) return null;

    final type = (a['type'] ?? a['action'] ?? '').toString().trim();
    if (type.isEmpty) return 'Action ignored (missing type).';

    switch (type) {
      case 'set_teacher_mood':
        return _setTeacherMood(a);

      case 'add_student':
        return _addStudent(a);

      case 'add_subject':
        return _addSubject(a);

      case 'add_assignment':
        return _addAssignment(a);

      case 'complete_assignment':
        return _completeAssignment(a);

      case 'undo_assignment':
        return _undoAssignment(a);

      case 'delete_assignment':
        return _deleteAssignment(a);

      default:
        return 'Action not supported: $type';
    }
  }

  // ----------------------------
  // Actions
  // ----------------------------

  static Future<String> _setTeacherMood(Map<String, dynamic> a) async {
    final mood = a['mood']; // can be null
    await FirestorePaths.settingsDoc().set(
      {
        'teacherMood': mood,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return mood == null ? 'Cleared teacher mood.' : 'Set teacher mood to $mood';
  }

  static Future<String> _addStudent(Map<String, dynamic> a) async {
    final name = (a['name'] ?? '').toString().trim();
    if (name.isEmpty) return 'Could not add student (missing name).';

    final age = int.tryParse((a['age'] ?? '').toString().trim()) ?? 0;
    final gradeLevel = (a['gradeLevel'] ?? a['grade'] ?? '').toString().trim();

    final existing = await _findByName(
      col: FirestorePaths.studentsCol(),
      name: name,
    );

    if (existing != null) {
      // Upsert missing fields if needed (do not clobber)
      await existing.reference.set(
        {
          'age': existing.data()?['age'] ?? age,
          'gradeLevel': (existing.data()['gradeLevel'] ?? gradeLevel).toString(),
          'nameLower': name.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return 'Student already existed: $name';
    }

    await FirestorePaths.studentsCol().add({
      'name': name,
      'nameLower': name.toLowerCase(),
      'age': age,
      'gradeLevel': gradeLevel,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return 'Added student: $name';
  }

  static Future<String> _addSubject(Map<String, dynamic> a) async {
    final name = (a['name'] ?? '').toString().trim();
    if (name.isEmpty) return 'Could not add subject (missing name).';

    final existing = await _findByName(
      col: FirestorePaths.subjectsCol(),
      name: name,
    );

    if (existing != null) {
      await existing.reference.set(
        {
          'nameLower': name.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return 'Subject already existed: $name';
    }

    await FirestorePaths.subjectsCol().add({
      'name': name,
      'nameLower': name.toLowerCase(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return 'Added subject: $name';
  }

  static Future<String> _addAssignment(Map<String, dynamic> a) async {
    final name = (a['name'] ?? a['title'] ?? '').toString().trim();
    final due = normalizeDueDate(a['dueDate'] ?? a['due_date']);

    if (name.isEmpty || due.isEmpty) {
      return 'Could not add assignment (missing name or dueDate).';
    }

    // Accept either IDs or names.
    String? studentId = (a['studentId'] ?? a['student_id'])?.toString().trim();
    String? subjectId = (a['subjectId'] ?? a['subject_id'])?.toString().trim();

    // Resolve or create Student by name if needed.
    if (studentId == null || studentId.isEmpty) {
      final studentName = (a['studentName'] ?? a['student_name'] ?? '').toString().trim();
      if (studentName.isEmpty) return 'Could not add assignment (missing studentId or studentName).';

      final match = await _findByName(col: FirestorePaths.studentsCol(), name: studentName);
      if (match != null) {
        studentId = match.id;
      } else {
        final created = await FirestorePaths.studentsCol().add({
          'name': studentName,
          'nameLower': studentName.toLowerCase(),
          'age': 0,
          'gradeLevel': '',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        studentId = created.id;
      }
    }

    // Resolve or create Subject by name if needed.
    if (subjectId == null || subjectId.isEmpty) {
      final subjectName = (a['subjectName'] ?? a['subject_name'] ?? '').toString().trim();
      if (subjectName.isEmpty) return 'Could not add assignment (missing subjectId or subjectName).';

      final match = await _findByName(col: FirestorePaths.subjectsCol(), name: subjectName);
      if (match != null) {
        subjectId = match.id;
      } else {
        final created = await FirestorePaths.subjectsCol().add({
          'name': subjectName,
          'nameLower': subjectName.toLowerCase(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        subjectId = created.id;
      }
    }

    await FirestorePaths.assignmentsCol().add({
      'studentId': studentId,
      'subjectId': subjectId,
      'name': name,
      'dueDate': due,
      'completed': false,
      'grade': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return 'Added assignment: $name (due $due)';
  }

  static Future<String> _completeAssignment(Map<String, dynamic> a) async {
    final id = (a['assignmentId'] ?? a['id'] ?? '').toString().trim();
    if (id.isEmpty) return 'Could not complete assignment (missing assignmentId).';

    final gradeRaw = a['grade'];
    final grade = gradeRaw == null ? null : (int.tryParse(gradeRaw.toString()) ?? 0);

    await FirestorePaths.assignmentsCol().doc(id).set(
      {
        'completed': true,
        'grade': grade,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return grade == null ? 'Marked assignment complete.' : 'Marked assignment complete ($grade%).';
  }

  static Future<String> _undoAssignment(Map<String, dynamic> a) async {
    final id = (a['assignmentId'] ?? a['id'] ?? '').toString().trim();
    if (id.isEmpty) return 'Could not undo assignment (missing assignmentId).';

    await FirestorePaths.assignmentsCol().doc(id).set(
      {
        'completed': false,
        'grade': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return 'Marked assignment incomplete.';
  }

  static Future<String> _deleteAssignment(Map<String, dynamic> a) async {
    final id = (a['assignmentId'] ?? a['id'] ?? '').toString().trim();
    if (id.isEmpty) return 'Could not delete assignment (missing assignmentId).';

    await FirestorePaths.assignmentsCol().doc(id).delete();
    return 'Deleted assignment.';
  }

  // ----------------------------
  // Helpers
  // ----------------------------

  static Map<String, dynamic>? _coerceToMap(dynamic action) {
    if (action == null) return null;

    if (action is Map<String, dynamic>) return action;

    if (action is String) {
      final s = action.trim();
      if (s.isEmpty) return null;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findByName({
    required CollectionReference<Map<String, dynamic>> col,
    required String name,
  }) async {
    final wantLower = name.trim().toLowerCase();
    if (wantLower.isEmpty) return null;

    // Best case: nameLower exists and is indexed.
    try {
      final q = await col.where('nameLower', isEqualTo: wantLower).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first;
    } catch (_) {
      // ignore (field may not exist yet / no index / rules)
    }

    // Fallback: scan small collection.
    final snap = await col.get();
    for (final d in snap.docs) {
      final n = (d.data()['name'] ?? '').toString().trim().toLowerCase();
      if (n == wantLower) return d;
    }
    return null;
  }
}
