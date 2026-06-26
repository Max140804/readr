import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data/timetable_data.dart';
import 'services/notification_service.dart';
import 'dart:io' show Platform;

class StudyAlarmPage extends StatefulWidget {
  const StudyAlarmPage({super.key});

  @override
  State<StudyAlarmPage> createState() => _StudyAlarmPageState();
}

class _StudyAlarmPageState extends State<StudyAlarmPage> with WidgetsBindingObserver, TickerProviderStateMixin {
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _isScheduled = false;
  DateTime? _scheduledDateTime;
  List<int> _selectedDays = []; // 1-7 (Mon-Sun)
  bool _hasOverlayPermission = false;
  bool _hasDndPermission = false;
  bool _hasNotificationPermission = false;
  bool _hasExactAlarmPermission = false;

  final List<String> _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _checkPermissions();
    _loadScheduledAlarm();
  }

  Future<void> _loadScheduledAlarm() async {
    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getStringList('study_alarm_days') ?? [];
    final hour = prefs.getInt('study_alarm_hour');
    final minute = prefs.getInt('study_alarm_minute');
    
    setState(() {
      _selectedDays = days.map(int.parse).toList();
      if (hour != null && minute != null) {
        _selectedTime = TimeOfDay(hour: hour, minute: minute);
      }
      if (_selectedDays.isNotEmpty) {
        _isScheduled = true;
      }
    });

    final scheduledStr = prefs.getString('scheduled_study_alarm');
    if (scheduledStr != null) {
      final scheduledDate = DateTime.parse(scheduledStr);
      if (scheduledDate.isAfter(DateTime.now())) {
        setState(() {
          _isScheduled = true;
          _scheduledDateTime = scheduledDate;
          _selectedTime = TimeOfDay.fromDateTime(scheduledDate);
        });
      } else if (_selectedDays.isEmpty) {
        await prefs.remove('scheduled_study_alarm');
        setState(() => _isScheduled = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) {
      setState(() {
        _hasOverlayPermission = true;
        _hasDndPermission = true;
        _hasNotificationPermission = true;
        _hasExactAlarmPermission = true;
      });
      return;
    }
    const platform = MethodChannel('com.example.readr/dnd');
    try {
      final bool overlayGranted = await platform.invokeMethod('checkOverlayPermission');
      final bool dndGranted = await platform.invokeMethod('isNotificationPolicyAccessGranted');
      
      // Check notification permission for Android 13+
      bool notificationGranted = await Permission.notification.isGranted;
      
      // Check exact alarm permission for Android 12+
      bool exactAlarmGranted = true;
      if (await Permission.scheduleExactAlarm.isDenied) {
        exactAlarmGranted = false;
      }

      setState(() {
        _hasOverlayPermission = overlayGranted;
        _hasDndPermission = dndGranted;
        _hasNotificationPermission = notificationGranted;
        _hasExactAlarmPermission = exactAlarmGranted;
      });
    } catch (e) {
      debugPrint("Error checking permissions: $e");
    }
  }

  Future<void> _requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    const platform = MethodChannel('com.example.readr/dnd');
    await platform.invokeMethod('requestOverlayPermission');
  }

  Future<void> _requestDndPermission() async {
    if (!Platform.isAndroid) return;
    const platform = MethodChannel('com.example.readr/dnd');
    await platform.invokeMethod('gotoPolicySettings');
  }

  Future<void> _selectTime(BuildContext context) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryColor = isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary;

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              dialBackgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[200],
              dialHandColor: primaryColor,
              hourMinuteTextColor: isDark ? Colors.white : AcademicTheme.primary,
              hourMinuteColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[100],
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: AcademicTheme.primary,
              primary: AcademicTheme.primary,
              brightness: isDark ? Brightness.dark : Brightness.light,
              surface: isDark ? AcademicTheme.darkCard : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      HapticFeedback.selectionClick();
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _scheduleAlarm() async {
    // Ensure notification permission is granted
    if (Platform.isAndroid && !_hasNotificationPermission) {
      final status = await Permission.notification.request();
      if (!status.isGranted) {
        _showModernSnackBar("Notification permission is required", Icons.warning, Colors.orange);
        return;
      }
      setState(() => _hasNotificationPermission = true);
    }

    final now = DateTime.now();
    
    if (_selectedDays.isEmpty) {
      // Single shot alarm (tomorrow or today)
      var scheduledDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      if (scheduledDateTime.isBefore(now)) {
        scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
      }

      await NotificationService().scheduleLockInAlarm(
        "Focus Session Starting! 📚",
        "Lock-in, twin! time to unleash your potential!",
        scheduledDateTime,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('scheduled_study_alarm', scheduledDateTime.toIso8601String());
      await prefs.setStringList('study_alarm_days', []);

      setState(() {
        _isScheduled = true;
        _scheduledDateTime = scheduledDateTime;
      });
      
      _showModernSnackBar("Alarm set for ${DateFormat.jm().format(scheduledDateTime)}", Icons.alarm_on, AcademicTheme.primary);
    } else {
      // Recurring alarm
      await NotificationService().scheduleRecurringLockInAlarm(
        "Focus Session Starting! 📚",
        "Lock-in, twin! time to unleash your potential!",
        _selectedTime,
        _selectedDays,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('study_alarm_days', _selectedDays.map((e) => e.toString()).toList());
      await prefs.setInt('study_alarm_hour', _selectedTime.hour);
      await prefs.setInt('study_alarm_minute', _selectedTime.minute);
      await prefs.remove('scheduled_study_alarm');

      setState(() {
        _isScheduled = true;
        _scheduledDateTime = null; // It's recurring
      });
      
      _showModernSnackBar("Recurring alarm set", Icons.alarm_on, AcademicTheme.primary);
    }

    HapticFeedback.mediumImpact();
  }

  void _cancelAlarm() async {
    HapticFeedback.lightImpact();
    await NotificationService().cancelLockInAlarm();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('scheduled_study_alarm');
    await prefs.remove('study_alarm_days');
    await prefs.remove('study_alarm_hour');
    await prefs.remove('study_alarm_minute');
    setState(() {
      _isScheduled = false;
      _selectedDays = [];
    });
    if (mounted) {
      _showModernSnackBar("Alarm cancelled", Icons.alarm_off, Colors.redAccent);
    }
  }

  void _showModernSnackBar(String message, IconData icon, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color.withValues(alpha: 0.9),
        margin: const EdgeInsets.all(15),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
  }

  String _getTimeRemaining() {
    DateTime nextOccurrence;
    bool isRecurring = false;

    if (_selectedDays.isNotEmpty) {
      isRecurring = true;
      DateTime soonest = DateTime.now().add(const Duration(days: 8));
      for (final day in _selectedDays) {
        final occurrence = _getDateTimeForNextDay(day, _selectedTime);
        if (occurrence.isBefore(soonest)) soonest = occurrence;
      }
      nextOccurrence = soonest;
    } else if (_scheduledDateTime != null && _scheduledDateTime!.isAfter(DateTime.now())) {
      nextOccurrence = _scheduledDateTime!;
    } else {
      return "";
    }

    final diff = nextOccurrence.difference(DateTime.now());
    if (diff.isNegative) return "Starting...";
    
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;

    List<String> parts = [];
    if (d > 0) parts.add("${d}d");
    if (h > 0) parts.add("${h}h");
    if (m > 0 || (d == 0 && h == 0)) parts.add("${m}m");

    String timeStr = parts.join(" ");
    return isRecurring ? "$timeStr (Recurring)" : timeStr;
  }

  DateTime _getDateTimeForNextDay(int day, TimeOfDay time) {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    return scheduledDate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary;

    return Scaffold(
      backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
      appBar: AppBar(
        backgroundColor: AcademicTheme.primary,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text("Study Alarm", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
            Text("UNLEASH YOUR POTENTIAL", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1.5)),
          ],
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: _buildStatusCard(isDark, primaryColor, key: ValueKey(_isScheduled)),
                  ),
                  const SizedBox(height: 40),
                  const Text("NEXT FOCUS SESSION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.grey)),
                  const SizedBox(height: 16),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: GestureDetector(
                      onTap: () => _selectTime(context),
                      child: Container(
                        width: 220, height: 220,
                        decoration: BoxDecoration(
                          color: isDark ? AcademicTheme.darkCard : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: primaryColor.withValues(alpha: 0.2), blurRadius: 30, spreadRadius: 5),
                          ],
                          border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _selectedTime.format(context).split(' ')[0],
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : AcademicTheme.primary,
                                ),
                              ),
                              Text(
                                _selectedTime.format(context).split(' ')[1],
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text("REPEAT DAYS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildQuickSelectChip("Daily", [1, 2, 3, 4, 5, 6, 7], primaryColor, isDark),
                      _buildQuickSelectChip("Weekdays", [1, 2, 3, 4, 5], primaryColor, isDark),
                      _buildQuickSelectChip("Weekends", [6, 7], primaryColor, isDark),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(7, (index) {
                      final dayNum = index + 1;
                      final isSelected = _selectedDays.contains(dayNum);
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            if (isSelected) {
                              _selectedDays.remove(dayNum);
                            } else {
                              _selectedDays.add(dayNum);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? primaryColor : (isDark ? Colors.white24 : Colors.grey[300]!),
                              width: 1.5,
                            ),
                            boxShadow: isSelected ? [
                              BoxShadow(color: primaryColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))
                            ] : [],
                          ),
                          child: Center(
                            child: Text(
                              _dayLabels[index],
                              style: TextStyle(
                                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 50),
                  if (!_hasOverlayPermission || !_hasDndPermission || !_hasNotificationPermission || !_hasExactAlarmPermission)
                    _buildPermissionWarning(isDark),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      onPressed: _scheduleAlarm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 8,
                        shadowColor: primaryColor.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text("SET ALARM", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ),
                  ),
                  if (_isScheduled) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _cancelAlarm,
                      icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.redAccent),
                      label: const Text("CANCEL SCHEDULED SESSION", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                  const SizedBox(height: 40),
                  _buildTipCard(primaryColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool isDark, Color primaryColor, {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _isScheduled ? primaryColor : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: _isScheduled ? primaryColor.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _isScheduled ? Colors.white.withValues(alpha: 0.24) : primaryColor.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(_isScheduled ? Icons.check_circle_rounded : Icons.timer_off_rounded, color: _isScheduled ? Colors.white : primaryColor, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_isScheduled ? "ALARM ACTIVE" : "NO ALARM SET", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: _isScheduled ? Colors.white.withValues(alpha: 0.8) : Colors.grey)),
                Text(_isScheduled ? "Next session in ${_getTimeRemaining()}" : "Ready when you are", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _isScheduled ? Colors.white : (isDark ? Colors.white : AcademicTheme.primary))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionWarning(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text("PERMISSIONS REQUIRED", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.orange, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          const Text("To lock-in automatically, please enable:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          if (!_hasNotificationPermission) const _PermissionBullet(text: "Push Notifications"),
          if (!_hasExactAlarmPermission) const _PermissionBullet(text: "Exact Alarms"),
          if (!_hasOverlayPermission) const _PermissionBullet(text: "Display over other apps"),
          if (!_hasDndPermission) const _PermissionBullet(text: "Do Not Disturb Access"),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                if (!_hasNotificationPermission) {
                  await Permission.notification.request();
                }
                if (!_hasExactAlarmPermission) {
                  await Permission.scheduleExactAlarm.request();
                }
                if (!_hasOverlayPermission) await _requestOverlayPermission();
                if (!_hasDndPermission) await _requestDndPermission();
                _checkPermissions();
              },
              style: TextButton.styleFrom(backgroundColor: Colors.orange.withValues(alpha: 0.2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text("GRANT ACCESS", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: primaryColor.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: primaryColor.withValues(alpha: 0.1))),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.orange),
          SizedBox(width: 16),
          Expanded(child: Text("Study Alarm will automatically launch the app and enable Do Not Disturb mode at the set time.", style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildQuickSelectChip(String label, List<int> days, Color primaryColor, bool isDark) {
    bool isAllSelected = days.every((d) => _selectedDays.contains(d));
    return ChoiceChip(
      label: Text(label),
      selected: isAllSelected,
      onSelected: (selected) {
        HapticFeedback.selectionClick();
        setState(() {
          if (selected) {
            for (var d in days) {
              if (!_selectedDays.contains(d)) _selectedDays.add(d);
            }
          } else {
            for (var d in days) {
              _selectedDays.remove(d);
            }
          }
          _selectedDays.sort();
        });
      },
      selectedColor: primaryColor.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isAllSelected ? primaryColor : (isDark ? Colors.white70 : Colors.black54),
        fontWeight: isAllSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: isAllSelected ? primaryColor : Colors.transparent),
      showCheckmark: false,
    );
  }
}

class _PermissionBullet extends StatelessWidget {
  final String text;
  const _PermissionBullet({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [const Icon(Icons.circle, size: 6, color: Colors.orange), const SizedBox(width: 8), Text(text, style: const TextStyle(fontSize: 12, color: Colors.orange))]),
    );
  }
}
