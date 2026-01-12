// FILE: lib/core/models/models.dart
//
// Strongly-typed Firestore models + safe coercion helpers.
// This file intentionally exports normalizeDueDate() for use across the app.

import 'package:cloud_firestore/cloud_firestore.dart';

String _yyyyMmDd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Normalizes Firestore/Date/ISO-like values into "YYYY-MM-DD".
/// Returns '' if null/empty.
String normalizeDueDate(dynamic v) {
  if (v == null) return '';

  if (v is Timestamp) return _yyyyMmDd(v.toDate());
  if (v is DateTime) return _yyyyMmDd(v);

  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return '';

    // Already yyyy-mm-dd
    final simple = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (simple.hasMatch(s)) return s;
        // Handle yyyy-m-d (not padded) -> yyyy-mm-dd
    final loose = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
    
    if (loose != null) {
      final y = loose.group(1)!;
      final m = loose.group(2)!.padLeft(2, '0');
      final d = loose.group(3)!.padLeft(2, '0');
      return '$y-$m-$d';
    }

    // Try parse ISO-ish
    final dt = DateTime.tryParse(s);
    if (dt != null) return _yyyyMmDd(dt.toLocal());

    // Fallback: return original trimmed string
    return s;
  }

  // Fallback for unexpected types
  return v.toString();
}

int asInt(dynamic v, {int fallback = 0}) {
  if (v == null) return fallback;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? fallback;
}

double asDouble(dynamic v, {double fallback = 0}) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

bool asBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;

  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return fallback;
}

String asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}

// =====================
// Student
// =====================
/// `color` is stored as an ARGB int (same as Flutter's Color.value).
/// If `colorValue == 0`, treat as "auto" (fallback palette).
class Student {
  final String id; // Firestore doc id
  final String name;
  final int age;
  final String gradeLevel;

  final int colorValue; // ARGB int; 0 = auto
  final String pin; // optional student PIN
  final String notes; // optional notes

  // Wallet
  final int walletBalance; // points

  const Student({
    required this.id,
    required this.name,
    required this.age,
    required this.gradeLevel,
    required this.colorValue,
    required this.pin,
    required this.notes,
    required this.walletBalance,
  });

  factory Student.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Support both "color" and legacy keys.
    final c = asInt(
      data['color'] ?? data['colorValue'] ?? data['color_value'],
      fallback: 0,
    );

    return Student(
      id: doc.id,
      name: asString(data['name']),
      age: asInt(data['age']),
      gradeLevel: asString(data['gradeLevel'] ?? data['grade_level'] ?? data['grade']),
      colorValue: c,
      pin: asString(data['pin'], fallback: ''),
      notes: asString(data['notes'], fallback: ''),
      walletBalance: asInt(data['walletBalance'] ?? data['wallet_balance'], fallback: 0),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'age': age,
        'gradeLevel': gradeLevel,
        'color': colorValue,
        'pin': pin,
        'notes': notes,
        'walletBalance': walletBalance,
      };
}

// =====================
// Subject
// =====================
class Subject {
  final String id; // Firestore doc id
  final String name;

  /// Optional: ties a subject to a course config doc (e.g. "general_chemistry_v1").
  final String courseConfigId;

  const Subject({
    required this.id,
    required this.name,
    required this.courseConfigId,
  });

  factory Subject.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Subject(
      id: doc.id,
      name: asString(data['name']),
      courseConfigId: asString(data['courseConfigId'] ?? data['course_config_id'], fallback: ''),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'courseConfigId': courseConfigId,
      };
}

// =====================
// Assignment
// =====================
class Assignment {
  final String id; // Firestore doc id

  // Firestore relationship ids
  final String studentId; // Firestore doc id
  final String subjectId; // Firestore doc id

  // Core fields
  final String name;
  final String dueDate; // normalized "YYYY-MM-DD"
  final bool isCompleted;
  final int? grade;

  // Chemistry / rubric metadata (safe for other subjects too)
  final String categoryKey; // e.g. reading_set, problem_set, topic_test
  final int pointsPossible; // optional, can be 0
  final double weight; // optional (future grading)
  final String courseConfigId; // optional override on assignment doc

  // Wallet tracking (optional)
  final String rewardTxnId; // deposit txn id (if applied)
  final int rewardPointsApplied; // points actually deposited for this assignment

  // Resolved display names (optional)
  final String studentName;
  final String subjectName;

  const Assignment({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.name,
    required this.dueDate,
    required this.isCompleted,
    required this.grade,
    required this.categoryKey,
    required this.pointsPossible,
    required this.weight,
    required this.courseConfigId,
    required this.rewardTxnId,
    required this.rewardPointsApplied,
    required this.studentName,
    required this.subjectName,
  });

  factory Assignment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    Map<String, Student>? studentsById,
    Map<String, Subject>? subjectsById,
  }) {
    final data = doc.data() ?? <String, dynamic>{};

    final sid = asString(data['studentId'] ?? data['student_id']);
    final subid = asString(data['subjectId'] ?? data['subject_id']);

    // Prefer resolved names from maps; fallback to stored names; fallback to ''
    final resolvedStudentName = studentsById?[sid]?.name ??
        asString(data['studentName'] ?? data['student_name'], fallback: '');

    final resolvedSubjectName = subjectsById?[subid]?.name ??
        asString(data['subjectName'] ?? data['subject_name'], fallback: '');

    return Assignment(
      id: doc.id,
      studentId: sid,
      subjectId: subid,
      name: asString(data['name'] ?? data['title'] ?? data['assignment_name']),
      dueDate: normalizeDueDate(data['dueDate'] ?? data['due_date']),
      isCompleted: asBool(data['completed'] ?? data['isCompleted'] ?? data['is_completed']),
      grade: data['grade'] == null ? null : asInt(data['grade'], fallback: 0),

      categoryKey: asString(data['categoryKey'] ?? data['category_key'], fallback: ''),
      pointsPossible: asInt(data['pointsPossible'] ?? data['points_possible'], fallback: 0),
      weight: asDouble(data['weight'], fallback: 1.0),
      courseConfigId: asString(data['courseConfigId'] ?? data['course_config_id'], fallback: ''),

      rewardTxnId: asString(data['rewardTxnId'] ?? data['reward_txn_id'], fallback: ''),
      rewardPointsApplied: asInt(data['rewardPointsApplied'] ?? data['reward_points_applied'], fallback: 0),

      studentName: resolvedStudentName,
      subjectName: resolvedSubjectName,
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'subjectId': subjectId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'dueDate': dueDate,
        'completed': isCompleted,
        'grade': grade,

        'categoryKey': categoryKey,
        'pointsPossible': pointsPossible,
        'weight': weight,
        'courseConfigId': courseConfigId,

        'rewardTxnId': rewardTxnId,
        'rewardPointsApplied': rewardPointsApplied,
      };
}
