import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'notification_service.dart';

class UpdateService {
  static final ValueNotifier<Map<String, dynamic>?> updateAvailableNotifier = ValueNotifier(null);

  static Future<void> checkForUpdates(BuildContext context, {bool showDialog = true}) async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = "${packageInfo.version}+${packageInfo.buildNumber}";

      final data = await Supabase.instance.client
          .from('app_updates')
          .select()
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data != null) {
        final latestVersion = data['version'];
        final updateUrl = data['url'];
        final releaseNotes = data['release_notes'] ?? "New features and bug fixes.";

        if (_isNewerVersion(currentVersion, latestVersion)) {
          updateAvailableNotifier.value = {
            'version': latestVersion,
            'url': updateUrl,
            'notes': releaseNotes,
          };

          if (showDialog) {
            final prefs = await SharedPreferences.getInstance();
            final lastPrompt = prefs.getInt('last_update_prompt') ?? 0;
            final now = DateTime.now().millisecondsSinceEpoch;
            
            // Only prompt if 24 hours have passed since the last "Later" click
            if (now - lastPrompt > 86400000) {
              if (!context.mounted) return;
              _showUpdateDialog(context, latestVersion, updateUrl, releaseNotes);
            }
          }
        } else {
          updateAvailableNotifier.value = null;
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    try {
      // Split into version and build number
      final currentParts = current.split('+');
      final latestParts = latest.split('+');

      // Compare semantic version (x.y.z)
      final currentV = currentParts[0].split('.');
      final latestV = latestParts[0].split('.');

      for (int i = 0; i < 3; i++) {
        final c = i < currentV.length ? (int.tryParse(currentV[i]) ?? 0) : 0;
        final l = i < latestV.length ? (int.tryParse(latestV[i]) ?? 0) : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // If semantic versions are equal, compare build numbers
      final latestBuild = latestParts.length > 1 ? (int.tryParse(latestParts[1]) ?? 0) : 0;
      final currentBuild = currentParts.length > 1 ? (int.tryParse(currentParts[1]) ?? 0) : 0;
      return latestBuild > currentBuild;
    } catch (e) {
      debugPrint("Version comparison error: $e");
      return latest != current;
    }
  }

  static void _showUpdateDialog(BuildContext context, String version, String url, String notes) async {
    // Record that we showed the prompt to respect the 24h cooldown
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_update_prompt', DateTime.now().millisecondsSinceEpoch);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("New Update Available! 🚀"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Version $version is ready for sync."),
            const SizedBox(height: 12),
            const Text("What's New:", style: TextStyle(fontWeight: FontWeight.bold)),
            Text(notes, style: const TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB), // Vibrant Blue
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(context);
              startUpdateFlow(context, url, version);
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }

  static Future<void> startUpdateFlow(BuildContext context, String url, String version) async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final String currentVersion = "${packageInfo.version}+${packageInfo.buildNumber}";

      // If user somehow triggers update when already on that version, just stay here
      if (!_isNewerVersion(currentVersion, version)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("App is already up to date!"))
          );
        }
        return;
      }

      String downloadUrl = url;
      if (!url.startsWith('http')) {
        downloadUrl = Supabase.instance.client.storage
            .from('materials')
            .getPublicUrl(url);
      }

      final Uri uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw "Could not launch browser for update.";
      }
    } catch (e) {
      debugPrint("Update error: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not open download link: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Listens for new updates in real-time and shows a notification
  static void listenForUpdates() {
    Supabase.instance.client
        .from('app_updates')
        .stream(primaryKey: ['id'])
        .order('id', ascending: false)
        .limit(1)
        .listen((List<Map<String, dynamic>> data) async {
          if (data.isNotEmpty) {
            final latest = data.first;
            final latestVersion = latest['version'];
            final updateUrl = latest['url'];
            
            final PackageInfo packageInfo = await PackageInfo.fromPlatform();
            final String currentVersion = "${packageInfo.version}+${packageInfo.buildNumber}";

            if (_isNewerVersion(currentVersion, latestVersion)) {
              updateAvailableNotifier.value = {
                'version': latestVersion,
                'url': updateUrl,
                'notes': latest['release_notes'] ?? "New features and bug fixes.",
              };
              // Show notification
              NotificationService().showNotificationNow(
                "New Update Available! 🚀",
                "Version $latestVersion is ready. Tap to install now.",
                payload: "update|$updateUrl|$latestVersion",
                channelId: 'updates_channel',
              );
            } else {
              updateAvailableNotifier.value = null;
            }
          }
        });
  }
}

