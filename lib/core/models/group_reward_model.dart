// FILE: lib/core/models/group_reward_model.dart
//
// Group Reward model for collaborative rewards all students can contribute to.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart'; // for asInt, asString, asBool

// =====================
// Group Reward
// =====================
/// A group reward that all students can contribute points towards.
/// Tracks total points needed, points contributed, and student contributions.
class GroupReward {
  final String id;
  final String name;
  final int pointsNeeded;
  final int pointsContributed;
  final String description;
  final bool isActive;
  final bool isRedeemed;
  final List<String> allowedStudentIds; // Empty = all students can contribute
  final Map<String, int> studentContributions; // studentId -> points contributed
  final DateTime? createdAt;
  final DateTime? redeemedAt;
  final DateTime? expiresAt;

  const GroupReward({
    required this.id,
    required this.name,
    required this.pointsNeeded,
    required this.pointsContributed,
    required this.description,
    required this.isActive,
    required this.isRedeemed,
    required this.allowedStudentIds,
    required this.studentContributions,
    this.createdAt,
    this.redeemedAt,
    this.expiresAt,
  });

  /// Whether this reward is available to all students
  bool get isForAllStudents => allowedStudentIds.isEmpty;

  /// Check if this reward is available to a specific student
  bool isAvailableTo(String studentId) {
    if (allowedStudentIds.isEmpty) return true;
    return allowedStudentIds.contains(studentId);
  }

  /// Get progress percentage (0-100)
  int get progressPercent {
    if (pointsNeeded == 0) return 0;
    return ((pointsContributed / pointsNeeded) * 100).toInt();
  }

  /// Whether the group reward has been fully funded
  bool get isCompleted => pointsContributed >= pointsNeeded;

  /// Get points remaining to complete the reward
  int get pointsRemaining => (pointsNeeded - pointsContributed).clamp(0, pointsNeeded);

  /// Get how much a student has contributed
  int getStudentContribution(String studentId) {
    return studentContributions[studentId] ?? 0;
  }

  /// Get list of students who have contributed
  List<String> get contributors => studentContributions.entries
      .where((e) => e.value > 0)
      .map((e) => e.key)
      .toList();

  /// Get number of students who have contributed
  int get contributorCount =>
      studentContributions.values.where((v) => v > 0).length;

  /// Check if student is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  factory GroupReward.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    // Parse allowedStudentIds
    List<String> studentIds = [];
    final rawIds = data['allowedStudentIds'] ?? data['allowed_student_ids'];
    if (rawIds is List) {
      studentIds = rawIds.map((e) => e.toString()).toList();
    }

    // Parse student contributions
    Map<String, int> contributions = {};
    final rawContribs = data['studentContributions'] ?? data['student_contributions'];
    if (rawContribs is Map) {
      rawContribs.forEach((key, value) {
        contributions[key.toString()] = asInt(value, fallback: 0);
      });
    }

    return GroupReward(
      id: doc.id,
      name: asString(data['name'], fallback: ''),
      pointsNeeded: asInt(data['pointsNeeded'] ?? data['points_needed'], fallback: 0),
      pointsContributed: asInt(data['pointsContributed'] ?? data['points_contributed'], fallback: 0),
      description: asString(data['description'], fallback: ''),
      isActive: asBool(data['isActive'] ?? data['is_active'], fallback: true),
      isRedeemed: asBool(data['isRedeemed'] ?? data['is_redeemed'], fallback: false),
      allowedStudentIds: studentIds,
      studentContributions: contributions,
      createdAt: _toDateTime(data['createdAt'] ?? data['created_at']),
      redeemedAt: _toDateTime(data['redeemedAt'] ?? data['redeemed_at']),
      expiresAt: _toDateTime(data['expiresAt'] ?? data['expires_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'pointsNeeded': pointsNeeded,
        'pointsContributed': pointsContributed,
        'description': description,
        'isActive': isActive,
        'isRedeemed': isRedeemed,
        'allowedStudentIds': allowedStudentIds,
        'studentContributions': studentContributions,
        'expiresAt': expiresAt,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// For creating a new group reward
  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  GroupReward copyWith({
    String? id,
    String? name,
    int? pointsNeeded,
    int? pointsContributed,
    String? description,
    bool? isActive,
    bool? isRedeemed,
    List<String>? allowedStudentIds,
    Map<String, int>? studentContributions,
    DateTime? expiresAt,
  }) =>
      GroupReward(
        id: id ?? this.id,
        name: name ?? this.name,
        pointsNeeded: pointsNeeded ?? this.pointsNeeded,
        pointsContributed: pointsContributed ?? this.pointsContributed,
        description: description ?? this.description,
        isActive: isActive ?? this.isActive,
        isRedeemed: isRedeemed ?? this.isRedeemed,
        allowedStudentIds: allowedStudentIds ?? this.allowedStudentIds,
        studentContributions: studentContributions ?? this.studentContributions,
        createdAt: createdAt,
        redeemedAt: redeemedAt,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

// =====================
// Helper
// =====================
DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}
