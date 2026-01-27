// FILE: lib/core/models/models.dart
//
// Strongly-typed Firestore models + safe coercion helpers.
// This file intentionally exports normalizeDueDate() for use across the app.
//
// UPDATED:
// - ✅ Fixed duplicate _yyyyMmDd() definition
// - ✅ AssignmentAttempt.toMap() no longer uses FieldValue.serverTimestamp()
//   (serverTimestamp is NOT allowed inside array items; use Timestamp.now() instead)
// - ✅ More robust attempts parsing (Map casting)

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

DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;

  // Common if something exported to JSON or stored as epoch millis:
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);

  if (v is String) return DateTime.tryParse(v);
  return null;
}

// =====================
// AssignmentAttempt (for retest tracking)
// =====================
class AssignmentAttempt {
  final int grade;

  /// Local date string for easy grouping/sorting: "YYYY-MM-DD"
  final String date;

  /// Precise moment of attempt (stored as Firestore Timestamp)
  final DateTime? timestamp;

  const AssignmentAttempt({
    required this.grade,
    required this.date,
    this.timestamp,
  });

  factory AssignmentAttempt.fromMap(Map<String, dynamic> data) {
    final ts = _toDateTime(data['timestamp']);
    final rawDate = asString(data['date'], fallback: '');

    // If date wasn't stored (older data), derive it from timestamp if possible.
    final normalizedDate = rawDate.isNotEmpty ? rawDate : (ts != null ? _yyyyMmDd(ts) : '');

    return AssignmentAttempt(
      grade: asInt(data['grade'], fallback: 0),
      date: normalizedDate,
      timestamp: ts,
    );
  }

  Map<String, dynamic> toMap() {
    // Ensure date is always filled even if caller passed ''.
    final safeDate = date.isNotEmpty ? date : _yyyyMmDd(DateTime.now());

    return <String, dynamic>{
      'grade': grade,
      'date': safeDate,

      // IMPORTANT:
      // Firestore does NOT allow FieldValue.serverTimestamp() inside an array item.
      // Since attempts is stored as a LIST on the assignment doc, we must store a real Timestamp.
      'timestamp': timestamp != null ? Timestamp.fromDate(timestamp!) : Timestamp.now(),
    };
  }
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
  final Map<String, int> rewardAllocations; // rewardId -> points allocated

  // Streak tracking (student-level, across all subjects)
  final int currentStreak; // consecutive days with at least 1 completion
  final int longestStreak; // all-time best streak
  final String lastCompletionDate; // "YYYY-MM-DD" of last completed assignment
  final String profilePictureUrl; // URL to profile picture in Firebase Storage

  const Student({
    required this.id,
    required this.name,
    required this.age,
    required this.gradeLevel,
    required this.colorValue,
    required this.pin,
    required this.notes,
    required this.walletBalance,
    this.rewardAllocations = const {},
    required this.currentStreak,
    required this.longestStreak,
    required this.lastCompletionDate,
    required this.profilePictureUrl,
  });

  factory Student.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Support both "color" and legacy keys.
    final c = asInt(
      data['color'] ?? data['colorValue'] ?? data['color_value'],
      fallback: 0,
    );

    // Parse reward allocations
    Map<String, int> allocations = {};
    final rawAllocations = data['rewardAllocations'] ?? data['reward_allocations'];
    if (rawAllocations is Map) {
      rawAllocations.forEach((key, value) {
        allocations[key.toString()] = asInt(value, fallback: 0);
      });
    }

    return Student(
      id: doc.id,
      name: asString(data['name']),
      age: asInt(data['age']),
      gradeLevel: asString(data['gradeLevel'] ?? data['grade_level'] ?? data['grade']),
      colorValue: c,
      pin: asString(data['pin'], fallback: ''),
      notes: asString(data['notes'], fallback: ''),
      walletBalance: asInt(data['walletBalance'] ?? data['wallet_balance'], fallback: 0),
      rewardAllocations: allocations,
      currentStreak: asInt(data['currentStreak'] ?? data['current_streak'], fallback: 0),
      longestStreak: asInt(data['longestStreak'] ?? data['longest_streak'], fallback: 0),
      lastCompletionDate: normalizeDueDate(data['lastCompletionDate'] ?? data['last_completion_date']),
      profilePictureUrl: asString(data['profilePictureUrl'] ?? data['profile_picture_url'], fallback: ''),
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
        'rewardAllocations': rewardAllocations,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastCompletionDate': lastCompletionDate,
        'profilePictureUrl': profilePictureUrl,
      };

  /// Calculate streak bonus percentage based on current streak
  /// 3 days = 5%, 7 days = 10%, 14 days = 15%, 30 days = 20%
  double get streakBonusPercent {
    if (currentStreak >= 30) return 0.20;
    if (currentStreak >= 14) return 0.15;
    if (currentStreak >= 7) return 0.10;
    if (currentStreak >= 3) return 0.05;
    return 0.0;
  }

