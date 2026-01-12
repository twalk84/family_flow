import 'package:cloud_firestore/cloud_firestore.dart';

class CourseConfigService {
  CourseConfigService._();
  static final CourseConfigService instance = CourseConfigService._();

  final _cache = <String, Map<String, dynamic>>{};

  /// Loads: courseConfigs/{configId}
  Future<Map<String, dynamic>?> getConfig(String configId) async {
    final key = configId.trim();
    if (key.isEmpty) return null;

    final cached = _cache[key];
    if (cached != null) return cached;

    final snap = await FirebaseFirestore.instance.collection('courseConfigs').doc(key).get();
    final data = snap.data();
    if (data == null) return null;

    _cache[key] = data;
    return data;
  }

  int basePointsFor(Map<String, dynamic> cfg, String categoryKey) {
    final rewards = (cfg['rewards'] as Map?)?.cast<String, dynamic>() ?? const {};
    final base = (rewards['basePoints'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = base[categoryKey];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  double multiplierFor(Map<String, dynamic> cfg, {required String categoryKey, int? gradePercent}) {
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
        // If multiple apply, multiply (simple + flexible).
        mult *= dm;
      }
    }

    return mult;
  }
}
