// FILE: lib/services/group_reward_service_extension.dart
//
// Extension methods for RewardService to manage group rewards.
// Add these methods to your existing RewardService class.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/group_reward_model.dart';
import '../firestore_paths.dart';

extension GroupRewardServiceExtension on RewardService {
  
  // ========================================
  // Group Reward CRUD (Parent)
  // ========================================

  /// Create a new group reward
  /// allowedStudentIds: empty list = all students, or list of specific student IDs
  Future<GroupReward> createGroupReward({
    required String name,
    required int pointsNeeded,
    String description = '',
    List<String> allowedStudentIds = const [],
    DateTime? expiresAt,
  }) async {
    final docRef = FirestorePaths.groupRewardsCol().doc();

    final groupReward = GroupReward(
      id: docRef.id,
      name: name,
      pointsNeeded: pointsNeeded,
      pointsContributed: 0,
      description: description,
      isActive: true,
      isRedeemed: false,
      allowedStudentIds: allowedStudentIds,
      studentContributions: {},
      expiresAt: expiresAt,
    );

    await docRef.set(groupReward.toCreateMap());
    return groupReward;
  }

  /// Update an existing group reward
  Future<void> updateGroupReward({
    required String groupRewardId,
    String? name,
    int? pointsNeeded,
    String? description,
    bool? isActive,
    List<String>? allowedStudentIds,
    DateTime? expiresAt,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      updates['name'] = name;
      updates['nameLower'] = name.toLowerCase();
    }
    if (pointsNeeded != null) updates['pointsNeeded'] = pointsNeeded;
    if (description != null) updates['description'] = description;
    if (isActive != null) updates['isActive'] = isActive;
    if (allowedStudentIds != null) updates['allowedStudentIds'] = allowedStudentIds;
    if (expiresAt != null) updates['expiresAt'] = expiresAt;

    await FirestorePaths.groupRewardDoc(groupRewardId).update(updates);
  }

  /// Disable a group reward
  Future<void> disableGroupReward(String groupRewardId) async {
    await updateGroupReward(groupRewardId: groupRewardId, isActive: false);
  }

  /// Enable a group reward
  Future<void> enableGroupReward(String groupRewardId) async {
    await updateGroupReward(groupRewardId: groupRewardId, isActive: true);
  }

  /// Delete a group reward permanently
  Future<void> deleteGroupReward(String groupRewardId) async {
    await FirestorePaths.groupRewardDoc(groupRewardId).delete();
  }

  /// Mark a group reward as redeemed and lock contributions
  Future<void> redeemGroupReward(String groupRewardId) async {
    await FirestorePaths.groupRewardDoc(groupRewardId).update({
      'isRedeemed': true,
      'isActive': false,
      'redeemedAt': FieldValue.serverTimestamp(),
    });
  }

  // ========================================
  // Group Reward Retrieval
  // ========================================

  /// Get a single group reward
  Future<GroupReward?> getGroupReward(String groupRewardId) async {
    final snap = await FirestorePaths.groupRewardDoc(groupRewardId).get();
    if (!snap.exists) return null;
    return GroupReward.fromDoc(snap);
  }

  /// Get all active group rewards
  Future<List<GroupReward>> getActiveGroupRewards() async {
    final snap = await FirestorePaths.groupRewardsCol().get();
    final rewards = snap.docs.map((d) => GroupReward.fromDoc(d)).toList();
    // Filter and sort in memory
    final active = rewards.where((r) => r.isActive && !r.isRedeemed).toList();
    active.sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
    return active;
  }

  /// Get active group rewards available to a specific student
  Future<List<GroupReward>> getActiveGroupRewardsForStudent(String studentId) async {
    final allRewards = await getActiveGroupRewards();
    return allRewards.where((r) => r.isAvailableTo(studentId)).toList();
  }

