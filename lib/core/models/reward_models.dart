// FILE: lib/core/models/reward_models.dart
//
// Models for the reward system: definitions, claims, and tiers.
// Supports student-specific reward assignments.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'models.dart'; // for asInt, asString, asBool

// =====================
// Reward Tier
// =====================
enum RewardTier {
  bronze,
  silver,
  gold,
  platinum;

  String get displayName {
    switch (this) {
      case RewardTier.bronze:
        return 'Bronze';
      case RewardTier.silver:
        return 'Silver';
      case RewardTier.gold:
        return 'Gold';
      case RewardTier.platinum:
        return 'Platinum';
    }
  }

  String get emoji {
    switch (this) {
      case RewardTier.bronze:
        return '🥉';
      case RewardTier.silver:
        return '🥈';
      case RewardTier.gold:
        return '🥇';
      case RewardTier.platinum:
        return '💎';
    }
  }

  /// Auto-assign tier based on point cost
  static RewardTier fromPointCost(int points) {
    if (points >= 3000) return RewardTier.platinum;
    if (points >= 1500) return RewardTier.gold;
    if (points >= 500) return RewardTier.silver;
    return RewardTier.bronze;
  }

  static RewardTier fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'silver':
        return RewardTier.silver;
      case 'gold':
        return RewardTier.gold;
      case 'platinum':
        return RewardTier.platinum;
      case 'bronze':
      default:
        return RewardTier.bronze;
    }
  }
}

// =====================
// Claim Status
// =====================
enum ClaimStatus {
  pending,
  fulfilled;

  String get displayName {
    switch (this) {
      case ClaimStatus.pending:
        return 'Pending';
      case ClaimStatus.fulfilled:
        return 'Fulfilled';
    }
  }

  String get emoji {
    switch (this) {
      case ClaimStatus.pending:
        return 'â³';
      case ClaimStatus.fulfilled:
        return 'âœ“';
    }
  }

  static ClaimStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'fulfilled':
        return ClaimStatus.fulfilled;
      case 'pending':
      default:
        return ClaimStatus.pending;
    }
  }
}

// =====================
// Reward (Definition)
// =====================
/// A reward template created by the parent.
/// Students can claim this reward if they have enough points.
/// 
/// assignedStudentIds:
/// - Empty list = available to ALL students
/// - Non-empty list = only available to those specific students
class Reward {
  final String id;
  final String name;
  final int pointCost;
  final RewardTier tier;
  final String description;
  final bool isActive;
  final int timesClaimedTotal;
  final List<String> assignedStudentIds; // Empty = all students
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Reward({
    required this.id,
    required this.name,
    required this.pointCost,
    required this.tier,
    required this.description,
    required this.isActive,
    required this.timesClaimedTotal,
    required this.assignedStudentIds,
    this.createdAt,
    this.updatedAt,
  });

  /// Whether this reward is available to all students
  bool get isForAllStudents => assignedStudentIds.isEmpty;

  /// Check if this reward is available to a specific student
  bool isAvailableTo(String studentId) {
    if (assignedStudentIds.isEmpty) return true; // Available to all
    return assignedStudentIds.contains(studentId);
  }

  factory Reward.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final pointCost = asInt(data['pointCost'] ?? data['point_cost'], fallback: 0);

    // Parse assignedStudentIds - can be list or null
    List<String> studentIds = [];
    final rawIds = data['assignedStudentIds'] ?? data['assigned_student_ids'];
    if (rawIds is List) {
      studentIds = rawIds.map((e) => e.toString()).toList();
    }