  Student copyWith({
    String? id,
    String? name,
    int? age,
    String? gradeLevel,
    int? colorValue,
    String? pin,
    String? notes,
    int? walletBalance,
    Map<String, int>? rewardAllocations,
    int? currentStreak,
    int? longestStreak,
    String? lastCompletionDate,
    String? profilePictureUrl,
  }) =>
      Student(
        id: id ?? this.id,
        name: name ?? this.name,
        age: age ?? this.age,
        gradeLevel: gradeLevel ?? this.gradeLevel,
        colorValue: colorValue ?? this.colorValue,
        pin: pin ?? this.pin,
        notes: notes ?? this.notes,
        walletBalance: walletBalance ?? this.walletBalance,
        rewardAllocations: rewardAllocations ?? this.rewardAllocations,
        currentStreak: currentStreak ?? this.currentStreak,
        longestStreak: longestStreak ?? this.longestStreak,
        lastCompletionDate: lastCompletionDate ?? this.lastCompletionDate,
        profilePictureUrl: profilePictureUrl ?? this.profilePictureUrl,
      );
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
// AssignmentAttachment
// =====================
class AssignmentAttachment {
  final String url;
  final String name;
  final String type; // 'image', 'pdf', etc.

  const AssignmentAttachment({
    required this.url,
    required this.name,
    required this.type,
  });