  /// Get completed/redeemed group rewards
  Future<List<GroupReward>> getRedeemedGroupRewards() async {
    final snap = await FirestorePaths.groupRewardsCol().get();
    final rewards = snap.docs.map((d) => GroupReward.fromDoc(d)).toList();
    final redeemed = rewards.where((r) => r.isRedeemed).toList();
    redeemed.sort((a, b) {
      final aDate = a.redeemedAt ?? DateTime(1970);
      final bDate = b.redeemedAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return redeemed;
  }

  /// Get all group rewards (including inactive/redeemed) for admin
  Future<List<GroupReward>> getAllGroupRewards() async {
    final snap = await FirestorePaths.groupRewardsCol().get();
    final rewards = snap.docs.map((d) => GroupReward.fromDoc(d)).toList();
    rewards.sort((a, b) => a.pointsNeeded.compareTo(b.pointsNeeded));
    return rewards;
  }

  // ========================================
  // Group Reward Streaming
  // ========================================

  /// Stream active group rewards (for admin)
  Stream<List<GroupReward>> streamActiveGroupRewards() {
    return FirestorePaths.groupRewardsCol()
        .snapshots()
        .map((snap) {
          final rewards = snap.docs.map((d) => GroupReward.fromDoc(d)).toList();
          final active = rewards.where((r) => r.isActive && !r.isRedeemed).toList();
          active.sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
          return active;
        });
  }

  /// Stream active group rewards available to a specific student
  Stream<List<GroupReward>> streamActiveGroupRewardsForStudent(String studentId) {
    return FirestorePaths.groupRewardsCol()
        .snapshots()
        .map((snap) {
          final rewards = snap.docs.map((d) => GroupReward.fromDoc(d)).toList();
          final filtered = rewards
              .where((r) => r.isActive && !r.isRedeemed && r.isAvailableTo(studentId))
              .toList();
          filtered.sort((a, b) => b.progressPercent.compareTo(a.progressPercent));
          return filtered;
        });
  }

  /// Stream a specific group reward for real-time updates
  Stream<GroupReward?> streamGroupReward(String groupRewardId) {
    return FirestorePaths.groupRewardDoc(groupRewardId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return GroupReward.fromDoc(snap);
        });
  }

  // ========================================
  // Student Contribution
  // ========================================

  /// Contribute points to a group reward
  /// Returns the updated GroupReward
  Future<GroupReward> contributeToGroupReward({
    required String groupRewardId,
    required String studentId,
    required int points,
  }) async {
    if (points <= 0) {
      throw ArgumentError('Points must be greater than 0');
    }

    // Get current group reward
    final current = await getGroupReward(groupRewardId);
    if (current == null) {
      throw Exception('Group reward not found');
    }

    // Verify student can contribute
    if (!current.isAvailableTo(studentId)) {
      throw Exception('Student is not allowed to contribute to this reward');
    }

    if (!current.isActive || current.isRedeemed) {
      throw Exception('This group reward is no longer active');
    }

    if (current.isExpired) {
      throw Exception('This group reward has expired');
    }

    // Get student's wallet balance
    final balance = await getWalletBalance(studentId);
    if (balance < points) {
      throw InsufficientBalanceException(required: points, available: balance);
    }

    // Calculate new totals
    final newContributed = current.pointsContributed + points;
    final newClamped = newContributed.clamp(0, current.pointsNeeded);
    
    // Update student contributions
    final updatedContributions = Map<String, int>.from(current.studentContributions);
    updatedContributions[studentId] = (updatedContributions[studentId] ?? 0) + points;

    // Update group reward
    await FirestorePaths.groupRewardDoc(groupRewardId).update({
      'pointsContributed': newClamped,
      'studentContributions': updatedContributions,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Deduct points from student wallet
    await adjustWalletBalance(
      studentId: studentId,
      points: -points,
      reason: 'Contributed to group reward: ${current.name}',
    );

    // Return updated reward
    return (await getGroupReward(groupRewardId))!;
  }

  /// Get a student's total contribution to all group rewards
  Future<int> getStudentTotalGroupContribution(String studentId) async {
    final rewards = await getAllGroupRewards();
    int total = 0;
    for (final reward in rewards) {
      total += reward.getStudentContribution(studentId);
    }
    return total;
  }

  /// Get leaderboard of top contributors to a specific group reward
  Future<List<MapEntry<String, int>>> getGroupRewardContributorLeaderboard(
    String groupRewardId,
  ) async {
    final reward = await getGroupReward(groupRewardId);
    if (reward == null) return [];

    final entries = reward.studentContributions.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  /// Get student's rank among contributors for a group reward
  Future<int?> getStudentContributorRank(
    String groupRewardId,
    String studentId,
  ) async {
    final leaderboard = await getGroupRewardContributorLeaderboard(groupRewardId);
    for (int i = 0; i < leaderboard.length; i++) {
      if (leaderboard[i].key == studentId) {
        return i + 1;
      }
    }
    return null; // Student hasn't contributed
  }

  // ========================================
  // Group Reward Transaction Tracking
  // ========================================

  /// Record a contribution to a group reward in the wallet history
  /// (Already handled by contributeToGroupReward via adjustWalletBalance)
  /// This is a helper to show contribution details
  Future<int> getGroupRewardContributionCount(String studentId) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId).get();
    int count = 0;
    for (final doc in snap.docs) {
      final reason = doc.data()['reason']?.toString() ?? '';
      if (reason.contains('group reward') || reason.contains('Group reward')) {
        count++;
      }
    }
    return count;
  }
}
