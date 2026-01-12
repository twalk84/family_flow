import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class CourseConfigLoader {
  static Future<Map<String, dynamic>> loadRaw(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Course config must be a JSON object at the root.');
    }
    return decoded;
  }

  static Future<void> smokeTest() async {
    const path = 'assets/courseConfigs/general_chemistry_v1.json';
    final map = await loadRaw(path);
    debugPrint('✅ Loaded course config: $path');
    debugPrint('Top-level keys: ${map.keys.toList()}');
  }
}
