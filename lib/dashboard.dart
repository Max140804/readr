import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'services/notification_service.dart';
import 'services/update_service.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notifications_page.dart';
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
import 'dues_page.dart';
import 'past_questions_page.dart';

class Dashboard extends StatefulWidget {
  final String userName;
  final bool isAdmin;
  const Dashboard({super.key, this.userName = "Max", this.isAdmin = false});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int currentIndex = 0;
  Timer? _timer;
  String _timerText = "00:00:00";
  String _statusLabel = "Next Class In";
  String _subMessage = "Loading schedule...";
  bool _isLockInEnabled = false;

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
    _startTimer();
    _loadRecentActivity();
    _initNotifications();
    _checkDndStatus();
    
    // Check for updates locally/remotely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
    });
  }

  static const platform = MethodChannel('com.example.readr/dnd');

  Future<void> _checkDndStatus() async {
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
    try {
      final bool? isGranted = await platform.invokeMethod('isNotificationPolicyAccessGranted');
      if (isGranted != true) {
        await platform.invokeMethod('gotoPolicySettings');
        return;
      }

      if (_isLockInEnabled) {
        await platform.invokeMethod('setInterruptionFilter', {"filter": 1}); // ALL
      } else {
        await platform.invokeMethod('setInterruptionFilter', {"filter": 2}); // PRIORITY
      }
      
      final int? newStatus = await platform.invokeMethod('getCurrentInterruptionFilter');
      setState(() {
        _isLockInEnabled = newStatus != null && newStatus != 1;
      });

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

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
          _subMessage = "Get ur tools ready, bub";
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

  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _loadRecentActivity());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                  Text(widget.isAdmin ? "Administrator" : "ECE Student", style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isLoggedIn', false);
                await prefs.remove('userName');
                await prefs.remove('isAdmin');
                
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// TOP BAR
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu, size: 28),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  Row(
                    children: [
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
              Text(widget.userName, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AcademicTheme.primary)),
              const SizedBox(height: 20),

              /// NEXT CLASS CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AcademicTheme.primary, AcademicTheme.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AcademicTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxWidth: 220),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _statusLabel.toUpperCase(),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _timerText,
                              style: const TextStyle(
                                color: Colors.white, 
                                fontSize: 42, 
                                fontWeight: FontWeight.w900, 
                                letterSpacing: 2, 
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(_subMessage, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                      ),
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
                  //Text("Edit", style: TextStyle(color: AcademicTheme.accent)),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickAccess(icon: Icons.payments, label: "Dues", onTap: () => _navigateTo(const DuesPage())),
                  _QuickAccess(icon: Icons.calendar_month, label: "Timetable", onTap: () => _navigateTo(const TimetablePage())),
                  _QuickAccess(icon: Icons.support_agent, label: "Assistant", onTap: () => _navigateTo(const AssistantPage())),
                  _QuickAccess(icon: Icons.note_alt_outlined, label: "PQs", onTap: () => _navigateTo(const PastQuestionsPage(courseName: "General", questions: []))),
                  _QuickAccess(
                    icon: _isLockInEnabled ? Icons.lock : Icons.lock_open, 
                    label: "Lock-in", 
                    onTap: _toggleLockInMode,
                    color: _isLockInEnabled ? AcademicTheme.accent : null,
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
                    onTap: () => _navigateTo(const AllCoursesPage()),
                    child: const Text("See All", style: TextStyle(color: AcademicTheme.accent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              /// COURSE GRID
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                children: [
                  _CourseCard(
                    title: "ECE 527",
                    subtitle: "Solid State Electronics",
                    icon: Icons.memory,
                    pdfs: const [{"title": "Semiconductor Fabrication Process", "path": "assets/pdfs/ECE 527 LECTURE 2.docx"}],
                    videos: const [{"title": "Semiconductor Introduction", "thumbnail": "https://img.youtube.com/vi/tiP6fgySxPU/0.jpg", "url": "https://youtu.be/tiP6fgySxPU?si=iZOryxdxMCxHH9hO"}],
                    onReturn: _loadRecentActivity,
                  ),
                  _CourseCard(
                    title: "ECE 537",
                    subtitle: "Digital Signal Processing",
                    icon: Icons.waves,
                    pdfs: const [{"title": "Introduction to DSP", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"}],
                    videos: const [{"title": "DSP Introduction", "thumbnail": "https://img.youtube.com/vi/iCaDt9Esdv4/0.jpg", "url": "https://youtu.be/iCaDt9Esdv4?si=W7gAhEzvfHcKjhl4"}],
                    onReturn: _loadRecentActivity,
                  ),
                  _CourseCard(
                    title: "ECE 541",
                    subtitle: "Artificial Intelligence",
                    icon: Icons.psychology,
                    onReturn: _loadRecentActivity,
                  ),
                  _CourseCard(
                    title: "ECE 539",
                    subtitle: "Communication Systems",
                    icon: Icons.settings_input_antenna,
                    onReturn: _loadRecentActivity,
                  ),
                ],
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
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: AcademicTheme.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) async {
          setState(() => currentIndex = index);
          await Future.delayed(const Duration(milliseconds: 150));
          if (!mounted) return;
          
          if (widget.isAdmin) {
            switch (index) {
              case 1: Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantPage())); break;
              case 2: Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityForumPage(userName: widget.userName, userId: widget.isAdmin ? "admin" : widget.userName))); break;
              case 3: Navigator.push(context, MaterialPageRoute(builder: (_) => const AllCoursesPage())); break;
              case 4: _navigateTo(const AdminProfilePage()); break;
            }
          } else {
            switch (index) {
              case 1: Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantPage())); break;
              case 2: Navigator.push(context, MaterialPageRoute(builder: (_) => const AllCoursesPage())); break;
              case 3: Navigator.push(context, MaterialPageRoute(builder: (_) => const BookmarksPage())); break;
              case 4: _navigateTo(CommunityForumPage(userName: widget.userName, userId: widget.userName)); break;
            }
          }
          
          if (mounted) setState(() => currentIndex = 0);
        },
        items: widget.isAdmin 
          ? [
              _buildNavBarItem(Icons.home, Icons.home_outlined, "Home", 0),
              _buildNavBarItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Assistant", 1),
              _buildNavBarItem(Icons.forum, Icons.forum_outlined, "Forum", 2),
              _buildNavBarItem(Icons.book, Icons.book_outlined, "Courses", 3),
              _buildNavBarItem(Icons.admin_panel_settings, Icons.admin_panel_settings_outlined, "Admin", 4),
            ]
          : [
              _buildNavBarItem(Icons.home, Icons.home_outlined, "Home", 0),
              _buildNavBarItem(Icons.chat_bubble, Icons.chat_bubble_outline, "Assistant", 1),
              _buildNavBarItem(Icons.book, Icons.book_outlined, "Courses", 2),
              _buildNavBarItem(Icons.bookmark, Icons.bookmark_border, "Saved", 3),
              _buildNavBarItem(Icons.forum, Icons.forum_outlined, "Forum", 4),
            ],
      ),
    );
  }

  BottomNavigationBarItem _buildNavBarItem(IconData activeIcon, IconData inactiveIcon, String label, int index) {
    final bool isSelected = currentIndex == index;
    return BottomNavigationBarItem(
      icon: AnimatedScale(
        scale: isSelected ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Icon(isSelected ? activeIcon : inactiveIcon),
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
  final VoidCallback? onReturn;

  const _CourseCard({required this.title, required this.subtitle, this.icon = Icons.book, this.pdfs = const [], this.videos = const [], this.onReturn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PDFPage(courseTitle: title, pdfs: pdfs, videos: videos))).then((_) => onReturn?.call());
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
                  "3 Credit Units",
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
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PDFPage(courseTitle: title, pdfs: pdfs, videos: videos))).then((_) => onReturn?.call());
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