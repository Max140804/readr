import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _supabase = Supabase.instance.client;

  /// Pushes local SharedPreferences data to Supabase user_data table
  Future<void> pushToCloud() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      final bookmarksJson = prefs.getString('bookmarks') ?? '[]';
      final themeIndex = prefs.getInt('themeMode') ?? 0;
      
      // Get recent activity from separate keys as used in ActivityService/Dashboard
      final recentActivity = {
        'title': prefs.getString('recent_title'),
        'subtitle': prefs.getString('recent_subtitle'),
        'type': prefs.getString('recent_type'),
        'path': prefs.getString('recent_path'),
        'url': prefs.getString('recent_url'),
        'course': prefs.getString('recent_course'),
      };

      final studyAlarm = {
        'days': prefs.getStringList('study_alarm_days'),
        'hour': prefs.getInt('study_alarm_hour'),
        'minute': prefs.getInt('study_alarm_minute'),
      };

      await _supabase.from('user_data').upsert({
        'user_id': user.id,
        'bookmarks': jsonDecode(bookmarksJson),
        'theme': themeIndex == 1 ? 'light' : (themeIndex == 2 ? 'dark' : 'system'),
        'recent_activity': recentActivity,
        'study_alarm': studyAlarm,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
      
      debugPrint("Successfully pushed data to cloud");
    } catch (e) {
      debugPrint("Error pushing to cloud: $e");
    }
  }

  /// Pulls data from Supabase user_data table and updates local SharedPreferences
  Future<void> pullFromCloud() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final response = await _supabase
          .from('user_data')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();

      if (response == null) return;

      final prefs = await SharedPreferences.getInstance();
      
      // Sync Bookmarks
      if (response['bookmarks'] != null) {
        await prefs.setString('bookmarks', jsonEncode(response['bookmarks']));
      }

      // Sync Theme
      if (response['theme'] != null) {
        int themeIndex = 0; // system
        if (response['theme'] == 'light') themeIndex = 1;
        if (response['theme'] == 'dark') themeIndex = 2;
        await prefs.setInt('themeMode', themeIndex);
      }

      // Sync Recent Activity
      final recent = response['recent_activity'];
      if (recent != null && recent is Map) {
        if (recent['title'] != null) await prefs.setString('recent_title', recent['title']);
        if (recent['subtitle'] != null) await prefs.setString('recent_subtitle', recent['subtitle']);
        if (recent['type'] != null) await prefs.setString('recent_type', recent['type']);
        if (recent['path'] != null) await prefs.setString('recent_path', recent['path']);
        if (recent['url'] != null) await prefs.setString('recent_url', recent['url']);
        if (recent['course'] != null) await prefs.setString('recent_course', recent['course']);
      }

      // Sync Study Alarm
      final studyAlarm = response['study_alarm'];
      if (studyAlarm != null && studyAlarm is Map) {
        if (studyAlarm['days'] != null) {
          await prefs.setStringList('study_alarm_days', List<String>.from(studyAlarm['days']));
        }
        if (studyAlarm['hour'] != null) {
          await prefs.setInt('study_alarm_hour', studyAlarm['hour']);
        }
        if (studyAlarm['minute'] != null) {
          await prefs.setInt('study_alarm_minute', studyAlarm['minute']);
        }
      }
      
      debugPrint("Successfully pulled data from cloud");
    } catch (e) {
      debugPrint("Error pulling from cloud: $e");
    }
  }
}
