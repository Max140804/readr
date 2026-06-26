import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notifications_page.dart';
import 'study_alarm_page.dart';
import 'login_page.dart';

import 'PDFPage.dart';
import 'all_courses_page.dart';
import 'assistant_page.dart';
import 'timetable_page.dart';
import 'community_forum_page.dart';
import 'admin_profile_page.dart';
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';
import 'youtube_videos_page.dart';
import 'bookmarks_page.dart';
import 'past_questions_page.dart';
import 'assignments_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/activity_service.dart';
import 'services/connectivity_service.dart';
import 'services/material_sync_service.dart';
import 'utils/responsive_utils.dart';

import 'data/course_data.dart';

class Dashboard extends StatefulWidget {
  final String userName;
  final String userId;
  final bool isAdmin;
  final bool isDev;
  const Dashboard({super.key, this.userName = "Max", this.userId = "user_1", this.isAdmin = false, this.isDev = false});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int currentIndex = 0;
  Timer? _timer;
  String _timerText = "00:00:00";
  String _statusLabel = "Next Class In";
  String _subMessage = "Loading schedule...";
  bool _isLockInEnabled = false;
  bool _hasNewForumMessage = false;
  bool _isOffline = false;
  StreamSubscription? _forumSubscription;
  StreamSubscription? _announcementSubscription;
  late final int _sessionStartTime;

  String get _currentUserId => widget.userId;

  // Recent Activity State
  String? recentTitle;
  String? recentSubtitle;
  String? recentType;
  String? recentUrl;
  String? recentPath;
  String? recentCourse;

