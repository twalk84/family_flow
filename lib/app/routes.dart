// FILE: lib/app/routes.dart
//
// Centralized named routes for the app.
// Keep these stable so navigation stays consistent.

class AppRoutes {
  AppRoutes._();

  // Core
  static const String authGate = '/';
  static const String menu = '/menu';

  // Main screens
  static const String dashboard = '/dashboard';
  static const String dailySchedule = '/daily-schedule';
  static const String assistant = '/assistant';
  static const studentSelection = '/student-selection';

  // Future
  static const String help = '/help';
  static const String achievements = '/achievements';
}