  factory AssignmentAttachment.fromMap(Map<String, dynamic> map) {
    return AssignmentAttachment(
      url: asString(map['url']),
      name: asString(map['name']),
      type: asString(map['type']),
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'name': name,
        'type': type,
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
  final String dueDate; // normalized "YYYY-MM-DD" - when it should be done
  final String completionDate; // normalized "YYYY-MM-DD" - when it was actually done
  final bool isCompleted;
  final int? grade; // current/best grade (0-100)

  // Course config link (for curriculum-based assignments)
  final String courseConfigId; // e.g. "saxon-math-76"
  final String categoryKey; // e.g. "lesson", "test", "practice"
  final int orderInCourse; // position in curriculum sequence (1, 2, 3...)

  // Points
  final int pointsBase; // base points from category or manual entry
  final int pointsEarned; // actual points after grade multiplier + streak bonus
  final bool gradable; // does this assignment require a grade?

  // Legacy/compatibility (maps to pointsBase)
  final int pointsPossible;
  final double weight; // optional (future grading)

  // Retest tracking
  final List<AssignmentAttempt> attempts; // history of all attempts
  final int? bestGrade; // highest grade across all attempts

  // Wallet tracking
  final String rewardTxnId; // deposit txn id (if applied)
  final int rewardPointsApplied; // points actually deposited for this assignment

  // Resolved display names (optional)
  final String studentName;
  final String subjectName;

  // Attachments
  final List<AssignmentAttachment> attachments;

  const Assignment({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.name,
    required this.dueDate,
    required this.completionDate,
    required this.isCompleted,
    required this.grade,
    required this.courseConfigId,
    required this.categoryKey,
    required this.orderInCourse,
    required this.pointsBase,
    required this.pointsEarned,
    required this.gradable,
    required this.pointsPossible,
    required this.weight,
    required this.attempts,
    required this.bestGrade,
    required this.rewardTxnId,
    required this.rewardPointsApplied,
    required this.studentName,
    required this.subjectName,
    required this.attachments,
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
    final resolvedStudentName =
        studentsById?[sid]?.name ?? asString(data['studentName'] ?? data['student_name'], fallback: '');

    final resolvedSubjectName =
        subjectsById?[subid]?.name ?? asString(data['subjectName'] ?? data['subject_name'], fallback: '');

    // Parse attempts list (robust casting)
    final attemptsRaw = data['attempts'];
    final attemptsList = <AssignmentAttempt>[];
    if (attemptsRaw is List) {
      for (final a in attemptsRaw) {
        if (a is Map) {
          final map = Map<String, dynamic>.from(a);
          attemptsList.add(AssignmentAttempt.fromMap(map));
        }
      }
    }

    // pointsBase: prefer new field, fallback to pointsPossible
    final pBase = asInt(
      data['pointsBase'] ?? data['points_base'] ?? data['pointsPossible'] ?? data['points_possible'],
      fallback: 0,
    );

    // Attachments parsing
    final attachmentsList = <AssignmentAttachment>[];
    final attachmentsRaw = data['attachments'];
    if (attachmentsRaw is List) {
      for (final a in attachmentsRaw) {
        if (a is Map) {
          attachmentsList.add(AssignmentAttachment.fromMap(Map<String, dynamic>.from(a)));
        }
      }
    }

    // Backward compatibility for single attachmentUrl
    final legacyUrl = asString(data['attachmentUrl'] ?? data['attachment_url']);
    if (legacyUrl.isNotEmpty && attachmentsList.isEmpty) {
      attachmentsList.add(AssignmentAttachment(
        url: legacyUrl,
        name: 'Attachment',
        type: legacyUrl.toLowerCase().contains('.pdf') ? 'pdf' : 'image',
      ));
    }

    return Assignment(
      id: doc.id,
      studentId: sid,
      subjectId: subid,
      name: asString(data['name'] ?? data['title'] ?? data['assignment_name']),
      dueDate: normalizeDueDate(data['dueDate'] ?? data['due_date']),
      completionDate: normalizeDueDate(data['completionDate'] ?? data['completion_date']),
      isCompleted: asBool(data['completed'] ?? data['isCompleted'] ?? data['is_completed']),
      grade: data['grade'] == null ? null : asInt(data['grade'], fallback: 0),
      courseConfigId: asString(data['courseConfigId'] ?? data['course_config_id'], fallback: ''),
      categoryKey: asString(data['categoryKey'] ?? data['category_key'], fallback: ''),
      orderInCourse: asInt(data['orderInCourse'] ?? data['order_in_course'], fallback: 0),
      pointsBase: pBase,
      pointsEarned: asInt(data['pointsEarned'] ?? data['points_earned'], fallback: 0),
      gradable: asBool(data['gradable'], fallback: true), // default to gradable
      pointsPossible: pBase, // legacy compatibility
      weight: asDouble(data['weight'], fallback: 1.0),
      attempts: attemptsList,
      bestGrade: data['bestGrade'] == null ? null : asInt(data['bestGrade'], fallback: 0),
      rewardTxnId: asString(data['rewardTxnId'] ?? data['reward_txn_id'], fallback: ''),
      rewardPointsApplied: asInt(data['rewardPointsApplied'] ?? data['reward_points_applied'], fallback: 0),
      studentName: resolvedStudentName,
      subjectName: resolvedSubjectName,
      attachments: attachmentsList,
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'subjectId': subjectId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'dueDate': dueDate,
        'completionDate': completionDate,
        'completed': isCompleted,
        'grade': grade,
        'courseConfigId': courseConfigId,
        'categoryKey': categoryKey,
        'orderInCourse': orderInCourse,
        'pointsBase': pointsBase,
        'pointsEarned': pointsEarned,
        'gradable': gradable,

        // Legacy compatibility
        'pointsPossible': pointsBase,
        'weight': weight,

        // NOTE: attempts is an array of maps; do NOT put FieldValue.serverTimestamp() inside these maps.
        'attempts': attempts.map((a) => a.toMap()).toList(),
        'bestGrade': bestGrade,
        'rewardTxnId': rewardTxnId,
        'rewardPointsApplied': rewardPointsApplied,
        'attachments': attachments.map((a) => a.toMap()).toList(),
      };

  Assignment copyWith({
    String? id,
    String? studentId,
    String? subjectId,
    String? name,
    String? dueDate,
    String? completionDate,
    bool? isCompleted,
    int? grade,
    String? courseConfigId,
    String? categoryKey,
    int? orderInCourse,
    int? pointsBase,
    int? pointsEarned,
    bool? gradable,
    int? pointsPossible,
    double? weight,
    List<AssignmentAttempt>? attempts,
    int? bestGrade,
    String? rewardTxnId,
    int? rewardPointsApplied,
    String? studentName,
    String? subjectName,
    List<AssignmentAttachment>? attachments,
  }) =>
      Assignment(
        id: id ?? this.id,
        studentId: studentId ?? this.studentId,
        subjectId: subjectId ?? this.subjectId,
        name: name ?? this.name,
        dueDate: dueDate ?? this.dueDate,
        completionDate: completionDate ?? this.completionDate,
        isCompleted: isCompleted ?? this.isCompleted,
        grade: grade ?? this.grade,
        courseConfigId: courseConfigId ?? this.courseConfigId,
        categoryKey: categoryKey ?? this.categoryKey,
        orderInCourse: orderInCourse ?? this.orderInCourse,
        pointsBase: pointsBase ?? this.pointsBase,
        pointsEarned: pointsEarned ?? this.pointsEarned,
        gradable: gradable ?? this.gradable,
        pointsPossible: pointsPossible ?? this.pointsPossible,
        weight: weight ?? this.weight,
        attempts: attempts ?? this.attempts,
        bestGrade: bestGrade ?? this.bestGrade,
        rewardTxnId: rewardTxnId ?? this.rewardTxnId,
        rewardPointsApplied: rewardPointsApplied ?? this.rewardPointsApplied,
        studentName: studentName ?? this.studentName,
        subjectName: subjectName ?? this.subjectName,
        attachments: attachments ?? this.attachments,
      );
}






