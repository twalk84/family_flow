// FILE: lib/app_config.dart
//
// Central place for app-wide constants.
// We intentionally removed any “server address / port” runtime settings.
// The assistant endpoint is configured in AssistantClient.baseUrl.

class AppConfig {
  AppConfig._();

  static const String appName = 'FamilyFlow';

  /// Firestore default seed names (used by bootstrap/seed routines).
  static const List<String> defaultSubjects = <String>[
    'Math',
    'English',
    'Science',
  ];

  /// If you want to rename the default "teacher mood" field or doc, keep it here.
  static const String settingsDocId = 'app';
}
