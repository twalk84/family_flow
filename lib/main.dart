// FILE: lib/main.dart
//
// App entrypoint + startup bootstrap.
//
// Includes:
// - Firebase.initializeApp()
// - Optional CourseConfigLoader smoke test (debug by default)
// - AuthGate (login/register)
// - Named route foundation

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'; // kDebugMode, debugPrintStack
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/routes.dart';
import 'firebase_options.dart';
import 'firestore_bootstrap.dart';

import 'core/course_configs/course_config_loader.dart';

import 'screens/menu_screen.dart';
import 'screens/help_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/daily_schedule_screen.dart';
import 'screens/assistant_standalone_screen.dart';

import 'widgets/app_scaffolds.dart';

/// Flip this ONLY if you want smoke tests to run in release builds too.
const bool kRunCourseConfigSmokeTestInRelease = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Run all pre-runApp initialization here.
  await _bootstrap();

  runApp(const FamilyFlowApp());
}

/// All startup initialization that must happen before runApp().
Future<void> _bootstrap() async {
  debugPrint('--- FamilyFlow bootstrap: begin ---');

  // 1) Firebase
  debugPrint('Bootstrap: Firebase.initializeApp()...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('Bootstrap: Firebase.initializeApp() OK');

  // 2) Course config smoke test (debug by default)
  final shouldRunSmokeTest = kDebugMode || kRunCourseConfigSmokeTestInRelease;

  if (shouldRunSmokeTest) {
    debugPrint('Bootstrap: CourseConfigLoader.smokeTest()...');
    try {
      await CourseConfigLoader.smokeTest();
      debugPrint('Bootstrap: CourseConfigLoader.smokeTest() OK');
    } catch (e, st) {
      // We do NOT want a config test to block the whole app unless you want it to.
      debugPrint('Bootstrap: CourseConfigLoader.smokeTest() FAILED: $e');
      debugPrintStack(stackTrace: st);

      // If you want this to HARD FAIL instead, replace the above with:
      // rethrow;
    }
  } else {
    debugPrint('Bootstrap: smokeTest skipped (release mode).');
  }

  debugPrint('--- FamilyFlow bootstrap: done ---');
}

class FamilyFlowApp extends StatelessWidget {
  const FamilyFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF111827),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.purple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      // Named routes foundation
      initialRoute: AppRoutes.authGate,
      routes: {
        AppRoutes.authGate: (_) => const AuthGate(),
        AppRoutes.menu: (_) => const MenuScreen(),
        AppRoutes.dashboard: (_) => const DashboardScreen(),
        AppRoutes.dailySchedule: (_) => const DashboardScreen(openScheduleOnStart: true),
        AppRoutes.assistant: (_) => const AssistantStandaloneScreen(),
        AppRoutes.help: (_) => const HelpScreen(),
      },

      // Helpful fallback for debugging if you navigate to a missing route
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => ErrorScaffold(
            title: 'Unknown route',
            message:
                'No route registered for: ${settings.name}\n\n'
                'Check lib/app/routes.dart and MaterialApp.routes in main.dart.',
          ),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LoadingScaffold();
        }

        final user = snap.data;
        if (user == null) return const LoginScreen();

        return FutureBuilder<void>(
          future: FirestoreBootstrap.ensureUserBootstrap(user),
          builder: (context, bootSnap) {
            if (bootSnap.connectionState != ConnectionState.done) {
              return const LoadingScaffold();
            }
            if (bootSnap.hasError) {
              return ErrorScaffold(
                title: 'Bootstrap error',
                message: bootSnap.error.toString(),
              );
            }
            return const MenuScreen();
          },
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();

  bool _isRegister = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final email = _email.text.trim();
      final pass = _pass.text;

      if (email.isEmpty || pass.isEmpty) {
        throw Exception('Please enter email + password.');
      }

      if (_isRegister) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'FamilyFlow',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegister ? 'Create your account' : 'Sign in',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.35)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    if (_error != null) const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.purple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isRegister ? 'Create Account' : 'Sign In'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () => setState(() => _isRegister = !_isRegister),
                      child: Text(
                        _isRegister
                            ? 'Already have an account? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
