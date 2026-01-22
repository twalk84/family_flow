/* eslint-disable no-console */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const admin = require("firebase-admin");

// Uses GOOGLE_APPLICATION_CREDENTIALS
// And uses FIREBASE_STORAGE_BUCKET for the default bucket.
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  storageBucket: process.env.FIREBASE_STORAGE_BUCKET, // <-- set this
});

const db = admin.firestore();
const bucket = admin.storage().bucket();

function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

async function publishOne(filePath) {
  const raw = fs.readFileSync(filePath);
  const json = JSON.parse(raw.toString("utf8"));

  const id = String(json.id || "").trim();
  const title = String(json.title || "").trim();
  const subtitle = String(json.subtitle || "").trim();
  const version = Number(json.version || 1);

  if (!id) throw new Error(`Missing "id" in ${filePath}`);
  if (!title) throw new Error(`Missing "title" in ${filePath}`);

  const storagePath = `course-configs/${id}/v${version}.json`;

  // Upload JSON to Storage
  await bucket.file(storagePath).save(raw, {
    contentType: "application/json; charset=utf-8",
    resumable: false,
    metadata: { cacheControl: "public, max-age=3600" },
  });

  const bytes = raw.length;
  const hash = sha256(raw);

  // Write Firestore metadata doc
  await db.collection("courseConfigs").doc(id).set(
    {
      id,
      title,
      subtitle,
      version,
      active: true,
      schemaVersion: 1,
      payloadStoragePath: storagePath,
      payloadBytes: bytes,
      payloadSha256: hash,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  console.log(`✅ Published ${id} v${version} -> ${storagePath} (${bytes} bytes)`);
}

async function main() {
  const dir = process.argv[2];
  if (!dir) throw new Error("Usage: node tools/publish_course_configs.js <folder-of-json-files>");

  const abs = path.resolve(dir);
  const files = fs.readdirSync(abs).filter((f) => f.toLowerCase().endsWith(".json"));
  if (!files.length) throw new Error(`No .json files found in ${abs}`);

  for (const f of files) {
    await publishOne(path.join(abs, f));
  }

  console.log("🎉 Done.");
}

main().catch((e) => {
  console.error("❌ Publish failed:", e);
  process.exit(1);
});
