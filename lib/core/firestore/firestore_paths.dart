// FILE: lib/firestore_paths.dart
//
// Centralized Firestore path helpers.
// Keeps collection/document paths consistent across the app.
//
// Schema:
// /users/{uid}                  (profile + familyId)
// /families/{familyId}
// /families/{familyId}/students
// /families/{familyId}/subjects
// /families/{familyId}/assignments
// /families/{familyId}/settings/app

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

  // ---------- Root docs ----------

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      _db.collection('users').doc(uid);

  static DocumentReference<Map<String, dynamic>> familyDoc([String? familyId]) =>
      _db.collection('families').doc((familyId ?? FirestorePaths.familyId()).trim());

  // ---------- Family subcollections ----------

  static CollectionReference<Map<String, dynamic>> studentsCol([String? familyId]) =>
      familyDoc(familyId).collection('students');

  static CollectionReference<Map<String, dynamic>> subjectsCol([String? familyId]) =>
      familyDoc(familyId).collection('subjects');

  static CollectionReference<Map<String, dynamic>> assignmentsCol([String? familyId]) =>
      familyDoc(familyId).collection('assignments');

  static DocumentReference<Map<String, dynamic>> settingsDoc([String? familyId]) =>
      familyDoc(familyId).collection('settings').doc('app');
}
