// FILE: lib/firestore_bootstrap.dart
//
// Production-safe Firestore bootstrap:
// - Ensures /users/{uid} exists and stores familyId
// - Ensures /families/{familyId} exists
// - Ensures /families/{familyId}/settings/app exists
//
// No demo/test writes. Safe to call at every login.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firestore_paths.dart';

class FirestoreBootstrap {
  FirestoreBootstrap._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Map<String, dynamic> _ts({bool includeCreated = false}) {
    final now = FieldValue.serverTimestamp();
    return <String, dynamic>{
      'updatedAt': now,
      if (includeCreated) 'createdAt': now,
    };
  }

  /// Initializes user + family documents for the signed-in user.
  ///
  /// familyId logic:
  /// - If /users/{uid}.familyId exists and is non-empty -> use it
  /// - Else default to uid (single-household)
  ///
  /// Also sets FirestorePaths.setFamilyIdOverride(familyId)
  static Future<void> ensureUserBootstrap(User user) async {
    final uid = user.uid;

    // 1) Read existing user doc to learn familyId (if any).
    final userRef = FirestorePaths.userDoc(uid);
    final userSnap = await userRef.get();

    String familyId = uid; // default: one family per account (simple + safe)
    if (userSnap.exists) {
      final data = userSnap.data();
      final fid = data?['familyId'];
      if (fid is String) {
        final trimmed = fid.trim();
        if (trimmed.isNotEmpty) familyId = trimmed;
      }
    }

    // Make familyId available to the rest of the app.
    FirestorePaths.setFamilyIdOverride(familyId);

    // 2) Upsert user doc
    await userRef.set(
      <String, dynamic>{
        'uid': uid,
        'email': user.email,
        'familyId': familyId,
        'role': 'parent',
        'lastLoginAt': FieldValue.serverTimestamp(),
        ..._ts(includeCreated: !userSnap.exists),
      },
      SetOptions(merge: true),
    );

    // 3) Upsert family doc
    final familyRef = FirestorePaths.familyDoc(familyId);
    final familySnap = await familyRef.get();

    await familyRef.set(
      <String, dynamic>{
        'ownerUid': uid,
        'name': user.email == null ? 'Family $familyId' : 'Family of ${user.email}',
        ..._ts(includeCreated: !familySnap.exists),
      },
      SetOptions(merge: true),
    );

    // 4) Ensure settings doc exists (no overwrites if it already exists)
    final settingsRef = FirestorePaths.settingsDoc(familyId);
    final settingsSnap = await settingsRef.get();

    if (!settingsSnap.exists) {
      await settingsRef.set(
        <String, dynamic>{
          'teacherMood': null,
          ..._ts(includeCreated: true),
        },
        SetOptions(merge: true),
      );
    }
  }
}