    return Reward(
      id: doc.id,
      name: asString(data['name'], fallback: ''),
      pointCost: pointCost,
      tier: data['tier'] != null
          ? RewardTier.fromString(data['tier'].toString())
          : RewardTier.fromPointCost(pointCost),
      description: asString(data['description'], fallback: ''),
      isActive: asBool(data['isActive'] ?? data['is_active'], fallback: true),
      timesClaimedTotal: asInt(data['timesClaimedTotal'] ?? data['times_claimed_total'], fallback: 0),
      assignedStudentIds: studentIds,
      createdAt: _toDateTime(data['createdAt'] ?? data['created_at']),
      updatedAt: _toDateTime(data['updatedAt'] ?? data['updated_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameLower': name.toLowerCase(),
        'pointCost': pointCost,
        'tier': tier.name,
        'description': description,
        'isActive': isActive,
        'timesClaimedTotal': timesClaimedTotal,
        'assignedStudentIds': assignedStudentIds,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// For creating a new reward (includes createdAt)
  Map<String, dynamic> toCreateMap() => {
        ...toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  Reward copyWith({
    String? id,
    String? name,
    int? pointCost,
    RewardTier? tier,
    String? description,
    bool? isActive,
    int? timesClaimedTotal,
    List<String>? assignedStudentIds,
  }) =>
      Reward(
        id: id ?? this.id,
        name: name ?? this.name,
        pointCost: pointCost ?? this.pointCost,
        tier: tier ?? this.tier,
        description: description ?? this.description,
        isActive: isActive ?? this.isActive,
        timesClaimedTotal: timesClaimedTotal ?? this.timesClaimedTotal,
        assignedStudentIds: assignedStudentIds ?? this.assignedStudentIds,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Whether a student with the given balance can afford this reward
  bool canAfford(int walletBalance) => walletBalance >= pointCost;

  /// How many more points needed to afford this reward
  int pointsNeeded(int walletBalance) =>
      canAfford(walletBalance) ? 0 : pointCost - walletBalance;
}

// =====================
// RewardClaim (Student Redemption)
// =====================
/// A record of a student claiming a reward.
/// Status flows: pending â†’ fulfilled
class RewardClaim {
  final String id;
  final String studentId;
  final String studentName;
  final String rewardId;
  final String rewardName;
  final int pointCost;
  final RewardTier tier;
  final ClaimStatus status;
  final DateTime? claimedAt;
  final DateTime? fulfilledAt;

  const RewardClaim({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.rewardId,
    required this.rewardName,
    required this.pointCost,
    required this.tier,
    required this.status,
    this.claimedAt,
    this.fulfilledAt,
  });

  factory RewardClaim.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return RewardClaim(
      id: doc.id,
      studentId: asString(data['studentId'] ?? data['student_id'], fallback: ''),
      studentName: asString(data['studentName'] ?? data['student_name'], fallback: ''),
      rewardId: asString(data['rewardId'] ?? data['reward_id'], fallback: ''),
      rewardName: asString(data['rewardName'] ?? data['reward_name'], fallback: ''),
      pointCost: asInt(data['pointCost'] ?? data['point_cost'], fallback: 0),
      tier: RewardTier.fromString(data['tier']?.toString()),
      status: ClaimStatus.fromString(data['status']?.toString()),
      claimedAt: _toDateTime(data['claimedAt'] ?? data['claimed_at']),
      fulfilledAt: _toDateTime(data['fulfilledAt'] ?? data['fulfilled_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'rewardId': rewardId,
        'rewardName': rewardName,
        'pointCost': pointCost,
        'tier': tier.name,
        'status': status.name,
        'claimedAt': claimedAt != null ? Timestamp.fromDate(claimedAt!) : FieldValue.serverTimestamp(),
        'fulfilledAt': fulfilledAt != null ? Timestamp.fromDate(fulfilledAt!) : null,
      };

  /// For creating a new claim
  Map<String, dynamic> toCreateMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'rewardId': rewardId,
        'rewardName': rewardName,
        'pointCost': pointCost,
        'tier': tier.name,
        'status': ClaimStatus.pending.name,
        'claimedAt': FieldValue.serverTimestamp(),
        'fulfilledAt': null,
      };

  bool get isPending => status == ClaimStatus.pending;
  bool get isFulfilled => status == ClaimStatus.fulfilled;

  RewardClaim copyWith({
    ClaimStatus? status,
    DateTime? fulfilledAt,
  }) =>
      RewardClaim(
        id: id,
        studentId: studentId,
        studentName: studentName,
        rewardId: rewardId,
        rewardName: rewardName,
        pointCost: pointCost,
        tier: tier,
        status: status ?? this.status,
        claimedAt: claimedAt,
        fulfilledAt: fulfilledAt ?? this.fulfilledAt,
      );
}

// =====================
// Wallet Transaction Extension
// =====================
/// Types of wallet transactions
enum WalletTransactionType {
  deposit,       // Points earned from assignment
  reversal,      // Points reversed when assignment uncompleted
  redemption,    // Points spent on reward
  adjustment,    // Manual adjustment by parent
  streakBonus,   // Bonus from streak milestone
  improvementBonus, // Bonus from WPM improvement
  allocation;    // Points allocated to a specific reward

  static WalletTransactionType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'allocation':
        return WalletTransactionType.allocation;
      case 'reversal':
        return WalletTransactionType.reversal;
      case 'redemption':
        return WalletTransactionType.redemption;
      case 'adjustment':
        return WalletTransactionType.adjustment;
      case 'streak_bonus':
      case 'streakbonus':
        return WalletTransactionType.streakBonus;
      case 'improvement_bonus':
      case 'improvementbonus':
        return WalletTransactionType.improvementBonus;
      case 'deposit':
      default:
        return WalletTransactionType.deposit;
    }
  }
}

/// Extended wallet transaction model for display purposes
class WalletTransaction {
  final String id;
  final WalletTransactionType type;
  final int points;
  final String source;
  final String studentId;
  final String? subjectId;
  final String? subjectName;
  final String? assignmentId;
  final String? assignmentName;
  final String? categoryKey;
  final int? gradePercent;
  final String? courseConfigId;
  final String? rewardId;
  final String? rewardName;
  final String? claimId;
  final String? reason; // For manual adjustments
  final DateTime? createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.points,
    required this.source,
    required this.studentId,
    this.subjectId,
    this.subjectName,
    this.assignmentId,
    this.assignmentName,
    this.categoryKey,
    this.gradePercent,
    this.courseConfigId,
    this.rewardId,
    this.rewardName,
    this.claimId,
    this.reason,
    this.createdAt,
  });

  factory WalletTransaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};

    return WalletTransaction(
      id: doc.id,
      type: WalletTransactionType.fromString(data['type']?.toString()),
      points: asInt(data['points'], fallback: 0),
      source: asString(data['source'], fallback: ''),
      studentId: asString(data['studentId'] ?? data['student_id'], fallback: ''),
      subjectId: data['subjectId']?.toString() ?? data['subject_id']?.toString(),
      subjectName: data['subjectName']?.toString() ?? data['subject_name']?.toString(),
      assignmentId: data['assignmentId']?.toString() ?? data['assignment_id']?.toString(),
      assignmentName: data['assignmentName']?.toString() ?? data['assignment_name']?.toString(),
      categoryKey: data['categoryKey']?.toString() ?? data['category_key']?.toString(),
      gradePercent: data['gradePercent'] != null ? asInt(data['gradePercent']) : null,
      courseConfigId: data['courseConfigId']?.toString() ?? data['course_config_id']?.toString(),
      rewardId: data['rewardId']?.toString() ?? data['reward_id']?.toString(),
      rewardName: data['rewardName']?.toString() ?? data['reward_name']?.toString(),
      claimId: data['claimId']?.toString() ?? data['claim_id']?.toString(),
      reason: data['reason']?.toString(),
      createdAt: _toDateTime(data['createdAt'] ?? data['created_at']),
    );
  }

