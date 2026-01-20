// FILE: lib/core/firestore/firestore_paths.dart
//
// Centralized Firestore path helpers.
// Keeps collection/document paths consistent across the app.
//
// Schema:
// /users/{uid}                                    (profile + familyId)
// /families/{familyId}
// /families/{familyId}/students/{studentId}
// /families/{familyId}/students/{studentId}/walletTransactions/{txnId}
// /families/{familyId}/students/{studentId}/subjectProgress/{subjectId}
// /families/{familyId}/students/{studentId}/badgesEarned/{badgeId}
// /families/{familyId}/students/{studentId}/dailyActivity/{date}
// /families/{familyId}/students/{studentId}/rewardClaims/{claimId}
// /families/{familyId}/subjects/{subjectId}
// /families/{familyId}/assignments/{assignmentId}
// /families/{familyId}/rewards/{rewardId}
// /families/{familyId}/settings/app
// /families/{familyId}/settings/parent
// /courseConfigs/{configId}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestorePaths {
  FirestorePaths._();

  static String? _overrideFamilyId;

  /// Optional override (useful for admin tooling or future multi-family support).
  static void setFamilyIdOverride(String? familyId) {
    final v = familyId?.trim();
    _overrideFamilyId = (v == null || v.isEmpty) ? null : v;
  }

  /// Current familyId for the signed-in user.
  ///
  /// Default: the current user's uid (single-household default).
  /// Can be overridden via [setFamilyIdOverride] after bootstrap resolves a familyId.
  static String familyId() {
    final override = _overrideFamilyId;
    if (override != null && override.isNotEmpty) return override;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('FirestorePaths.familyId() called while no user is signed in.');
    }
    return user.uid;
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ========================================
  // Root docs
  // ========================================

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      _db.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> familyDoc([String? familyId]) =>
      _db.collection('families').doc((familyId ?? FirestorePaths.familyId()).trim());

  // ========================================
  // Family subcollections
  // ========================================

  static CollectionReference<Map<String, dynamic>> studentsCol([String? familyId]) =>
      familyDoc(familyId).collection('students');

  static DocumentReference<Map<String, dynamic>> studentDoc(String studentId, [String? familyId]) =>
      studentsCol(familyId).doc(studentId);

  static CollectionReference<Map<String, dynamic>> subjectsCol([String? familyId]) =>
      familyDoc(familyId).collection('subjects');

  static CollectionReference<Map<String, dynamic>> assignmentsCol([String? familyId]) =>
      familyDoc(familyId).collection('assignments');

  static DocumentReference<Map<String, dynamic>> settingsDoc([String? familyId]) =>
      familyDoc(familyId).collection('settings').doc('app');

  // ========================================
  // Parent settings (for parent PIN)
  // ========================================

  static DocumentReference<Map<String, dynamic>> parentSettingsDoc([String? familyId]) =>
      familyDoc(familyId).collection('settings').doc('parent');

  // ========================================
  // Rewards (family-level)
  // ========================================

  /// /families/{familyId}/rewards
  static CollectionReference<Map<String, dynamic>> rewardsCol([String? familyId]) =>
      familyDoc(familyId).collection('rewards');

  /// /families/{familyId}/rewards/{rewardId}
  static DocumentReference<Map<String, dynamic>> rewardDoc(String rewardId, [String? familyId]) =>
      rewardsCol(familyId).doc(rewardId);

  // ========================================
  // Student subcollections
  // ========================================

  /// /families/{familyId}/students/{studentId}/walletTransactions
  static CollectionReference<Map<String, dynamic>> walletTransactionsCol(
    String studentId, [
    String? familyId,
  ]) =>
      studentsCol(familyId).doc(studentId).collection('walletTransactions');

  /// /families/{familyId}/students/{studentId}/walletTransactions/{txnId}
  static DocumentReference<Map<String, dynamic>> walletTransactionDoc(
    String studentId,
    String txnId, [
    String? familyId,
  ]) =>
      walletTransactionsCol(studentId, familyId).doc(txnId);

  /// /families/{familyId}/students/{studentId}/subjectProgress
  static CollectionReference<Map<String, dynamic>> subjectProgressCol(
    String studentId, [
    String? familyId,
  ]) =>
      studentsCol(familyId).doc(studentId).collection('subjectProgress');

  /// /families/{familyId}/students/{studentId}/subjectProgress/{subjectId}
  static DocumentReference<Map<String, dynamic>> subjectProgressDoc(
    String studentId,
    String subjectId, [
    String? familyId,
  ]) =>
      subjectProgressCol(studentId, familyId).doc(subjectId);

  /// /families/{familyId}/students/{studentId}/badgesEarned
  static CollectionReference<Map<String, dynamic>> badgesEarnedCol(
    String studentId, [
    String? familyId,
  ]) =>
      studentsCol(familyId).doc(studentId).collection('badgesEarned');

  /// /families/{familyId}/students/{studentId}/badgesEarned/{badgeId}
  static DocumentReference<Map<String, dynamic>> badgeEarnedDoc(
    String studentId,
    String badgeId, [
    String? familyId,
  ]) =>
      badgesEarnedCol(studentId, familyId).doc(badgeId);

  /// /families/{familyId}/students/{studentId}/dailyActivity
  static CollectionReference<Map<String, dynamic>> dailyActivityCol(
    String studentId, [
    String? familyId,
  ]) =>
      studentsCol(familyId).doc(studentId).collection('dailyActivity');

  /// /families/{familyId}/students/{studentId}/dailyActivity/{date}
  /// Date format: "YYYY-MM-DD"
  static DocumentReference<Map<String, dynamic>> dailyActivityDoc(
    String studentId,
    String date, [
    String? familyId,
  ]) =>
      dailyActivityCol(studentId, familyId).doc(date);

  /// /families/{familyId}/students/{studentId}/rewardClaims
  static CollectionReference<Map<String, dynamic>> rewardClaimsCol(
    String studentId, [
    String? familyId,
  ]) =>
      studentsCol(familyId).doc(studentId).collection('rewardClaims');

  /// /families/{familyId}/students/{studentId}/rewardClaims/{claimId}
  static DocumentReference<Map<String, dynamic>> rewardClaimDoc(
    String studentId,
    String claimId, [
    String? familyId,
  ]) =>
      rewardClaimsCol(studentId, familyId).doc(claimId);

  // ========================================
  // Course configs (global)
  // ========================================

  /// /courseConfigs
  static CollectionReference<Map<String, dynamic>> courseConfigsCol() =>
      _db.collection('courseConfigs');

  /// /courseConfigs/{configId}
  static DocumentReference<Map<String, dynamic>> courseConfigDoc(String configId) =>
      courseConfigsCol().doc(configId);
}