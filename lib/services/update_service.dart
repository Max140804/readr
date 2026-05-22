import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  // Updated to your GitHub repository
  static const String versionUrl = "https://raw.githubusercontent.com/Max140804/readr/main/version.json";
  static const String currentVersion = "1.0.0+1";

  static Future<void> checkForUpdates(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse(versionUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestVersion = data['version'];
        final updateUrl = data['url'];

        if (latestVersion != currentVersion) {
          if (!context.mounted) return;
          _showUpdateDialog(context, latestVersion, updateUrl);
        }
      }
    } catch (e) {
      debugPrint("Update check failed: $e");
    }
  }

  static void _showUpdateDialog(BuildContext context, String version, String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Update Available! 🚀"),
        content: Text("A new version ($version) of Readr is available. Update now to get the latest features and fixes."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text("Update Now"),
          ),
        ],
      ),
    );
  }
}
