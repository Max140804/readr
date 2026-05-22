import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import '../data/timetable_data.dart';
import 'package:flutter/foundation.dart';

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
      tz.initializeTimeZones();
      try {
        final currentTimeZone = await FlutterTimezone.getLocalTimezone();
        final String zoneName = currentTimeZone is String ? currentTimeZone : (currentTimeZone as dynamic).name;
        tz.setLocalLocation(tz.getLocation(zoneName));
      } catch (e) {
        debugPrint("Timezone detection error, falling back to UTC: $e");
        tz.setLocalLocation(tz.getLocation('UTC'));
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      await _notificationsPlugin.initialize(
        settings: InitializationSettings(android: initializationSettingsAndroid),
        onDidReceiveNotificationResponse: (details) {
          debugPrint("Notification clicked: ${details.payload}");
        },
      );

      final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint("Notification Service Init Error: $e");
    }
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

  Future<void> showNotificationNow(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'urgent_alert_channel',
      'Urgent Alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: true,
      enableVibration: true,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _notificationsPlugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
    
    await saveToHistory(title, body);
  }

  Future<void> scheduleTimetableNotifications() async {
    final daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"];
    await _notificationsPlugin.cancelAll();

    for (int dayIdx = 0; dayIdx < daysOfWeek.length; dayIdx++) {
      final String day = daysOfWeek[dayIdx];
      final List<Map<String, String>> classes = timetable[day] ?? [];
      
      for (int classIdx = 0; classIdx < classes.length; classIdx++) {
        final classInfo = classes[classIdx];
        final String course = classInfo['course']!;
        final String timeRange = classInfo['time']!;
        
        try {
          final int startHour = int.parse(timeRange.split('-')[0]);
          final int scheduledHour = (startHour < 8) ? startHour + 12 : startHour;
          final int idBase = (dayIdx + 1) * 100 + (classIdx * 2);

          int reminderHour = scheduledHour - 1;
          if (reminderHour >= 0) {
            await _scheduleClassAlert(
              id: idBase,
              title: "Upcoming Class: $course",
              body: "Your class $course starts in 1 hour!",
              day: day,
              hour: reminderHour,
            );
          }

          await _scheduleClassAlert(
            id: idBase + 1,
            title: "Class Started: $course",
            body: "Time for $course. Tap to open your notes!",
            day: day,
            hour: scheduledHour,
            isOngoing: true,
          );
        } catch (e) {
          debugPrint("Error scheduling $course: $e");
        }
      }
    }
  }

  Future<void> _scheduleClassAlert({
    required int id,
    required String title,
    required String body,
    required String day,
    required int hour,
    bool isOngoing = false,
  }) async {
    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOfDayAndTime(_getDayOfWeek(day), hour),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'timetable_channel_v5',
          'Class Reminders',
          importance: Importance.max,
          priority: Priority.high,
          ongoing: isOngoing,
          styleInformation: const BigTextStyleInformation(''),
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

  tz.TZDateTime _nextInstanceOfDayAndTime(int day, int hour) {
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(hour);
    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  tz.TZDateTime _nextInstanceOfTime(int hour) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, 0);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}