  @override
  void initState() {
    super.initState();
    _sessionStartTime = DateTime.now().millisecondsSinceEpoch;
    FlutterBackgroundService().invoke('setAsForeground');
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
    _loadRecentActivity();
    _initNotifications();
    _checkDndStatus();
    _initForumListener();
    _initAnnouncementListener();
    _checkAndApplyLockInTrigger();
    _initMethodChannel();
    _initConnectivityListener();
    
    // Check for updates locally/remotely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
    });
  }

  void _initConnectivityListener() {
    _isOffline = !ConnectivityService().isConnected;
    ConnectivityService().connectivityStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isOffline = !connected;
        });
        
        if (!connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You're offline. Some features may be limited."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  void _initMethodChannel() {
    if (!Platform.isAndroid) return;
    platform.setMethodCallHandler((call) async {
      if (call.method == "triggerLockIn") {
        if (!_isLockInEnabled) {
          await _toggleLockInMode();
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _forumSubscription?.cancel();
    _announcementSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      FlutterBackgroundService().invoke('setAsForeground');
      _checkAndApplyLockInTrigger();
      _loadRecentActivity();
      _checkDndStatus(); // Refresh lock-in status when coming back
    } else if (state == AppLifecycleState.paused) {
      FlutterBackgroundService().invoke('setAsBackground');
    } else if (state == AppLifecycleState.detached) {
      // If the app is being destroyed/closed, turn off Lock-in mode
      if (_isLockInEnabled) {
        platform.invokeMethod('setInterruptionFilter', {"filter": 1});
      }
    }
  }

  Future<void> _checkAndApplyLockInTrigger() async {
    final prefs = await SharedPreferences.getInstance();
    final trigger = prefs.getBool('trigger_lock_in') ?? false;
    if (trigger) {
      await prefs.setBool('trigger_lock_in', false);
      if (!_isLockInEnabled) {
        await _toggleLockInMode();
      }
    }
  }

  void _initAnnouncementListener() {
    final supabase = Supabase.instance.client;
    _announcementSubscription = supabase
        .from('announcements')
        .stream(primaryKey: ['id'])
        .listen((docs) async {
      if (docs.isNotEmpty) {
        // Sort manually by id if the stream doesn't guarantee order
        docs.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
        
        final lastAnn = docs.first;
        final String id = lastAnn['id'].toString();
        final String title = lastAnn['title'] ?? "New Announcement";
        final String body = lastAnn['body'] ?? "";
        
        final prefs = await SharedPreferences.getInstance();
        final lastNotifiedAnnId = prefs.getString('last_announcement_id');

        if (lastNotifiedAnnId != id) {
          await prefs.setString('last_announcement_id', id);
          
          // Trigger local notification and save to history
          NotificationService().showNotificationNow(
            "📢 $title",
            body,
            saveToLog: true,
          );
        }
      }
    }, onError: (e) {
      debugPrint("Announcement sync error: $e");
    });
  }

  void _initForumListener() async {
    final prefs = await SharedPreferences.getInstance();
    final supabase = Supabase.instance.client;
    
    _forumSubscription = supabase
        .from('forum_messages')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: true)
        .listen((docs) {
      if (docs.isNotEmpty) {
        final lastMsgData = docs.last;
        final dynamic stamp = lastMsgData['timestamp'];
        if (stamp == null) return;

        final lastMsgTime = DateTime.parse(stamp).millisecondsSinceEpoch;
        final lastMsgId = lastMsgData['id']?.toString();
        final senderUid = lastMsgData['uid']?.toString();
        
        // Use user-specific keys to prevent leaks between student logins
        final lastSeenKey = 'last_seen_forum_$_currentUserId';
        final lastNotifiedKey = 'last_notified_msg_id_$_currentUserId';
        
        final lastSeen = prefs.getInt(lastSeenKey) ?? 0;
        final lastNotifiedId = prefs.getString(lastNotifiedKey);

        // 1. Red Dot: Always show if there's ANY message newer than the last time we opened the forum
        if (lastMsgTime > lastSeen && senderUid != _currentUserId) {
           if (mounted) setState(() => _hasNewForumMessage = true);
        }

        // 2. Notification Logic:
        // Handled primarily by the background service to avoid duplicate streams
        // and ensure delivery in all app states.
        /*
        final isNewSinceLastSeen = lastMsgTime > lastSeen;
        final isNotAlreadyNotified = lastMsgId != lastNotifiedId;

        if (isNotAlreadyNotified && isNewSinceLastSeen && senderUid != _currentUserId) {
           if (mounted) {
             if (lastMsgId != null) prefs.setString(lastNotifiedKey, lastMsgId);

             NotificationService().showNotificationNow(
               lastMsgData['sender'] ?? "Scholr",
               lastMsgData['text'] ?? "Sent an image 🖼️",
               saveToLog: false,
             );
           }
        }
        */
      }
    }, onError: (e) => debugPrint("Forum sync error: $e"));
  }

  static const platform = MethodChannel('com.example.readr/dnd');

  Future<void> _checkDndStatus() async {
    if (!Platform.isAndroid) return;
    try {
      final int? status = await platform.invokeMethod('getCurrentInterruptionFilter');
      if (mounted) {
        setState(() {
          _isLockInEnabled = status != null && status != 1; // 1 is INTERRUPTION_FILTER_ALL
        });
      }
    } catch (e) {
      debugPrint("Error checking DND status: $e");
    }
  }

  Future<void> _toggleLockInMode() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lock-in mode is currently only available on Android")),
      );
      return;
    }
    try {
      final bool? isGranted = await platform.invokeMethod('isNotificationPolicyAccessGranted');
      if (isGranted != true) {
        await platform.invokeMethod('gotoPolicySettings');
        return;
      }

      final String action;
      if (_isLockInEnabled) {
        await platform.invokeMethod('setInterruptionFilter', {"filter": 1}); // INTERRUPTION_FILTER_ALL
        action = "Disabled";
      } else {
        await platform.invokeMethod('setInterruptionFilter', {"filter": 2}); // INTERRUPTION_FILTER_PRIORITY
        action = "Enabled";
      }
      
      final int? newStatus = await platform.invokeMethod('getCurrentInterruptionFilter');
      setState(() {
        _isLockInEnabled = newStatus != null && newStatus != 1;
      });

      // Track Lock-in Activity
      ActivityService().trackActivity(
        title: "Lock-in Mode $action",
        subtitle: "Student toggled focus mode",
        type: 'focus',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isLockInEnabled ? "Lock-in Mode Enabled 🔒" : "Lock-in Mode Disabled 🔓"),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error toggling Lock-in mode: $e");
    }
  }

  Future<void> _initNotifications() async {
    try {
      final notificationService = NotificationService();
      await notificationService.init();
      await notificationService.requestPermissions(); // Ensure permissions are granted
      await notificationService.scheduleTimetableNotifications();
    } catch (e) {
      debugPrint("Notification initialization failed: $e");
    }
  }

  Future<void> _loadRecentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        recentTitle = prefs.getString('recent_title');
        recentSubtitle = prefs.getString('recent_subtitle');
        recentType = prefs.getString('recent_type');
        recentUrl = prefs.getString('recent_url');
        recentPath = prefs.getString('recent_path');
        recentCourse = prefs.getString('recent_course');
      });
    }
  }


  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateCountdown();
      }
    });
  }

  void _updateCountdown() {
    final now = DateTime.now();
    const days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];

    // 1. Weekend Check
    if (now.weekday > 5) {
      setState(() {
        _timerText = "It's Weekend Baby 🎉";
        _statusLabel = "Weekend Mode";
        _subMessage = "Enjoy the weekend! 🥳";
      });
      return;
    }

    // 2. Friday Check
    if (now.weekday == 5) {
      setState(() {
        _timerText = "Lecture free day innit! 😎";
        _statusLabel = "Friday";
        _subMessage = "Have fun!";
      });
      return;
    }

    final today = days[now.weekday - 1];
    final todaySchedule = timetable[today] ?? [];

    for (var item in todaySchedule) {
      final timeStr = item["time"] ?? "0:0 AM - 0:0 AM";
      final parts = timeStr.split("-");
      
      int startH = _parseHour(parts[0]);
      int endH = _parseHour(parts[1]);

      final startTime = DateTime(now.year, now.month, now.day, startH, 0);
      final endTime = DateTime(now.year, now.month, now.day, endH, 0);

      // A. Check if currently IN class
      if (now.isAfter(startTime) && now.isBefore(endTime)) {
        setState(() {
          _timerText = item["course"] ?? "Class";
          _statusLabel = "Ongoing Class";
          _subMessage = "Pay attention, bub! 📚";
        });
        return;
      }

      // B. Check if class is coming UP (this will be the 'Next Class')
      if (startTime.isAfter(now)) {
        final diff = startTime.difference(now);
        final h = diff.inHours.toString().padLeft(2, '0');
        final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
        final s = (diff.inSeconds % 60).toString().padLeft(2, '0');

        setState(() {
          _timerText = "$h:$m:$s";
          _statusLabel = "Next: ${item["course"]}";
          _subMessage = "Get ready, bub";
        });
        return;
      }
    }

    // 3. End of Day
    setState(() {
      _timerText = "Done for today! 🎉";
      _statusLabel = "Classes Over";
      _subMessage = "We go again tomorrow";
    });
  }

  int _parseHour(String timePart) {
    timePart = timePart.trim().toUpperCase();
    // Extract digit before the first colon or space
    int hour = int.tryParse(timePart.split(":")[0]) ?? 0;
    
    if (timePart.contains("PM") && hour < 12) {
      hour += 12;
    } else if (timePart.contains("AM") && hour == 12) {
      hour = 0;
    }
    return hour;
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', false);
    await prefs.remove('userName');
    await prefs.remove('isAdmin');
    await prefs.remove('isDev');
    
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _loadRecentActivity());
  }

  void _showStorageManagementDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Storage Management"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Cleaning the cache will remove all offline materials. You will need to re-sync them to access them without internet."),
            const SizedBox(height: 15),
            FutureBuilder<double>(
              future: MaterialSyncService().getCacheSize(),
              builder: (context, snapshot) {
                return Text(
                  "Total Storage Used: ${snapshot.data?.toStringAsFixed(1) ?? '...'} MB",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              await MaterialSyncService().clearCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Offline cache cleared")),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Clear Cache"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isDesktop = Responsive.isDesktop(context) || Responsive.isTablet(context);
    final bool isSmallHeight = MediaQuery.of(context).size.height < 500;

    Widget mainContent = SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.getHorizontalPadding(context), 
          vertical: 10
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isOffline)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        "You may be disconnected from the internet, please check in later",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            /// TOP BAR
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isDesktop)
                  IconButton(
                    icon: const Icon(Icons.menu, size: 28),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  )
                else
                  const SizedBox(width: 5),
                Row(
                  children: [
                ListenableBuilder(
                  listenable: MaterialSyncService(),
                  builder: (context, _) {
                    final syncService = MaterialSyncService();
                    if (!syncService.isSyncing) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: "Syncing materials: ${(syncService.syncProgress * 100).toInt()}%",
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.green)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "${(syncService.syncProgress * 100).toInt()}%",
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<Map<String, dynamic>?>(
                      valueListenable: UpdateService.updateAvailableNotifier,
                      builder: (context, update, child) {
                        if (update == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: "Update Available (${update['version']})",
                            child: GestureDetector(
                              onTap: () => UpdateService.startUpdateFlow(
                                context, 
                                update['url'], 
                                update['version']
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: (isDark ? AcademicTheme.darkPrimary : Colors.blue.shade600).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (isDark ? AcademicTheme.darkPrimary : Colors.blue.shade600).withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.system_update_rounded, 
                                      size: 18, 
                                      color: isDark ? AcademicTheme.darkPrimary : Colors.blue.shade700
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "UPDATE AVAILABLE",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        color: isDark ? AcademicTheme.darkPrimary : Colors.blue.shade800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsPage()),
                        ).then((_) => setState(() {}));
                      },
                      child: FutureBuilder<List<NotificationHistoryItem>>(
                        future: NotificationService().getHistory(),
                        builder: (context, snapshot) {
                          final hasUnread = snapshot.hasData && snapshot.data!.any((e) => !e.isRead);
                          return Stack(
                            children: [
                              const Icon(Icons.notifications_none, size: 28),
                              if (hasUnread)
                                Positioned(
                                  right: 0,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(color: AcademicTheme.accent, shape: BoxShape.circle),
                                  ),
                                )
                            ],
                          );
                        }
                      ),
                    ),
                    const SizedBox(width: 15),
                    const CircleAvatar(
                      radius: 18,
                      backgroundColor: AcademicTheme.primary,
                      child: Icon(Icons.person, color: Colors.white, size: 20),
                    )
                  ],
                )
              ],
            ),
            const SizedBox(height: 25),
            /// GREETING
            Text(_getGreeting(), style: TextStyle(fontSize: 18, color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey)),
            const SizedBox(height: 5),
            Text(
              widget.userName, 
              style: TextStyle(
                fontSize: 34, 
                fontWeight: FontWeight.bold, 
                color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary
              )
            ),
            const SizedBox(height: 20),

            /// NEXT CLASS CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AcademicTheme.primary,
                    AcademicTheme.primary.withValues(alpha: 0.8),
                    AcademicTheme.secondary,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: AcademicTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 25,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Decorative background element
                  Positioned(
                    right: -20,
                    top: -20,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_awesome, color: AcademicTheme.accent.withValues(alpha: 0.9), size: 12),
                                const SizedBox(width: 6),
                                Text(
                                  _statusLabel.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white, 
                                    fontSize: 10, 
                                    letterSpacing: 1.5, 
                                    fontWeight: FontWeight.w800
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_statusLabel.contains("Ongoing"))
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 1500),
                              builder: (context, value, child) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: value),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: Colors.redAccent.withValues(alpha: 0.5 * value), blurRadius: 4)
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text("LIVE", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFE0E0E0)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _timerText,
                            maxLines: 1,
                            style: GoogleFonts.outfit(
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 72, 
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2,
                                height: 0.9,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _subMessage, 
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7), 
                          fontSize: 16, 
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        )
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),
            /// QUICK ACCESS
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text("Quick Access", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: _QuickAccess(icon: Icons.alarm, label: "Study Alarm", onTap: () => _navigateTo(const StudyAlarmPage()))),
                Expanded(child: _QuickAccess(icon: Icons.calendar_month, label: "Timetable", onTap: () => _navigateTo(const TimetablePage()))),
                Expanded(child: _QuickAccess(icon: Icons.support_agent, label: "Assistant", onTap: () => _navigateTo(const AssistantPage()))),
                Expanded(child: _QuickAccess(icon: Icons.assignment_outlined, label: "Assignments", onTap: () => _navigateTo(AssignmentsPage(courseName: "All", assignments: [], isAdmin: widget.isAdmin)))),
                Expanded(
                  child: _QuickAccess(
                    icon: _isLockInEnabled ? Icons.lock : Icons.lock_open, 
                    label: "Lock-in", 
                    onTap: _toggleLockInMode,
                    color: _isLockInEnabled ? AcademicTheme.accent : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),
            /// COURSES HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Courses", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: () => _navigateTo(AllCoursesPage(isAdmin: widget.isAdmin)),
                  child: const Text("See All", style: TextStyle(color: AcademicTheme.accent, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            /// COURSE GRID
            GridView.builder(
              itemCount: CourseData.getCourses().where((c) => c['semester'] == 1).length > 4 
                ? 4 
                : CourseData.getCourses().where((c) => c['semester'] == 1).length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.getGridColumnCount(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: Responsive.isMobile(context) ? 0.85 : 1.1,
              ),
              itemBuilder: (context, index) {
                final course = CourseData.getCourses().where((c) => c['semester'] == 1).toList()[index];
                return _CourseCard(
                  title: course["title"] as String,
                  subtitle: course["subtitle"] as String,
                  icon: course["icon"] as IconData,
                  pdfs: (course["pdfs"] as List?) ?? [],
                  videos: (course["videos"] as List?) ?? [],
                  pastQuestions: (course["pastQuestions"] as List?) ?? [],
                  onReturn: _loadRecentActivity,
                  isAdmin: widget.isAdmin,
                  credits: course["credits"] as int? ?? 3,
                );
              },
            ),

            const SizedBox(height: 30),
            /// RECENT ACTIVITY
            if (recentTitle != null) ...[
              const Text("Recent Activity", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              GestureDetector(
                onTap: () {
                  if (recentType == 'pdf' && recentPath != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => SmartPDFViewerPage(title: recentTitle!, assetPath: recentPath!))).then((_) => _loadRecentActivity());
                  } else if (recentType == 'video' && recentUrl != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(videoUrl: recentUrl!, title: recentTitle!))).then((_) => _loadRecentActivity());
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.cardTheme.color,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: (recentType == 'pdf' ? Colors.red : Colors.redAccent).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(recentType == 'pdf' ? Icons.picture_as_pdf : Icons.play_circle_fill, color: recentType == 'pdf' ? Colors.red : Colors.redAccent, size: 30),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(recentTitle ?? "No Recent activity", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary)),
                            const SizedBox(height: 5),
                            Text(recentSubtitle ?? "Start learning to see activity", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: AcademicTheme.accent),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: AcademicTheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(
                      widget.isAdmin ? Icons.admin_panel_settings : Icons.person,
                      color: AcademicTheme.primary,
                      size: 35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(widget.isAdmin ? "Administrator" : widget.isDev ? "Developer" : "ECE Student", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings_display),
              title: const Text("Theme Mode"),
            ),
            RadioListTile<ThemeMode>(
              title: const Text("System Settings"),
              value: ThemeMode.system,
              groupValue: MyApp.of(context).themeMode,
              onChanged: (mode) => MyApp.of(context).setThemeMode(mode!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text("Light Mode"),
              value: ThemeMode.light,
              groupValue: MyApp.of(context).themeMode,
              onChanged: (mode) => MyApp.of(context).setThemeMode(mode!),
            ),
            RadioListTile<ThemeMode>(
              title: const Text("Dark Mode"),
              value: ThemeMode.dark,
              groupValue: MyApp.of(context).themeMode,
              onChanged: (mode) => MyApp.of(context).setThemeMode(mode!),
            ),
            const Divider(),
            ListenableBuilder(
              listenable: MaterialSyncService(),
              builder: (context, _) {
                final syncService = MaterialSyncService();
                return ListTile(
                  leading: Icon(
                    syncService.isSyncing ? Icons.sync : Icons.cloud_done,
                    color: syncService.isSyncing ? Colors.orange : Colors.green,
                  ),
                  title: const Text("Material Sync"),
                  subtitle: Text(
                    syncService.isSyncing 
                        ? "Syncing: ${(syncService.syncProgress * 100).toInt()}% (${syncService.downloadedFiles}/${syncService.totalFiles})"
                        : "All materials available offline",
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: syncService.isSyncing 
                      ? null 
                      : IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () => syncService.syncAllMaterials(),
                        ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_rounded, color: Colors.blueGrey),
              title: const Text("Storage Management"),
              subtitle: FutureBuilder<double>(
                future: MaterialSyncService().getCacheSize(),
                builder: (context, snapshot) {
                  final size = snapshot.data ?? 0.0;
                  return Text("${size.toStringAsFixed(1)} MB used for offline files", style: const TextStyle(fontSize: 12));
                },
              ),
              onTap: () => _showStorageManagementDialog(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
      ),
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              selectedIndex: currentIndex,
              onDestinationSelected: (index) {
                _onNavBarTap(index);
              },
              backgroundColor: isDark ? AcademicTheme.darkCard : Colors.white,
              labelType: isSmallHeight ? NavigationRailLabelType.selected : NavigationRailLabelType.all,
              groupAlignment: 0.0,
              useIndicator: true,
              indicatorColor: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.12),
              minWidth: 80,
              indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              selectedIconTheme: IconThemeData(
                color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary, 
                size: 28
              ),
              unselectedIconTheme: IconThemeData(
                color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey.shade600, 
                size: 24
              ),
              selectedLabelTextStyle: TextStyle(
                color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary, 
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
              unselectedLabelTextStyle: TextStyle(
                color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey.shade600,
                fontSize: 12,
              ),
              leading: isSmallHeight ? null : Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/logo.png', width: 48, height: 48),
                  ),
                ),
              ),
              trailing: isSmallHeight ? null : Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 26),
                    tooltip: "Logout",
                    onPressed: _logout,
                  ),
                  const SizedBox(height: 30),
                ],
              ),
              destinations: widget.isAdmin 
                ? [
                    const NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text("Home")),
                    const NavigationRailDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: Text("Assistant")),
                    NavigationRailDestination(
                      icon: Stack(children: [const Icon(Icons.forum_outlined), if (_hasNewForumMessage) Positioned(right: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)))]), 
                      selectedIcon: const Icon(Icons.forum_rounded), 
                      label: const Text("Forum")
                    ),
                    const NavigationRailDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book_rounded), label: Text("Courses")),
                    const NavigationRailDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings_rounded), label: Text("Admin")),
                  ]
                : widget.isDev 
                  ? [
                    const NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text("Home")),
                    const NavigationRailDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings_rounded), label: Text("Dev Panel")),
                  ]
                  : [
                    const NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: Text("Home")),
                    const NavigationRailDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: Text("Assistant")),
                    const NavigationRailDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book_rounded), label: Text("Courses")),
                    const NavigationRailDestination(icon: Icon(Icons.bookmark_border_rounded), selectedIcon: Icon(Icons.bookmark_rounded), label: Text("Saved")),
                    NavigationRailDestination(
                      icon: Stack(children: [const Icon(Icons.forum_outlined), if (_hasNewForumMessage) Positioned(right: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)))]), 
                      selectedIcon: const Icon(Icons.forum_rounded),
                      label: const Text("Forum")
                    ),
                  ],
            ),
          if (isDesktop) VerticalDivider(thickness: 1, width: 1, color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
          Expanded(child: mainContent),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
        unselectedItemColor: isDark ? AcademicTheme.darkTextSecondary : Colors.grey,
        backgroundColor: isDark ? AcademicTheme.darkCard : Colors.white,
        type: BottomNavigationBarType.fixed,
        onTap: _onNavBarTap,
        items: widget.isAdmin 
          ? [
              _buildNavBarItem(Icons.home, Icons.home_outlined, "Home", 0),
              _buildNavBarItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Assistant", 1),
              _buildNavBarItem(Icons.forum, Icons.forum_outlined, "Forum", 2, showBadge: _hasNewForumMessage),
              _buildNavBarItem(Icons.book, Icons.book_outlined, "Courses", 3),
              _buildNavBarItem(Icons.admin_panel_settings, Icons.admin_panel_settings_outlined, "Admin", 4),
            ]
          : widget.isDev 
            ? [
              _buildNavBarItem(Icons.home, Icons.home_outlined, "Home", 0),
              _buildNavBarItem(Icons.admin_panel_settings, Icons.admin_panel_settings_outlined, "Dev", 1),
            ]
            : [
              _buildNavBarItem(Icons.home, Icons.home_outlined, "Home", 0),
              _buildNavBarItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Assistant", 1),
              _buildNavBarItem(Icons.book, Icons.book_outlined, "Courses", 2),
              _buildNavBarItem(Icons.bookmark, Icons.bookmark_border, "Saved", 3),
              _buildNavBarItem(Icons.forum, Icons.forum_outlined, "Forum", 4, showBadge: _hasNewForumMessage),
            ],
      ),
    );
  }

  void _onNavBarTap(int index) async {
    setState(() => currentIndex = index);
    if (index == 0) return; // Already on home

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    
    if (widget.isAdmin) {
      switch (index) {
        case 1: Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantPage())); break;
        case 2: 
          setState(() => _hasNewForumMessage = false);
          Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityForumPage(userName: widget.userName, userId: _currentUserId))); 
          break;
        case 3: Navigator.push(context, MaterialPageRoute(builder: (_) => AllCoursesPage(isAdmin: widget.isAdmin))); break;
        case 4: _navigateTo(const AdminProfilePage()); break;
      }
    } else if (widget.isDev) {
      switch (index) {
        case 1: _navigateTo(const AdminProfilePage()); break;
      }
    } else {
      switch (index) {
        case 1: Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantPage())); break;
        case 2: Navigator.push(context, MaterialPageRoute(builder: (_) => AllCoursesPage(isAdmin: widget.isAdmin))); break;
        case 3: Navigator.push(context, MaterialPageRoute(builder: (_) => const BookmarksPage())); break;
        case 4: 
          setState(() => _hasNewForumMessage = false);
          _navigateTo(CommunityForumPage(userName: widget.userName, userId: _currentUserId));
          break;
      }
    }
    
    if (mounted) setState(() => currentIndex = 0);
  }

  BottomNavigationBarItem _buildNavBarItem(IconData activeIcon, IconData inactiveIcon, String label, int index, {bool showBadge = false}) {
    final bool isSelected = currentIndex == index;
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          AnimatedScale(
            scale: isSelected ? 1.2 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Icon(isSelected ? activeIcon : inactiveIcon),
          ),
          if (showBadge)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
              ),
            ),
        ],
      ),
      label: label,
    );
  }
}

