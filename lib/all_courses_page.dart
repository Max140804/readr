import 'package:flutter/material.dart';
import 'PDFPage.dart';
import 'assignments_page.dart';
import 'data/timetable_data.dart';

class AllCoursesPage extends StatelessWidget {
  const AllCoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final courses = [
      {
        "title": "ECE 527",
        "subtitle": "Solid State Electronics",
        "icon": Icons.lightbulb,
        "color": Colors.deepOrange,
        "pdfs": [
          {"title": "Semiconductor Fabrication Process", "path": "assets/pdfs/ECE 527 LECTURE 2.docx"},
        ],
        "videos": [
          {
            "title": "Semiconductor Introduction",
            "thumbnail": "https://img.youtube.com/vi/tiP6fgySxPU/0.jpg",
            "url": "https://youtu.be/tiP6fgySxPU?si=iZOryxdxMCxHH9hO",
          }
        ],
        "pastQuestions": [
          {"title": "2023 Exam", "path": "assets/pdfs/ECE 527 LECTURE 2.docx"},
        ],
        "assignments": [
          Assignment(id: "1", title: "PN Junction Analysis", dueDate: DateTime.now().add(const Duration(days: 3)), status: AssignmentStatus.pending),
        ],
      },
      {
        "title": "ECE 537",
        "subtitle": "Digital Signal Processing",
        "icon": Icons.graphic_eq,
        "color": Colors.blue,
        "pdfs": [
          {"title": "Introduction to DSP", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"},
        ],
        "videos": [
          {
            "title": "DSP Introduction",
            "thumbnail": "https://img.youtube.com/vi/iCaDt9Esdv4/0.jpg",
            "url": "https://youtu.be/iCaDt9Esdv4?si=W7gAhEzvfHcKjhl4",
          },
        ],
        "pastQuestions": [
          {"title": "2023 Exam", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"},
          {"title": "2022 Exam", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"}
        ],
        "assignments": [
          Assignment(id: "2", title: "FFT Implementation", dueDate: DateTime.now().subtract(const Duration(days: 1)), status: AssignmentStatus.overdue),
        ],
      },
      {
        "title": "ECE 517",
        "subtitle": "Real-time Computing and Control",
        "icon": Icons.timer_outlined,
        "color": Colors.indigo,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
      {
        "title": "ECE 539",
        "subtitle": "Communication Systems",
        "icon": Icons.settings_input_antenna,
        "color": Colors.redAccent,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
      {
        "title": "ECE 519",
        "subtitle": "Seminar",
        "icon": Icons.co_present,
        "color": Colors.purple,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
      {
        "title": "ECE 505",
        "subtitle": "Computer Aided Design",
        "icon": Icons.architecture,
        "color": Colors.blueGrey,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
      {
        "title": "ECE 541",
        "subtitle": "Artificial Intelligence",
        "icon": Icons.psychology_outlined,
        "color": Colors.teal,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
      {
        "title": "ECE 529",
        "subtitle": "System Programming",
        "icon": Icons.terminal,
        "color": Colors.green,
        "pdfs": [],
        "videos": [],
        "pastQuestions": [],
        "assignments": [],
      },
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: AcademicTheme.primary,
        title: const Text(
          "All Courses",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: courses.length,
          gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final course = courses[index];

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PDFPage(
                      courseTitle: course["title"] as String,
                      pdfs: (course["pdfs"] as List?) ?? [],
                      videos: (course["videos"] as List?) ?? [],
                      pastQuestions: (course["pastQuestions"] as List?) ?? [],
                      assignments: (course["assignments"] as List?) ?? [],
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (course["color"] as Color)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        course["icon"] as IconData,
                        color: course["color"] as Color,
                        size: 30,
                      ),
                    ),

                    const SizedBox(height: 18),

                    Text(
                      course["title"] as String,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      course["subtitle"] as String,
                      style: TextStyle(
                        color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Icon(Icons.bookmark_outline_rounded, size: 12, color: AcademicTheme.accent),
                        const SizedBox(width: 4),
                        Text(
                          "3 Credit Units",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: (course["color"] as Color)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        "Open Course",
                        style: TextStyle(
                          color: course["color"] as Color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
