import 'dart:convert';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // rootBundle

class CourseConfigService {
  CourseConfigService._();
  static final CourseConfigService instance = CourseConfigService._();

  final _cache = <String, Map<String, dynamic>>{};
  final _fs = FirebaseFirestore.instance;

  // Be explicit with your bucket (yours is NOT the classic appspot.com)
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'gs://familyflow-576e1.firebasestorage.app',
  );

  /// Loads curriculum by ID.
  ///
  /// Priority:
  /// 1) in-memory cache
  /// 2) Firestore metadata -> Storage JSON payload
  /// 3) local asset fallback: assets/courseConfigs/{configId}.json
  Future<Map<String, dynamic>?> getConfig(String configId) async {
    final key = configId.trim();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

    // 1) Try global config: Firestore -> Storage
    try {
      final metaSnap = await _fs.collection('courseConfigs').doc(key).get();
      final meta = metaSnap.data();

      final storagePath = (meta?['payloadStoragePath'] ?? '').toString().trim();
      if (storagePath.isNotEmpty) {
        final cfg = await _downloadJsonFromStorage(storagePath);
        _cache[key] = cfg;
        return cfg;
      }
    } catch (e, st) {
      debugPrint('CourseConfigService.getConfig($key) global load failed: $e');
      debugPrint('$st');
    }

    // 2) Fallback to local asset (keeps current behavior during transition)
    try {
      final jsonString = await rootBundle.loadString('assets/courseConfigs/$key.json');
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        _cache[key] = decoded;
        return decoded;
      }
    } catch (e) {
      debugPrint('CourseConfigService.getConfig($key) asset fallback failed: $e');
    }

    return null;
  }

  Future<Map<String, dynamic>> _downloadJsonFromStorage(String storagePath) async {
    // Large configs are fine in Storage. Set a reasonable download cap.
    const maxSizeBytes = 20 * 1024 * 1024; // 20 MB

    final ref = _storage.ref(storagePath);
    final Uint8List? bytes = await ref.getData(maxSizeBytes);

    if (bytes == null || bytes.isEmpty) {
      throw StateError('Storage JSON empty or missing: $storagePath');
    }

    final raw = utf8.decode(bytes);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Course config root must be a JSON object: $storagePath');
    }
    return decoded;
  }

  /// OPTIONAL: clear cache if you want a manual refresh button.
  void clearCache() => _cache.clear();

  int basePointsFor(Map<String, dynamic> cfg, String categoryKey) {
    final rewards = (cfg['rewards'] as Map?)?.cast<String, dynamic>() ?? const {};
    final base = (rewards['basePoints'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = base[categoryKey];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  double multiplierFor(
    Map<String, dynamic> cfg, {
    required String categoryKey,
    int? gradePercent,
  }) {
    final rewards = (cfg['rewards'] as Map?)?.cast<String, dynamic>() ?? const {};
    final multipliers = (rewards['multipliers'] as List?) ?? const [];

    double mult = 1.0;

    for (final m in multipliers) {
      if (m is! Map) continue;
      final mm = m.cast<String, dynamic>();

      final when = (mm['when'] as Map?)?.cast<String, dynamic>() ?? const {};
      final whenCategory = (when['categoryKey'] ?? '').toString();
      if (whenCategory.isNotEmpty && whenCategory != categoryKey) continue;

      final minGrade = when['minGradePercent'];
      if (minGrade != null && gradePercent != null) {
        final mg = (minGrade is num) ? minGrade.toInt() : int.tryParse(minGrade.toString());
        if (mg != null && gradePercent < mg) continue;
      }

      final rawMult = mm['multiplier'];
      final dm = (rawMult is num) ? rawMult.toDouble() : double.tryParse(rawMult.toString());
      if (dm != null && dm > 0) {
        mult *= dm;
      }
    }

    return mult;
  }
}
