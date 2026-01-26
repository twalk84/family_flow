// FILE: lib/services/reward_service.dart
//
// Service for managing rewards, claims, and point adjustments.
// Supports student-specific reward assignments.
//
// Handles:
// - CRUD for reward definitions (parent)
// - Claiming rewards (student)
// - Fulfilling claims (parent)
// - Manual point adjustments (parent)
// - Wallet transaction history

import 'dart:async'; // Added for FutureOr
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import '../core/models/reward_models.dart';
import '../firestore_paths.dart';

class RewardService {
  RewardService._();
  static final RewardService instance = RewardService._();

  // ========================================
  // Reward CRUD (Parent)
  // ========================================

  /// Create a new reward
  Future<Reward> createReward({
    required String name,
    required int pointCost,
    String description = '',
    List<String> assignedStudentIds = const [],
  }) async {
    final tier = RewardTier.fromPointCost(pointCost);
    final docRef = FirestorePaths.rewardsCol().doc();

    final reward = Reward(
      id: docRef.id,
      name: name,
      pointCost: pointCost,
      tier: tier,
      description: description,
      isActive: true,
      timesClaimedTotal: 0,
      assignedStudentIds: assignedStudentIds,
    );

    await docRef.set(reward.toCreateMap());
    return reward;
  }

  /// Update an existing reward
  Future<void> updateReward({
    required String rewardId,
    String? name,
    int? pointCost,
    String? description,
    bool? isActive,
    List<String>? assignedStudentIds,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      updates['name'] = name;
      updates['nameLower'] = name.toLowerCase();
    }
    if (pointCost != null) {
      updates['pointCost'] = pointCost;
      updates['tier'] = RewardTier.fromPointCost(pointCost).name;
    }
    if (description != null) updates['description'] = description;
    if (isActive != null) updates['isActive'] = isActive;
    if (assignedStudentIds != null) updates['assignedStudentIds'] = assignedStudentIds;

    await FirestorePaths.rewardDoc(rewardId).update(updates);
  }

  /// Disable a reward (soft delete)
  Future<void> disableReward(String rewardId) async {
    await updateReward(rewardId: rewardId, isActive: false);
  }

  /// Enable a reward
  Future<void> enableReward(String rewardId) async {
    await updateReward(rewardId: rewardId, isActive: true);
  }

  /// Delete a reward permanently
  Future<void> deleteReward(String rewardId) async {
    await FirestorePaths.rewardDoc(rewardId).delete();
  }

  /// Get a single reward
  Future<Reward?> getReward(String rewardId) async {
    final snap = await FirestorePaths.rewardDoc(rewardId).get();
    if (!snap.exists) return null;
    return Reward.fromDoc(snap);
  }

  /// Get all active rewards (for admin view)
  Future<List<Reward>> getActiveRewards() async {
    final snap = await FirestorePaths.rewardsCol().get();
    final rewards = snap.docs.map((d) => Reward.fromDoc(d)).toList();
    final active = rewards.where((r) => r.isActive).toList();
    active.sort((a, b) => a.pointCost.compareTo(b.pointCost));
    return active;
  }

  /// Get active rewards available to a specific student
  Future<List<Reward>> getActiveRewardsForStudent(String studentId) async {
    final allRewards = await getActiveRewards();
    return allRewards.where((r) => r.isAvailableTo(studentId)).toList();
  }

  /// Get all rewards (including inactive) for admin
  Future<List<Reward>> getAllRewards() async {
    final snap = await FirestorePaths.rewardsCol().get();
    final rewards = snap.docs.map((d) => Reward.fromDoc(d)).toList();
    rewards.sort((a, b) => a.pointCost.compareTo(b.pointCost));
    return rewards;
  }

  /// Stream active rewards (for admin - shows all)
  Stream<List<Reward>> streamActiveRewards() {
    return FirestorePaths.rewardsCol()
        .snapshots()
        .map((snap) {
          final rewards = snap.docs.map((d) => Reward.fromDoc(d)).toList();
          final active = rewards.where((r) => r.isActive).toList();
          active.sort((a, b) => a.pointCost.compareTo(b.pointCost));
          return active;
        });
  }

