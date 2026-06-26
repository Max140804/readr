import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'notification_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'forum_sync_channel',
      initialNotificationTitle: 'Readr Sync Active',
      initialNotificationContent: 'Monitoring forum messages...',
      foregroundServiceNotificationId: 999,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // WRAP EVERYTHING IN A DELAYED TRY-CATCH
  // This prevents the background service from crashing the main app process startup
  Future.delayed(const Duration(seconds: 2), () async {
    try {
      try {
        await dotenv.load(fileName: ".env");
      } catch (_) {}

      final url = dotenv.env['SUPABASE_URL'] ?? 'https://hcqaseovlciadogewnsw.supabase.co';
      final key = dotenv.env['SUPABASE_ANON_KEY'] ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhjcWFzZW92bGNpYWRvZ2V3bnN3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk3MDczMjYsImV4cCI6MjA5NTI4MzMyNn0.HUeREBkAYeZYyv9ekq5a0kVuhpAgFTJJzydzau8Zrdk';

      await Supabase.initialize(url: url, anonKey: key);
      
      final prefs = await SharedPreferences.getInstance();
      final notificationService = NotificationService();
      await notificationService.init();

      // Ensure timetable and repeated study alarms are scheduled even if app isn't opened
      await notificationService.scheduleTimetableNotifications();

      final supabase = Supabase.instance.client;
      bool isForumOpen = false;

      service.on('setForumOpen').listen((event) {
        if (event != null) {
          isForumOpen = event['open'] ?? false;
        }
      });

      // Real-time listener
      supabase
          .from('forum_messages')
          .stream(primaryKey: ['id'])
          .order('timestamp', ascending: true)
          .listen((docs) async {
        
        if (isForumOpen) return;

        await prefs.reload();
        final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
        if (!isLoggedIn) return;

        final currentUserId = prefs.getString('userId');
        if (currentUserId == null || docs.isEmpty) return;

        final lastSeenKey = 'last_seen_forum_$currentUserId';
        final lastNotifiedKey = 'last_notified_msg_id_$currentUserId';
        
        final lastSeen = prefs.getInt(lastSeenKey) ?? 0;
        final lastNotifiedId = prefs.getString(lastNotifiedKey);

        int lastNotifiedIndex = -1;
        if (lastNotifiedId != null) {
          lastNotifiedIndex = docs.indexWhere((m) => m['id'].toString() == lastNotifiedId);
        }

        final newMessages = docs.sublist(lastNotifiedIndex + 1).where((m) {
          final stamp = m['timestamp'];
          if (stamp == null) return false;
          final msgTime = DateTime.parse(stamp).millisecondsSinceEpoch;
          return m['uid']?.toString() != currentUserId && msgTime > lastSeen;
        }).toList();

        if (newMessages.isNotEmpty) {
          final lastMsg = newMessages.last;
          await prefs.setString(lastNotifiedKey, lastMsg['id'].toString());
          
          notificationService.showNotificationNow(
            lastMsg['sender'] ?? "Scholr",
            lastMsg['text'] ?? "Sent an image 🖼️",
            saveToLog: true,
          );
        }
      });

      // Material/Assignment Listener (Unified)
      supabase
          .from('course_materials')
          .stream(primaryKey: ['id'])
          .listen((docs) async {
        if (docs.isEmpty) return;
        
        await prefs.reload();
        if (!(prefs.getBool('isLoggedIn') ?? false)) return;

        final completedAssignments = prefs.getStringList('completed_assignments') ?? [];

        for (var doc in docs) {
          if (doc['type'] != 'Assignment') continue;

          final String id = doc['id'].toString();
          final String fileName = doc['file_name'] ?? "";
          final bool isText = fileName.startsWith("TEXT_ASSIGNMENT");
          
          final String course = doc['course'] ?? "Assignment";
          final String questions = isText ? doc['url'] : (doc['title'] ?? "New Document Assignment");
          
          DateTime dueDate;
          try {
            if (isText && fileName.contains("|DUE:")) {
              dueDate = DateTime.parse(fileName.split("|DUE:").last);
            } else {
              // Default for document assignments if no date found
              dueDate = DateTime.now().add(const Duration(days: 7));
            }
          } catch (_) {
            dueDate = DateTime.now().add(const Duration(days: 7));
          }

          final String notifiedKey = 'notified_assignment_$id';
          if (!(prefs.getBool(notifiedKey) ?? false) && !completedAssignments.contains(id)) {
            await notificationService.showNotificationNow(
              "New Assignment: $course",
              questions.length > 100 ? questions.substring(0, 100) + "..." : questions,
              saveToLog: true,
              channelId: 'assignments_channel',
            );
            await notificationService.scheduleAssignmentReminders(id, course, questions, dueDate);
            await prefs.setBool(notifiedKey, true);
          }
        }
      });

      // Announcements Listener
      supabase
          .from('announcements')
          .stream(primaryKey: ['id'])
          .listen((docs) async {
        if (docs.isEmpty) return;

        await prefs.reload();
        if (!(prefs.getBool('isLoggedIn') ?? false)) return;

        for (var doc in docs) {
          final String id = doc['id'].toString();
          final String notifiedKey = 'notified_announcement_$id';
          
          if (!(prefs.getBool(notifiedKey) ?? false)) {
            await notificationService.showNotificationNow(
              doc['title'] ?? "New Announcement",
              doc['body'] ?? "Tap to read more.",
              saveToLog: true,
              channelId: 'urgent_alert_channel',
            );
            await prefs.setBool(notifiedKey, true);
          }
        }
      });

      // App Updates Listener (Essential for killed state)
      supabase
          .from('app_updates')
          .stream(primaryKey: ['id'])
          .order('id', ascending: false)
          .limit(1)
          .listen((docs) async {
        if (docs.isEmpty) return;
        
        await prefs.reload();
        if (!(prefs.getBool('isLoggedIn') ?? false)) return;

        final latest = docs.first;
        final String id = latest['id'].toString();
        final String notifiedKey = 'notified_update_$id';

        if (!(prefs.getBool(notifiedKey) ?? false)) {
          notificationService.showNotificationNow(
            "New Update Available! 🚀",
            "Version ${latest['version']} is ready. Tap to install now.",
            payload: "update|${latest['url']}|${latest['version']}",
            channelId: 'updates_channel',
          );
          await prefs.setBool(notifiedKey, true);
        }
      });

      // Periodic Fallback (Every 15 minutes)
      // This ensures that even if streams fail, we catch new items
      Timer.periodic(const Duration(minutes: 15), (timer) async {
        try {
          await prefs.reload();
          if (!(prefs.getBool('isLoggedIn') ?? false)) return;

          // Check Announcements fallback
          final annResponse = await supabase.from('announcements').select().order('id', ascending: false).limit(5);
          for (var doc in annResponse) {
            final String id = doc['id'].toString();
            if (!(prefs.getBool('notified_announcement_$id') ?? false)) {
              await notificationService.showNotificationNow(
                doc['title'] ?? "New Announcement",
                doc['body'] ?? "Tap to read more.",
                channelId: 'urgent_alert_channel',
              );
              await prefs.setBool('notified_announcement_$id', true);
            }
          }
        } catch (e) {
          debugPrint("Background periodic check failed: $e");
        }
      });

      // Dedicated Assignment Table Listener (Keep for backward/future compatibility)
      try {
        supabase
            .from('assignments')
            .stream(primaryKey: ['id'])
            .listen((docs) async {
          if (docs.isEmpty) return;
          
          await prefs.reload();
          if (!(prefs.getBool('isLoggedIn') ?? false)) return;

          final completedAssignments = prefs.getStringList('completed_assignments') ?? [];

          for (var doc in docs) {
            final String id = doc['id'].toString();
            final String course = doc['course'] ?? "Assignment";
            final String questions = doc['questions'] ?? "";
            final DateTime dueDate = DateTime.parse(doc['due_date']);
            
            final String notifiedKey = 'notified_assignment_$id';
            if (!(prefs.getBool(notifiedKey) ?? false) && !completedAssignments.contains(id)) {
              await notificationService.showNotificationNow(
                "New Assignment: $course",
                questions.length > 100 ? questions.substring(0, 100) + "..." : questions,
                saveToLog: true,
              );
              await notificationService.scheduleAssignmentReminders(id, course, questions, dueDate);
              await prefs.setBool(notifiedKey, true);
            }
          }
        }, onError: (e) => debugPrint("Assignments table sync skipped: $e"));
      } catch (e) {
        debugPrint("Assignments table listener failed: $e");
      }
    } catch (e) {
      debugPrint("Background Service Init Error (Suppressed): $e");
    }
  });
}
