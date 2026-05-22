import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';

class PastQuestionsPage extends StatelessWidget {
  final String courseName;
  final List questions;

  const PastQuestionsPage({
    super.key,
    required this.courseName,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (questions.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
        appBar: AppBar(
          backgroundColor: AcademicTheme.primary,
          title: Text("$courseName Past Questions", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz_outlined, size: 80, color: isDark ? Colors.white10 : Colors.grey[300]),
              const SizedBox(height: 16),
              Text(
                "No past questions available yet.",
                style: TextStyle(
                  color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
      appBar: AppBar(
        title: Text(
          "$courseName Past Questions",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AcademicTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: questions.length,
        itemBuilder: (context, index) {
          final item = questions[index];
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              tileColor: isDark ? AcademicTheme.darkCard : AcademicTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.history_edu,
                  color: Colors.orange,
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
                "Tap to practice",
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
                await prefs.setString('recent_subtitle', "Past Question: $courseName");
                await prefs.setString('recent_type', 'pdf'); 
                await prefs.setString('recent_path', item["path"]);
                await prefs.setString('recent_course', courseName);

                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SmartPDFViewerPage(
                        title: item["title"],
                        assetPath: item["path"],
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