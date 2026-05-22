import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/notification_service.dart';
import 'data/timetable_data.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }

  // Make the app fullscreen
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  
  // Initialize notification service
  await NotificationService().init();
  
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found or could not be loaded: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>()!;

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0; // 0: system, 1: light, 2: dark
    setState(() {
      _themeMode = ThemeMode.values[themeIndex];
    });
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  @override
  Widget build(BuildContext context) {
    // Re-apply fullscreen mode on build to ensure it sticks
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return MaterialApp(
      title: 'Readr',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AcademicTheme.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AcademicTheme.primary,
          primary: AcademicTheme.primary,
          secondary: AcademicTheme.secondary,
          surface: AcademicTheme.card,
          onPrimary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AcademicTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AcademicTheme.card,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AcademicTheme.darkBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AcademicTheme.darkPrimary,
          brightness: Brightness.dark,
          primary: AcademicTheme.darkPrimary,
          secondary: AcademicTheme.darkSecondary,
          surface: AcademicTheme.darkCard,
          onPrimary: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AcademicTheme.darkCard,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AcademicTheme.darkCard,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AcademicTheme.darkTextPrimary),
          bodyMedium: TextStyle(color: AcademicTheme.darkTextPrimary),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