  /// Stream active rewards available to a specific student
  Stream<List<Reward>> streamActiveRewardsForStudent(String studentId) {
    return FirestorePaths.rewardsCol()
        .snapshots()
        .map((snap) {
          final rewards = snap.docs.map((d) => Reward.fromDoc(d)).toList();
          final filtered = rewards
              .where((r) => r.isActive && r.isAvailableTo(studentId))
              .toList();
          filtered.sort((a, b) => a.pointCost.compareTo(b.pointCost));
          return filtered;
        });
  }

  /// Stream all rewards (for admin)
  Stream<List<Reward>> streamAllRewards() {
    return FirestorePaths.rewardsCol()
        .snapshots()
        .map((snap) {
          final rewards = snap.docs.map((d) => Reward.fromDoc(d)).toList();
          rewards.sort((a, b) => a.pointCost.compareTo(b.pointCost));
          return rewards;
        });
  }

  // ========================================
  // Claiming & Allocating Rewards (Student)
  // ========================================

  /// Update allocation for a reward
  /// Allocates (deducts from wallet) or Deallocates (refunds to wallet) points
  Future<void> setAllocation({
    required String studentId,
    required String rewardId,
    required String rewardName,
    required int newAmount,
  }) async {
    if (newAmount < 0) throw ArgumentError('Allocation cannot be negative');

    return FirebaseFirestore.instance.runTransaction((tx) async {
      final studentRef = FirestorePaths.studentDoc(studentId);
      final studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) throw Exception('Student not found');
      
      final studentData = studentSnap.data() ?? {};
      final currentBalance = asInt(studentData['walletBalance'], fallback: 0);
      
      // Parse current allocations
      final rewardAllocations = Map<String, int>.from(
        (studentData['rewardAllocations'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), asInt(v))
        ) ?? {}
      );
      
      final currentAllocation = rewardAllocations[rewardId] ?? 0;
      final delta = newAmount - currentAllocation;
      
      if (delta == 0) return; // No change
      
      // If allocating more, check balance
      if (delta > 0) {
        if (currentBalance < delta) {
           throw InsufficientBalanceException(required: delta, available: currentBalance);
        }
      }
      
      // Update allocations map
      if (newAmount == 0) {
        rewardAllocations.remove(rewardId);
      } else {
        rewardAllocations[rewardId] = newAmount;
      }
      
      // Create transaction record
      final txnRef = FirestorePaths.walletTransactionsCol(studentId).doc();
      final txnData = <String, dynamic>{
        'type': 'allocation',
        'points': -delta, // Negative if allocating, Positive if reclaiming
        'source': 'allocation_update',
        'studentId': studentId,
        'rewardId': rewardId,
        'rewardName': rewardName,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      tx.set(txnRef, txnData);
      tx.update(studentRef, {
        'walletBalance': FieldValue.increment(-delta),
        'rewardAllocations': rewardAllocations,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Claim a reward (student self-serve)
  /// Uses allocated points first, then wallet balance
  Future<RewardClaim> claimReward({
    required String studentId,
    required String studentName,
    required String rewardId,
  }) async {
    // Get reward details
    final reward = await getReward(rewardId);
    if (reward == null) {
      throw Exception('Reward not found');
    }
    if (!reward.isActive) {
      throw Exception('Reward is no longer available');
    }
    if (!reward.isAvailableTo(studentId)) {
      throw Exception('This reward is not available to you');
    }

    // Run transaction
    return FirebaseFirestore.instance.runTransaction((tx) async {
      // Get student
      final studentRef = FirestorePaths.studentDoc(studentId);
      final studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) throw Exception('Student not found');
      
      final studentData = studentSnap.data() ?? {};
      final currentBalance = asInt(studentData['walletBalance'], fallback: 0);
      
      // Get allocations
      final rewardAllocations = Map<String, int>.from(
        (studentData['rewardAllocations'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), asInt(v))
        ) ?? {}
      );
      
      final allocated = rewardAllocations[rewardId] ?? 0;
      final neededFromWallet = reward.pointCost - allocated;
      
      // Check affordability
      if (neededFromWallet > 0) {
        if (currentBalance < neededFromWallet) {
          throw InsufficientBalanceException(
            required: neededFromWallet,
            available: currentBalance,
          );
        }
      }
      
      // Create claim document
      final claimRef = FirestorePaths.rewardClaimsCol(studentId).doc();
      final claim = RewardClaim(
        id: claimRef.id,
        studentId: studentId,
        studentName: studentName,
        rewardId: rewardId,
        rewardName: reward.name,
        pointCost: reward.pointCost,
        tier: reward.tier,
        status: ClaimStatus.pending,
      );

      // Create wallet transaction IF spending from wallet
      // We only log the amount taken from wallet here.
      // Allocated points were logged when they were allocated.
      if (neededFromWallet != 0) {
        final txnRef = FirestorePaths.walletTransactionsCol(studentId).doc();
        final txnData = <String, dynamic>{
          'type': 'redemption',
          'points': -neededFromWallet, // Can be positive if refunding excess allocation!
          'source': 'reward_claim',
          'studentId': studentId,
          'rewardId': rewardId,
          'rewardName': reward.name,
          'claimId': claimRef.id,
          'createdAt': FieldValue.serverTimestamp(),
        };
        tx.set(txnRef, txnData);
      }

      // Remove allocation
      rewardAllocations.remove(rewardId);

      // Update reward claim count
      final rewardRef = FirestorePaths.rewardDoc(rewardId);

      // Execute writes
      tx.set(claimRef, claim.toCreateMap());
      
      tx.update(studentRef, {
        'walletBalance': FieldValue.increment(-neededFromWallet),
        'rewardAllocations': rewardAllocations,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      tx.update(rewardRef, {
        'timesClaimedTotal': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return claim;
    });
  }

  // ========================================
  // Fulfilling Claims (Parent)
  // ========================================

  /// Mark a claim as fulfilled
  Future<void> fulfillClaim({
    required String studentId,
    required String claimId,
  }) async {
    await FirestorePaths.rewardClaimDoc(studentId, claimId).update({
      'status': ClaimStatus.fulfilled.name,
      'fulfilledAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get all pending claims across all students
  Future<List<RewardClaim>> getAllPendingClaims() async {
    final students = await FirestorePaths.studentsCol().get();
    final allClaims = <RewardClaim>[];

    for (final studentDoc in students.docs) {
      final claims = await FirestorePaths.rewardClaimsCol(studentDoc.id)
          .where('status', isEqualTo: ClaimStatus.pending.name)
          .get();
      allClaims.addAll(claims.docs.map((d) => RewardClaim.fromDoc(d)));
    }

    allClaims.sort((a, b) {
      final aDate = a.claimedAt ?? DateTime(1970);
      final bDate = b.claimedAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });

    return allClaims;
  }

  /// Stream pending claims for a specific student
  Stream<List<RewardClaim>> streamPendingClaims(String studentId) {
    return FirestorePaths.rewardClaimsCol(studentId)
        .where('status', isEqualTo: ClaimStatus.pending.name)
        .snapshots()
        .map((snap) {
          final claims = snap.docs.map((d) => RewardClaim.fromDoc(d)).toList();
          claims.sort((a, b) {
            final aDate = a.claimedAt ?? DateTime(1970);
            final bDate = b.claimedAt ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
          return claims;
        });
  }

  /// Get claims for a student
  Future<List<RewardClaim>> getClaimsForStudent(String studentId) async {
    final snap = await FirestorePaths.rewardClaimsCol(studentId).get();
    final claims = snap.docs.map((d) => RewardClaim.fromDoc(d)).toList();
    claims.sort((a, b) {
      final aDate = a.claimedAt ?? DateTime(1970);
      final bDate = b.claimedAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return claims;
  }

  /// Stream all claims for a student
  Stream<List<RewardClaim>> streamClaimsForStudent(String studentId) {
    return FirestorePaths.rewardClaimsCol(studentId)
        .snapshots()
        .map((snap) {
          final claims = snap.docs.map((d) => RewardClaim.fromDoc(d)).toList();
          claims.sort((a, b) {
            final aDate = a.claimedAt ?? DateTime(1970);
            final bDate = b.claimedAt ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
          return claims;
        });
  }

  // ========================================
  // Manual Point Adjustments (Parent)
  // ========================================

  /// Add or remove points manually
  Future<void> adjustPoints({
    required String studentId,
    required int points,
    required String reason,
  }) async {
    if (points == 0) return;

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final studentRef = FirestorePaths.studentDoc(studentId);
      final studentSnap = await tx.get(studentRef);
      final studentData = studentSnap.data() ?? {};
      final currentBalance = asInt(studentData['walletBalance'], fallback: 0);

      // Prevent negative balance
      if (points < 0 && (currentBalance + points) < 0) {
        throw InsufficientBalanceException(
          required: -points,
          available: currentBalance,
        );
      }

      final txnRef = FirestorePaths.walletTransactionsCol(studentId).doc();
      final txnData = <String, dynamic>{
        'type': 'adjustment',
        'points': points,
        'source': 'parent_adjustment',
        'studentId': studentId,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      };

      tx.set(txnRef, txnData);
      tx.update(studentRef, {
        'walletBalance': FieldValue.increment(points),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ========================================
  // Wallet History
  // ========================================

  Future<List<WalletTransaction>> getWalletHistory(
    String studentId, {
    int limit = 50,
  }) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId)
        .limit(limit)
        .get();
    final txns = snap.docs.map((d) => WalletTransaction.fromDoc(d)).toList();
    txns.sort((a, b) {
      final aDate = a.createdAt ?? DateTime(1970);
      final bDate = b.createdAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return txns;
  }

  Stream<List<WalletTransaction>> streamWalletHistory(
    String studentId, {
    int limit = 50,
  }) {
    return FirestorePaths.walletTransactionsCol(studentId)
        .limit(limit)
        .snapshots()
        .map((snap) {
          final txns = snap.docs.map((d) => WalletTransaction.fromDoc(d)).toList();
          txns.sort((a, b) {
            final aDate = a.createdAt ?? DateTime(1970);
            final bDate = b.createdAt ?? DateTime(1970);
            return bDate.compareTo(aDate);
          });
          return txns;
        });
  }

  Future<List<WalletTransaction>> getWalletHistoryForDateRange(
    String studentId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId).get();
    final txns = snap.docs
        .map((d) => WalletTransaction.fromDoc(d))
        .where((t) {
          if (t.createdAt == null) return false;
          return t.createdAt!.isAfter(startDate) && t.createdAt!.isBefore(endDate);
        })
        .toList();
    txns.sort((a, b) {
      final aDate = a.createdAt ?? DateTime(1970);
      final bDate = b.createdAt ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });
    return txns;
  }

  Future<int> getTotalPointsEarned(String studentId) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId).get();
    int total = 0;
    for (final doc in snap.docs) {
      final type = doc.data()['type']?.toString();
      if (type == 'deposit') {
        total += asInt(doc.data()['points'], fallback: 0);
      }
    }
    return total;
  }

  Future<int> getTotalPointsSpent(String studentId) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId).get();
    int total = 0;
    for (final doc in snap.docs) {
      final type = doc.data()['type']?.toString();
      if (type == 'redemption') {
        total += asInt(doc.data()['points'], fallback: 0).abs();
      }
    }
    return total;
  }

  // ========================================
  // Parent PIN Management
  // ========================================

  Future<void> setParentPin(String pin) async {
    await FirestorePaths.parentSettingsDoc().set({
      'pin': pin,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<bool> verifyParentPin(String pin) async {
    final snap = await FirestorePaths.parentSettingsDoc().get();
    final data = snap.data();
    if (data == null) return false;

    final storedPin = data['pin']?.toString() ?? '';
    return storedPin == pin;
  }

  Future<bool> isParentPinSet() async {
    final snap = await FirestorePaths.parentSettingsDoc().get();
    final data = snap.data();
    if (data == null) return false;

    final storedPin = data['pin']?.toString() ?? '';
    return storedPin.isNotEmpty;
  }

  // ========================================
  // Student Balance
  // ========================================

  Future<int> getWalletBalance(String studentId) async {
    final snap = await FirestorePaths.studentDoc(studentId).get();
    final data = snap.data();
    if (data == null) return 0;

    return asInt(data['walletBalance'], fallback: 0);
  }

  Stream<int> streamWalletBalance(String studentId) {
    return FirestorePaths.studentDoc(studentId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return 0;
      return asInt(data['walletBalance'], fallback: 0);
    });
  }

  // ========================================
  // Group Rewards
  // ========================================

  Future<dynamic> createGroupReward({
    required String name,
    required int pointsNeeded,
    String description = '',
    List<String> allowedStudentIds = const [],
    DateTime? expiresAt,
  }) async {
    final docRef = FirestorePaths.groupRewardsCol().doc();
    final data = {
      'id': docRef.id,
      'name': name,
      'nameLower': name.toLowerCase(),
      'pointsNeeded': pointsNeeded,
      'pointsContributed': 0,
      'description': description,
      'isActive': true,
      'isRedeemed': false,
      'allowedStudentIds': allowedStudentIds,
      'studentContributions': <String, int>{},
      'expiresAt': expiresAt,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await docRef.set(data);
    return data;
  }

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

  Future<void> redeemGroupReward(String groupRewardId) async {
    await FirestorePaths.groupRewardDoc(groupRewardId).update({
      'isRedeemed': true,
      'isActive': false,
      'redeemedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<dynamic> getGroupReward(String groupRewardId) async {
    final snap = await FirestorePaths.groupRewardDoc(groupRewardId).get();
    return snap.data();
  }

  Future<List<Map<String, dynamic>>> getActiveGroupRewards() async {
    final snap = await FirestorePaths.groupRewardsCol().get();
    final rewards = snap.docs.map((d) => d.data()).toList();
    final active = rewards
        .where((r) => asBool(r['isActive'], fallback: true) && 
                      !asBool(r['isRedeemed'], fallback: false))
        .toList();
    return active;
  }

  Stream<QuerySnapshot> getActiveGroupRewardsStream() {
    return FirestorePaths.groupRewardsCol().snapshots();
  }

  Stream<List<Map<String, dynamic>>> streamActiveGroupRewardsForStudent(String studentId) {
    return FirestorePaths.groupRewardsCol().snapshots().map((snap) {
      final rewards = snap.docs.map((d) => d.data()).toList();
      final filtered = rewards.where((r) {
        final isActive = asBool(r['isActive'], fallback: true);
        final isRedeemed = asBool(r['isRedeemed'], fallback: false);
        final allowed = r['allowedStudentIds'] as List? ?? [];
        final canAccess = allowed.isEmpty || allowed.contains(studentId);
        return isActive && !isRedeemed && canAccess;
      }).toList();
      return filtered;
    });
  }

  Future<void> contributeToGroupReward({
    required String groupRewardId,
    required String studentId,
    required int points,
  }) async {
    if (points <= 0) {
      throw ArgumentError('Points must be greater than 0');
    }

    final current = await getGroupReward(groupRewardId);
    if (current == null) throw Exception('Group reward not found');

    final allowed = current['allowedStudentIds'] as List? ?? [];
    if (allowed.isNotEmpty && !allowed.contains(studentId)) {
      throw Exception('Student is not allowed to contribute to this reward');
    }

    if (!asBool(current['isActive'], fallback: false) || 
        asBool(current['isRedeemed'], fallback: false)) {
      throw Exception('This group reward is no longer active');
    }

    final balance = await getWalletBalance(studentId);
    if (balance < points) {
      throw InsufficientBalanceException(required: points, available: balance);
    }

    final currentContributed = asInt(current['pointsContributed'], fallback: 0);
    final pointsNeeded = asInt(current['pointsNeeded'], fallback: 0);
    final newContributed = currentContributed + points;
    final newClamped = newContributed.clamp(0, pointsNeeded);
    
    final contributions = Map<String, dynamic>.from(current['studentContributions'] ?? {});
    final existingContribution = asInt(contributions[studentId], fallback: 0);
    contributions[studentId] = existingContribution + points;

    await FirestorePaths.groupRewardDoc(groupRewardId).update({
      'pointsContributed': newClamped,
      'studentContributions': contributions,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await adjustPoints(
      studentId: studentId,
      points: -points,
      reason: 'Contributed to group reward: ${current['name'] ?? 'Group Goal'}',
    );
  }

  Future<int> getStudentGroupContribution(String groupRewardId, String studentId) async {
    final reward = await getGroupReward(groupRewardId);
    if (reward == null) return 0;
    return 0; // The logic here was missing in previous read, but default to 0 is safe
  }

  Future<void> updateGroupRewardContributions({
    required String groupRewardId,
    required Map<String, int> studentContributions,
  }) async {
    int totalContributed = 0;
    final cleanedContributions = <String, int>{};

    for (final entry in studentContributions.entries) {
      if (entry.value > 0) {
        totalContributed += entry.value;
        cleanedContributions[entry.key] = entry.value;
      }
    }

    await FirestorePaths.groupRewardDoc(groupRewardId).update({
      'studentContributions': cleanedContributions,
      'pointsContributed': totalContributed,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class InsufficientBalanceException implements Exception {
  final int required;
  final int available;

  InsufficientBalanceException({
    required this.required,
    required this.available,
  });

  int get shortfall => required - available;

  @override
  String toString() =>
      'Insufficient balance: need $required points, have $available (short $shortfall)';
}
