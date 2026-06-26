import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ActivityService {
  static final ActivityService _instance = ActivityService._internal();
  factory ActivityService() => _instance;
  ActivityService._internal();

  /// Logs activity both locally and to Supabase (if logged in)
  Future<void> trackActivity({
    required String title,
    required String subtitle,
    required String type, // 'pdf', 'video', 'course', etc.
    String? path,
    String? url,
    String? course,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Update Local Recent Activity
    await prefs.setString('recent_title', title);
    await prefs.setString('recent_subtitle', subtitle);
    await prefs.setString('recent_type', type);
    if (path != null) await prefs.setString('recent_path', path);
    if (url != null) await prefs.setString('recent_url', url);
    if (course != null) await prefs.setString('recent_course', course);

    // 2. Sync to Supabase
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        await supabase.from('student_activity').insert({
          'uid': user.id,
          'student_id': user.userMetadata?['reg_number'] ?? 'unknown',
          'full_name': user.userMetadata?['full_name'] ?? 'Unknown Student',
          'title': title,
          'subtitle': subtitle,
          'type': type,
          'path': path,
          'url': url,
          'course': course,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint("Failed to sync activity to Supabase: $e");
    }
  }
}
