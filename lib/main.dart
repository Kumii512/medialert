import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/edit_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'models/medication.dart';
import 'constants/app_theme.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrapper());
}

class AppBootstrapper extends StatefulWidget {
  const AppBootstrapper({super.key});

  @override
  State<AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<AppBootstrapper> {
  bool _initialized = false;
  String? _error;
  bool _forceContinue = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    // Fallback: If initialization takes too long, force continue after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (!_initialized && mounted) {
        setState(() {
          _forceContinue = true;
        });
      }
    });
  }

  Future<void> _initialize() async {
    try {
      await _safeInitializeServices();
      setState(() {
        _initialized = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Initialization failed:\n\n$_error',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _forceContinue = true;
                    });
                  },
                  child: const Text('Continue Anyway'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!_initialized && !_forceContinue) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return const MyApp();
  }
}

Future<void> _safeInitializeServices() async {
  debugPrint('Starting Firebase initialization');
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  debugPrint('Starting NotificationService initialization');
  try {
    await NotificationService().initialize();
    debugPrint('NotificationService initialized');
  } catch (e) {
    debugPrint('Local notification initialization error: $e');
  }

  debugPrint('Starting PushNotificationService initialization');
  try {
    await PushNotificationService().initialize();
    debugPrint('PushNotificationService initialized');
  } catch (e) {
    debugPrint('Push notification initialization error: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'MediAlert',
          theme: AppThemes.lightTheme(),
          darkTheme: AppThemes.darkTheme(),
          themeMode: themeMode,
          debugShowCheckedModeBanner: false,
          initialRoute: '/landing',
          routes: {
            '/landing': (context) => const WelcomeScreen(),
            '/auth': (context) => const AuthScreen(),
            '/welcome': (context) => const WelcomeScreen(),
            '/app': (context) => const AuthGate(),
            '/home': (context) => const AuthGate(),
            '/history': (context) => const HistoryScreen(),
            '/settings': (context) => const SettingsScreen(),
            '/edit': (context) {
              final medication =
                  ModalRoute.of(context)?.settings.arguments as Medication?;
              return EditScreen(medication: medication);
            },
          },
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == null) {
          return const AuthScreen();
        }

        return const HomeScreen();
      },
    );
  }
}
