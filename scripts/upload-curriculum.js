#!/usr/bin/env node

/**
 * Upload curriculum JSON to Firestore
 * Usage: node scripts/upload-curriculum.js <filepath> [--force]
 * Example: node scripts/upload-curriculum.js assets/courseConfigs/llpsi_familia_romana_v1.json
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT || 
  path.join(__dirname, '..', 'firebase-service-account.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error('❌ Error: Firebase service account not found at:', serviceAccountPath);
  console.error('   Set FIREBASE_SERVICE_ACCOUNT environment variable or place json file at project root');
  process.exit(1);
}

const serviceAccount = require(serviceAccountPath);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function uploadCurriculum(filePath, force = false) {
  try {
    // Read and parse JSON
    if (!fs.existsSync(filePath)) {
      console.error(`❌ Error: File not found: ${filePath}`);
      process.exit(1);
    }

    const jsonStr = fs.readFileSync(filePath, 'utf-8');
    const curriculum = JSON.parse(jsonStr);

    // Validate
    const configId = curriculum.id;
    if (!configId) {
      console.error('❌ Error: JSON must contain an "id" field');
      process.exit(1);
    }

    console.log('📖 Curriculum:', configId);
    console.log('📄 File:', filePath);

    // Check if exists
    const docRef = db.collection('courseConfigs').doc(configId);
    const docSnap = await docRef.get();

    if (docSnap.exists && !force) {
      console.error('⚠️  Document already exists. Use --force to overwrite.');
      console.error('   Command: node scripts/upload-curriculum.js', filePath, '--force');
      process.exit(1);
    }

    if (docSnap.exists && force) {
      console.log('⚠️  Overwriting existing document...');
    }

    // Add metadata
    curriculum.active = true;
    curriculum.uploadedAt = admin.firestore.FieldValue.serverTimestamp();
    curriculum.updatedAt = admin.firestore.FieldValue.serverTimestamp();

    // Upload
    await docRef.set(curriculum, { merge: false });

    console.log('✅ Successfully uploaded to Firestore!');
    console.log('   Collection: courseConfigs');
    console.log('   Document ID:', configId);
    
    process.exit(0);
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

// Parse arguments
const args = process.argv.slice(2);
if (args.length === 0) {
  console.log('Usage: node scripts/upload-curriculum.js <filepath> [--force]');
  console.log('Example: node scripts/upload-curriculum.js assets/courseConfigs/llpsi_familia_romana_v1.json');
  process.exit(1);
}

const filePath = args[0];
const force = args.includes('--force');

uploadCurriculum(filePath, force);