class _QuickAccess extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _QuickAccess({required this.icon, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AcademicTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 5)],
            ),
            child: Icon(icon, color: color ?? AcademicTheme.primary),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 65,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List pdfs;
  final List videos;
  final List pastQuestions;
  final VoidCallback? onReturn;
  final bool isAdmin;
  final int credits;

  const _CourseCard({required this.title, required this.subtitle, this.icon = Icons.book, this.pdfs = const [], this.videos = const [], this.pastQuestions = const [], this.onReturn, this.isAdmin = false, this.credits = 3});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PDFPage(courseTitle: title, pdfs: pdfs, videos: videos, pastQuestions: pastQuestions, isAdmin: isAdmin))).then((_) => onReturn?.call());
      },
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.1),
              child: Icon(icon, color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary, size: 20),
            ),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.bookmark_outline_rounded, size: 12, color: AcademicTheme.accent),
                const SizedBox(width: 4),
                Text(
                  "$credits Credit Unit${credits > 1 ? 's' : ''}",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PDFPage(courseTitle: title, pdfs: pdfs, videos: videos, pastQuestions: pastQuestions, isAdmin: isAdmin))).then((_) => onReturn?.call());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.1),
                  foregroundColor: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                  elevation: 0,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("View", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// NEXT CLASS LOGIC
String getNextClass() {
  final now = DateTime.now();

  const days = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday"
  ];

  if (now.weekday > 5) {
    return "It's Weekend Baby 🎉";
  }

  final today = days[now.weekday - 1];

  final todaySchedule = timetable[today] ?? [];

  if (todaySchedule.isEmpty) {
    return "No more classes today";
  }

  for (var item in todaySchedule) {
    final time = item["time"] ?? "0-0";
    final startHour =
        int.tryParse(time.split("-")[0].split(":")[0]) ?? 0;

    if (startHour > now.hour) {
      return "${item["course"]} in ${startHour - now.hour}hrs";
    }
  }

  return "Done for today 🎉";
}

String _getGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return "Good Morning!";
  if (hour < 17) return "Good Afternoon!";
  return "Good Evening!";
}