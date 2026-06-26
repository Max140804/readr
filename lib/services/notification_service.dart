import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../data/timetable_data.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../main.dart';
import 'update_service.dart';

class NotificationHistoryItem {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  bool isRead;

  NotificationHistoryItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'timestamp': timestamp.toIso8601String(),
    'isRead': isRead,
  };

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) => NotificationHistoryItem(
    id: json['id'],
    title: json['title'],
    body: json['body'],
    timestamp: DateTime.parse(json['timestamp']),
    isRead: json['isRead'] ?? false,
  );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    try {
      tz_data.initializeTimeZones();
      
      // Non-blocking timezone setup
      _setupTimezone();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      await _notificationsPlugin.initialize(
        settings: InitializationSettings(android: initializationSettingsAndroid),
        onDidReceiveNotificationResponse: (details) async {
          debugPrint("Notification clicked: ${details.payload}");
          if (details.payload == 'lock_in_alarm') {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('trigger_lock_in', true);
          } else if (details.payload != null && details.payload!.startsWith('update|')) {
            final parts = details.payload!.split('|');
            if (parts.length >= 3) {
              final url = parts[1];
              final version = parts[2];
              
              // We'll use a delayed check to ensure the navigator is ready
              Future.delayed(const Duration(seconds: 1), () {
                final context = navigatorKey.currentContext;
                if (context != null) {
                  UpdateService.startUpdateFlow(context, url, version);
                }
              });
            }
          }
        },
      );

      await createNotificationChannels();

      // Handle killed state launch (Notification or Native Alarm)
      final prefs = await SharedPreferences.getInstance();
      
      // 1. Check if launched from Notification
      final NotificationAppLaunchDetails? launchDetails = 
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        if (launchDetails.notificationResponse?.payload == 'lock_in_alarm') {
          await prefs.setBool('trigger_lock_in', true);
        }
      }

      // 2. Check if launched from Native Alarm (even without notification click)
      const platform = MethodChannel('com.example.readr/dnd');
      try {
        final bool wasNativeAlarm = await platform.invokeMethod('wasStartedByAlarm');
        if (wasNativeAlarm) {
          await prefs.setBool('trigger_lock_in', true);
        }
      } catch (e) {
        debugPrint("Error checking native alarm launch: $e");
      }
    } catch (e) {
      debugPrint("Notification Service Init Error: $e");
    }
  }

  Future<void> _setupTimezone() async {
    try {
      final dynamic zone = await FlutterTimezone.getLocalTimezone();
      final String zoneName = zone is String ? zone : (zone as dynamic).name;
      tz.setLocalLocation(tz.getLocation(zoneName));
      debugPrint("Timezone initialized: $zoneName");
    } catch (e) {
      debugPrint("Timezone detection error, falling back to Africa/Lagos: $e");
      tz.setLocalLocation(tz.getLocation('Africa/Lagos'));
    }
  }

  Future<void> requestPermissions() async {
    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      try {
        await androidImplementation.requestExactAlarmsPermission();
      } catch (e) {
        debugPrint("Exact alarm permission request failed: $e");
      }
      await createNotificationChannels();
    }
  }

  /// Creates channels. Can be called multiple times safely.
  Future<void> createNotificationChannels() async {
    final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) return;

    // 1. Forum Sync Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'forum_sync_channel',
        'Readr Sync',
        description: 'Background synchronization for forum messages',
        importance: Importance.low,
      ),
    );

    // 2. Urgent Alerts Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'urgent_alert_channel',
        'Urgent Alerts',
        description: 'High priority notifications for new forum messages',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    // 3. Study Alarm Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'lock_in_channel_v7',
        'Study Alarms',
        description: 'Triggers Lock-in mode automatically',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    // 4. Timetable Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'timetable_channel_v7',
        'Class Reminders',
        importance: Importance.max,
      ),
    );

    // 5. Assignments Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'assignments_channel',
        'Assignments',
        description: 'Notifications for new assignments and deadlines',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    // 6. Updates Channel
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'updates_channel',
        'App Updates',
        description: 'Notifications for new app versions and features',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  Future<void> saveToHistory(String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('notification_history') ?? '[]';
    final List<dynamic> historyData = jsonDecode(historyJson);
    
    final newItem = NotificationHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      timestamp: DateTime.now(),
    );

    historyData.insert(0, newItem.toJson());
    // Keep only last 50 notifications
    if (historyData.length > 50) historyData.removeLast();
    
    await prefs.setString('notification_history', jsonEncode(historyData));
  }

  Future<List<NotificationHistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('notification_history') ?? '[]';
    final List<dynamic> historyData = jsonDecode(historyJson);
    return historyData.map((e) => NotificationHistoryItem.fromJson(e)).toList();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_history');
  }

  Future<void> markAllAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    for (var item in history) {
      item.isRead = true;
    }
    await prefs.setString('notification_history', jsonEncode(history.map((e) => e.toJson()).toList()));
  }

  Future<void> showNotificationNow(String title, String body, {bool saveToLog = true, String? payload, String channelId = 'urgent_alert_channel'}) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      channelId,
      channelId == 'urgent_alert_channel' ? 'Urgent Alerts' : (channelId == 'updates_channel' ? 'App Updates' : 'General'),
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: true,
      enableVibration: true,
      color: const Color(0xFF1A237E), // Scholr Navy Blue
      icon: '@mipmap/ic_launcher',
    );
    
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
    
    if (saveToLog) {
      await saveToHistory(title, body);
    }
  }

  Future<void> scheduleTimetableNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final lastScheduled = prefs.getString('last_timetable_schedule') ?? '';
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    // Only reschedule if the day has changed to avoid redundant work
    if (lastScheduled == today) {
      debugPrint("Timetable already scheduled for today.");
      // Even if timetable is scheduled, ensure recurring alarms are healthy
      await _ensureRecurringAlarmsAreScheduled();
      return;
    }

    final daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
    try {
      await _notificationsPlugin.cancelAll();
      debugPrint("Scheduling timetable notifications...");

      for (int dayIdx = 0; dayIdx < daysOfWeek.length; dayIdx++) {
        final String day = daysOfWeek[dayIdx];
        final List<Map<String, String>> classes = timetable[day] ?? [];
        
        for (int classIdx = 0; classIdx < classes.length; classIdx++) {
          final classInfo = classes[classIdx];
          final String course = classInfo['course']!;
          final String timeRange = classInfo['time']!;
          
          try {
            // Parse start time (e.g., "9:00 AM")
            final String startTimeStr = timeRange.split('-')[0].trim();
            final parts = startTimeStr.split(' ');
            final timeParts = parts[0].split(':');
            int hour = int.parse(timeParts[0]);
            int minute = int.parse(timeParts[1]);
            final String amPm = parts[1].toUpperCase();

            if (amPm == 'PM' && hour != 12) hour += 12;
            if (amPm == 'AM' && hour == 12) hour = 0;

            final int idBase = (dayIdx + 1) * 1000 + (classIdx * 10);

            // Get the next occurrence of the class
            final classTime = _nextInstanceOfDayAndTime(_getDayOfWeek(day), hour, minute);

            // 1 Hour Before Reminder
            final reminderTime = classTime.subtract(const Duration(hours: 1));

            await _scheduleClassAlert(
              id: idBase,
              title: "Upcoming Class: $course",
              body: "$course class starts in 1 hour at $startTimeStr!",
              scheduledDate: reminderTime,
            );

            // Commencement Notification
            await _scheduleClassAlert(
              id: idBase + 1,
              title: "Class Started: $course",
              body: "Time for $course ($startTimeStr). You might want to pay attention! or make your way to class if you arent there already.",
              scheduledDate: classTime,
              isOngoing: true,
            );
            
            debugPrint("Scheduled $course: Reminder at ${reminderTime.hour}:${reminderTime.minute}, Start at ${classTime.hour}:${classTime.minute}");
          } catch (e) {
            debugPrint("Error parsing/scheduling $course on $day: $e");
          }
        }
      }
      await prefs.setString('last_timetable_schedule', today);
      debugPrint("Timetable notifications scheduled successfully.");
      
      // Ensure recurring study alarms are also scheduled
      await _ensureRecurringAlarmsAreScheduled();
    } catch (e) {
      debugPrint("Critical error scheduling notifications: $e");
    }
  }

  Future<void> _scheduleClassAlert({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    bool isOngoing = false,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'timetable_channel_v7',
          'Class Reminders',
          importance: Importance.max,
          priority: Priority.high,
          ongoing: isOngoing,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> scheduleCustomEvent(String title, String body, DateTime time) async {
    final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(time, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'events_channel',
          'Custom Events',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> scheduleLockInAlarm(String title, String body, DateTime scheduledTime) async {
    const int id = 888; // Unique ID for Study Alarm
    const platform = MethodChannel('com.example.readr/dnd');

    // 1. Schedule the notification (with fullScreenIntent)
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'lock_in_channel_v7',
          'Study Alarms',
          channelDescription: 'Triggers Lock-in mode automatically',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          visibility: NotificationVisibility.public,
          additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
          audioAttributesUsage: AudioAttributesUsage.alarm,
          ongoing: true, // Make it harder to dismiss
          autoCancel: false,
        ),
      ),
      payload: 'lock_in_alarm',
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    // 2. Schedule the native alarm to wake up and bring app to front
    try {
      await platform.invokeMethod('scheduleNativeAlarm', {
        'timeInMillis': scheduledTime.millisecondsSinceEpoch,
        'id': id,
      });
    } catch (e) {
      debugPrint("Native alarm scheduling failed: $e");
    }
  }

  Future<void> _ensureRecurringAlarmsAreScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getStringList('study_alarm_days') ?? [];
    final hour = prefs.getInt('study_alarm_hour');
    final minute = prefs.getInt('study_alarm_minute');

    if (days.isNotEmpty && hour != null && minute != null) {
      debugPrint("Restoring recurring study alarms from background...");
      await scheduleRecurringLockInAlarm(
        "Focus Session Starting! 📚",
        "Lock-in, twin! time to unleash your potential!",
        TimeOfDay(hour: hour, minute: minute),
        days.map(int.parse).toList(),
      );
    }
  }

  Future<void> scheduleRecurringLockInAlarm(String title, String body, TimeOfDay time, List<int> days) async {
    const platform = MethodChannel('com.example.readr/dnd');
    
    // Cancel existing first
    await cancelLockInAlarm();

    for (final day in days) {
      final int id = 888 + day; // Unique ID per day
      final scheduledDate = _nextInstanceOfDayAndTime(day, time.hour, time.minute);

      await _notificationsPlugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'lock_in_channel_v7',
            'Study Alarms',
            channelDescription: 'Triggers Lock-in mode automatically',
            importance: Importance.max,
            priority: Priority.max,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            additionalFlags: Int32List.fromList([4]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            ongoing: true,
            autoCancel: false,
          ),
        ),
        payload: 'lock_in_alarm',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );

      // Schedule native alarm for each day to ensure wake up
      try {
        await platform.invokeMethod('scheduleNativeAlarm', {
          'timeInMillis': scheduledDate.millisecondsSinceEpoch,
          'id': id,
        });
      } catch (e) {
        debugPrint("Native alarm scheduling failed for day $day: $e");
      }
    }
  }

  Future<void> cancelLockInAlarm() async {
    const platform = MethodChannel('com.example.readr/dnd');
    await _notificationsPlugin.cancel(id: 888);
    try {
      await platform.invokeMethod('cancelNativeAlarm', {'id': 888});
    } catch (e) {
      debugPrint("Native alarm cancellation failed: $e");
    }

    // Cancel recurring ones too
    for (int i = 1; i <= 7; i++) {
      final int id = 888 + i;
      await _notificationsPlugin.cancel(id: id);
      try {
        await platform.invokeMethod('cancelNativeAlarm', {'id': id});
      } catch (e) {
        debugPrint("Native alarm cancellation failed for id $id: $e");
      }
    }
  }

  Future<void> scheduleAssignmentReminders(String assignmentId, String course, String title, DateTime dueDate) async {
    final now = DateTime.now();
    if (dueDate.isBefore(now)) return;

    final reminders = [12, 6, 3, 1]; // Hours before deadline

    for (int hours in reminders) {
      final scheduledTime = dueDate.subtract(Duration(hours: hours));
      if (scheduledTime.isAfter(now)) {
        // Generate a unique ID for this specific reminder
        // Using hash of assignmentId and hours to keep it consistent
        final int notificationId = (assignmentId.hashCode + hours).remainder(100000).abs();
        
        await _notificationsPlugin.zonedSchedule(
          id: notificationId,
          title: "Assignment Deadline: $course",
          body: "$title is due in $hours hour${hours > 1 ? 's' : ''}!",
          scheduledDate: tz.TZDateTime.from(scheduledTime, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'assignments_channel',
              'Assignments',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> cancelAssignmentReminders(String assignmentId) async {
    final reminders = [12, 6, 3, 1];
    for (int hours in reminders) {
      final int notificationId = (assignmentId.hashCode + hours).remainder(100000).abs();
      await _notificationsPlugin.cancel(id: notificationId);
    }
  }

  int _getDayOfWeek(String day) {
    switch (day) {
      case "Monday": return DateTime.monday;
      case "Tuesday": return DateTime.tuesday;
      case "Wednesday": return DateTime.wednesday;
      case "Thursday": return DateTime.thursday;
      case "Friday": return DateTime.friday;
      default: return DateTime.monday;
    }
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(int day, int hour, int minute) {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, hour, minute);
    
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    
    return tz.TZDateTime.from(scheduledDate, tz.local);
  }

}
