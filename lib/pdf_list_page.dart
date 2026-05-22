import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data/timetable_data.dart';

import 'SmartPDFViewerPage.dart';

class PDFListPage extends StatelessWidget {
  final String courseName;
  final List pdfs;

  const PDFListPage({
    super.key,
    required this.courseName,
    required this.pdfs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (pdfs.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: AcademicTheme.primary,
          title: Text("$courseName Materials"),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_stories_outlined, size: 60, color: isDark ? Colors.grey[700] : Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                "No materials available for this course yet.",
                style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          courseName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: AcademicTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pdfs.length,
        itemBuilder: (context, index) {
          final item = pdfs[index];
          final path = item["path"] as String? ?? "";
          final isPdf = path.toLowerCase().endsWith('.pdf');
          final isDocx = path.toLowerCase().endsWith('.docx') || path.toLowerCase().endsWith('.doc');

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              tileColor: theme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AcademicTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPdf ? Icons.picture_as_pdf : (isDocx ? Icons.description : Icons.insert_drive_file),
                  color: isPdf ? Colors.red : (isDocx ? Colors.blue : Colors.orange),
                ),
              ),
              title: Text(
                item["title"],
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                isPdf ? "Tap to open PDF" : (isDocx ? "Tap to open Document" : "Tap to open File"),
                style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: AcademicTheme.accent,
              ),
              onTap: () async {
                // Save to recent activity
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('recent_title', item["title"]);
                await prefs.setString('recent_subtitle', "Continue reading from $courseName");
                await prefs.setString('recent_type', 'pdf'); // Keep as 'pdf' for Dashboard logic compatibility
                await prefs.setString('recent_path', item["path"]);
                await prefs.setString('recent_course', courseName);

                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmartPDFViewerPage(
                        title: item["title"],
                        assetPath: item["path"],
                        courseName: courseName,
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}