  bool get isEarning => points > 0;
  bool get isSpending => points < 0;

  String get displayTitle {
    switch (type) {
      case WalletTransactionType.deposit:
        return assignmentName ?? 'Assignment completed';
      case WalletTransactionType.reversal:
        return '${assignmentName ?? 'Assignment'} (reversed)';
      case WalletTransactionType.redemption:
        return rewardName ?? 'Reward claimed';
      case WalletTransactionType.adjustment:
        return reason ?? 'Manual adjustment';
      case WalletTransactionType.streakBonus:
        return 'Streak bonus';
      case WalletTransactionType.improvementBonus:
        return 'Improvement bonus';
      case WalletTransactionType.allocation:
        return rewardName != null ? 'Allocated to $rewardName' : 'Points allocated';
    }
  }

  String get displaySubtitle {
    switch (type) {
      case WalletTransactionType.deposit:
      case WalletTransactionType.reversal:
        return subjectName ?? '';
      case WalletTransactionType.redemption:
        return 'Reward claimed';
      case WalletTransactionType.adjustment:
        return 'Parent adjustment';
      case WalletTransactionType.streakBonus:
        return 'Streak milestone';
      case WalletTransactionType.improvementBonus:
        return 'WPM improvement';
      case WalletTransactionType.allocation:
        return 'Saved for later';
    }
  }
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
