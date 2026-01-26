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

  /// Standard emojis for mood tracking (Dashboard + Student Profile)
  static const List<String> availableMoods = [
    '😀', // Grinning Face (General happiness)
    '😇', // Smiling Face with Halo (Feeling good or proud of work)
    '🥳', // Partying Face (Excitement for a breakthrough or activity)
    '🤔', // Thinking Face (Focused and deep in thought)
    '💡', // Light Bulb (Inspired or just had an "Aha!" moment)
    '🤩', // Star-Eyed Face (Amused or impressed)
    '😌', // Relieved Face (Feeling calm or finished with a task)
    '😴', // Sleeping Face (Tired or lacking energy)
    '😔', // Pensive Face (Quiet or thoughtful)
    '😕', // Confused Face (Feeling stuck or unsure of a lesson)
    '🫠', // Melting Face (Feeling a bit overwhelmed)
    '☹️', // Frowning Face (Sad or disappointed)
    '😤', // Face with Steam from Nose (Frustrated with a challenge)
    '🤯', // Exploding Head (Experiencing "brain fog" or information overload)
    '🙃', // Upside-Down Face (Feeling silly or goofy)
    '😎', // Wearing Shades (Feeling cool)
  ];
}
