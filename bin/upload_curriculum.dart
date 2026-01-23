// Usage: dart run bin/upload_curriculum.dart <filepath> [--force]
// Example: dart run bin/upload_curriculum.dart assets/courseConfigs/llpsi_familia_romana_v1.json
// Example: dart run bin/upload_curriculum.dart assets/courseConfigs/llpsi_familia_romana_v1.json --force

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/upload_curriculum.dart <filepath> [--force]');
    print('Example: dart run bin/upload_curriculum.dart assets/courseConfigs/llpsi_familia_romana_v1.json');
    exit(1);
  }

  final filePath = args[0];
  final force = args.contains('--force');

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final db = FirebaseFirestore.instance;

  try {
    // Read JSON file
    final file = File(filePath);
    if (!file.existsSync()) {
      print('❌ Error: File not found: $filePath');
      exit(1);
    }

    final jsonStr = file.readAsStringSync();
    final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;

    // Extract curriculum ID
    final configId = jsonData['id'] as String?;
    if (configId == null) {
      print('❌ Error: JSON must contain an "id" field');
      exit(1);
    }

    print('📖 Curriculum: $configId');
    print('📄 File: $filePath');

    // Check if document already exists
    final docRef = db.collection('courseConfigs').doc(configId);
    final docSnap = await docRef.get();

    if (docSnap.exists && !force) {
      print('⚠️  Document already exists. Use --force to overwrite.');
      print('   Command: dart run bin/upload_curriculum.dart $filePath --force');
      exit(1);
    }

    if (docSnap.exists && force) {
      print('⚠️  Overwriting existing document...');
    }

    // Add metadata fields
    jsonData['active'] = true;
    jsonData['uploadedAt'] = FieldValue.serverTimestamp();
    jsonData['updatedAt'] = FieldValue.serverTimestamp();

    // Upload to Firestore
    await docRef.set(jsonData, SetOptions(merge: false));

    print('✅ Successfully uploaded to Firestore!');
    print('   Collection: courseConfigs');
    print('   Document ID: $configId');
    exit(0);
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}
