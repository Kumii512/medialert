import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/edit_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'models/medication.dart';
import 'constants/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    // Wait for auth state to fully initialize
    await Future.delayed(const Duration(milliseconds: 1000));
  } catch (e) {
    print('Firebase initialization error: $e');
  }

  runApp(const MyApp());
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
          initialRoute: '/welcome',
          routes: {
            '/welcome': (context) => const WelcomeScreen(),
            '/home': (context) => const HomeScreen(),
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
