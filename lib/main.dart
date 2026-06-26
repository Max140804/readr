import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/timetable_data.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'services/update_service.dart';
import 'services/connectivity_service.dart';
import 'services/material_sync_service.dart';
import 'splash_screen.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

void main() async {
  runZonedGuarded(() async {
    // Ensure we don't block the UI thread with any async tasks
    WidgetsFlutterBinding.ensureInitialized();
    
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {}

    final url = dotenv.env['SUPABASE_URL'] ?? 'https://hcqaseovlciadogewnsw.supabase.co';
    final key = dotenv.env['SUPABASE_ANON_KEY'] ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhjcWFzZW92bGNpYWRvZ2V3bnN3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDczMjYsImV4cCI6MjA5NTI4MzMyNn0.HUeREBkAYeZYyv9ekq5a0kVuhpAgFTJJzydzau8Zrdk';

    await Supabase.initialize(url: url, anonKey: key);

    // Initialize services in the background so the app starts instantly
    final notificationService = NotificationService();
    await notificationService.init();
    await initializeBackgroundService();
    UpdateService.listenForUpdates();
    ConnectivityService().init();
    MaterialSyncService().syncAllMaterials(); // Start background sync

    // Request ignore battery optimizations on Android
    if (Platform.isAndroid) {
      try {
        final status = await Permission.ignoreBatteryOptimizations.status;
        if (!status.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
        
        // Request exact alarm permission for Android 12+
        if (await Permission.scheduleExactAlarm.isDenied) {
          await Permission.scheduleExactAlarm.request();
        }
      } catch (e) {
        debugPrint("Battery optimization permission error: $e");
      }
    }

    // Set status bar immediately
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    runApp(const MyApp());
  }, (error, stack) {
    debugPrint("GLOBAL CRASH CAUGHT: $error");
    debugPrint("STACK: $stack");
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState of(BuildContext context) => 
      context.findAncestorStateOfType<MyAppState>()!;

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? 0];
        });
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  ThemeMode get themeMode => _themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Readr',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AcademicTheme.background,
        // Removed GoogleFonts from here as it can cause network hangs during startup
        colorScheme: ColorScheme.fromSeed(seedColor: AcademicTheme.primary),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AcademicTheme.darkBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AcademicTheme.darkPrimary, 
          brightness: Brightness.dark
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
