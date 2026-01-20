// FILE: lib/services/reward_service.dart
//
// Service for managing rewards, claims, and point adjustments.
//
// Handles:
// - CRUD for reward definitions (parent)
// - Claiming rewards (student)
// - Fulfilling claims (parent)
// - Manual point adjustments (parent)
// - Wallet transaction history

import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/models/models.dart';
import '../core/models/reward_models.dart';
import '../core/firestore/firestore_paths.dart';

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

  /// Get all active rewards
  Future<List<Reward>> getActiveRewards() async {
    final snap = await FirestorePaths.rewardsCol()
        .where('isActive', isEqualTo: true)
        .orderBy('pointCost')
        .get();
    return snap.docs.map((d) => Reward.fromDoc(d)).toList();
  }

  /// Get all rewards (including inactive)
  Future<List<Reward>> getAllRewards() async {
    final snap = await FirestorePaths.rewardsCol()
        .orderBy('pointCost')
        .get();
    return snap.docs.map((d) => Reward.fromDoc(d)).toList();
  }

  /// Stream active rewards
  Stream<List<Reward>> streamActiveRewards() {
    return FirestorePaths.rewardsCol()
        .where('isActive', isEqualTo: true)
        .orderBy('pointCost')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Reward.fromDoc(d)).toList());
  }

  /// Stream all rewards
  Stream<List<Reward>> streamAllRewards() {
    return FirestorePaths.rewardsCol()
        .orderBy('pointCost')
        .snapshots()
        .map((snap) => snap.docs.map((d) => Reward.fromDoc(d)).toList());
  }

  // ========================================
  // Claiming Rewards (Student)
  // ========================================

  /// Claim a reward (student self-serve)
  /// Returns the claim if successful, throws if insufficient balance
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

    // Run transaction to ensure atomic balance check + deduction
    return FirebaseFirestore.instance.runTransaction((tx) async {
      // Get current student balance
      final studentRef = FirestorePaths.studentDoc(studentId);
      final studentSnap = await tx.get(studentRef);
      final studentData = studentSnap.data() ?? {};
      final currentBalance = asInt(
        studentData['walletBalance'] ?? studentData['wallet_balance'],
        fallback: 0,
      );

      // Check if student can afford
      if (currentBalance < reward.pointCost) {
        throw InsufficientBalanceException(
          required: reward.pointCost,
          available: currentBalance,
        );
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

      // Create wallet transaction (redemption)
      final txnRef = FirestorePaths.walletTransactionsCol(studentId).doc();
      final txnData = <String, dynamic>{
        'type': 'redemption',
        'points': -reward.pointCost,
        'source': 'reward_claim',
        'studentId': studentId,
        'rewardId': rewardId,
        'rewardName': reward.name,
        'claimId': claimRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Update reward claim count
      final rewardRef = FirestorePaths.rewardDoc(rewardId);

      // Execute all writes
      tx.set(claimRef, claim.toCreateMap());
      tx.set(txnRef, txnData);
      tx.update(studentRef, {
        'walletBalance': FieldValue.increment(-reward.pointCost),
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
          .orderBy('claimedAt', descending: true)
          .get();
      allClaims.addAll(claims.docs.map((d) => RewardClaim.fromDoc(d)));
    }

    // Sort by claimed date (newest first)
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
        .orderBy('claimedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => RewardClaim.fromDoc(d)).toList());
  }

  /// Get claims for a student
  Future<List<RewardClaim>> getClaimsForStudent(String studentId) async {
    final snap = await FirestorePaths.rewardClaimsCol(studentId)
        .orderBy('claimedAt', descending: true)
        .get();
    return snap.docs.map((d) => RewardClaim.fromDoc(d)).toList();
  }

  /// Stream all claims for a student
  Stream<List<RewardClaim>> streamClaimsForStudent(String studentId) {
    return FirestorePaths.rewardClaimsCol(studentId)
        .orderBy('claimedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => RewardClaim.fromDoc(d)).toList());
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
      final currentBalance = asInt(
        studentData['walletBalance'] ?? studentData['wallet_balance'],
        fallback: 0,
      );

      // Prevent negative balance
      if (points < 0 && (currentBalance + points) < 0) {
        throw InsufficientBalanceException(
          required: -points,
          available: currentBalance,
        );
      }

      // Create wallet transaction
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

  /// Get wallet transaction history for a student
  Future<List<WalletTransaction>> getWalletHistory(
    String studentId, {
    int limit = 50,
  }) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => WalletTransaction.fromDoc(d)).toList();
  }

  /// Stream wallet transaction history for a student
  Stream<List<WalletTransaction>> streamWalletHistory(
    String studentId, {
    int limit = 50,
  }) {
    return FirestorePaths.walletTransactionsCol(studentId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => WalletTransaction.fromDoc(d)).toList());
  }

  /// Get wallet transactions for a date range
  Future<List<WalletTransaction>> getWalletHistoryForDateRange(
    String studentId, {
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) => WalletTransaction.fromDoc(d)).toList();
  }

  /// Get total points earned (all deposits)
  Future<int> getTotalPointsEarned(String studentId) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId)
        .where('type', isEqualTo: 'deposit')
        .get();

    int total = 0;
    for (final doc in snap.docs) {
      total += asInt(doc.data()['points'], fallback: 0);
    }
    return total;
  }

  /// Get total points spent (all redemptions)
  Future<int> getTotalPointsSpent(String studentId) async {
    final snap = await FirestorePaths.walletTransactionsCol(studentId)
        .where('type', isEqualTo: 'redemption')
        .get();

    int total = 0;
    for (final doc in snap.docs) {
      total += asInt(doc.data()['points'], fallback: 0).abs();
    }
    return total;
  }

  // ========================================
  // Parent PIN Management
  // ========================================

  /// Set or update parent PIN
  Future<void> setParentPin(String pin) async {
    await FirestorePaths.parentSettingsDoc().set({
      'pin': pin,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Verify parent PIN
  Future<bool> verifyParentPin(String pin) async {
    final snap = await FirestorePaths.parentSettingsDoc().get();
    final data = snap.data();
    if (data == null) return false;

    final storedPin = data['pin']?.toString() ?? '';
    return storedPin == pin;
  }

  /// Check if parent PIN is set
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

  /// Get current wallet balance for a student
  Future<int> getWalletBalance(String studentId) async {
    final snap = await FirestorePaths.studentDoc(studentId).get();
    final data = snap.data();
    if (data == null) return 0;

    return asInt(
      data['walletBalance'] ?? data['wallet_balance'],
      fallback: 0,
    );
  }

  /// Stream wallet balance for real-time updates
  Stream<int> streamWalletBalance(String studentId) {
    return FirestorePaths.studentDoc(studentId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return 0;
      return asInt(
        data['walletBalance'] ?? data['wallet_balance'],
        fallback: 0,
      );
    });
  }
}

// ========================================
// Exceptions
// ========================================

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