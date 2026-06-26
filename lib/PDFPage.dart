import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pdf_list_page.dart';
import 'youtube_videos_page.dart';
import 'past_questions_page.dart';
import 'assignments_page.dart';
import 'data/timetable_data.dart';
import 'data/course_data.dart';
import 'utils/responsive_utils.dart';

class PDFPage extends StatefulWidget {
  final String courseTitle;
  final List pdfs;
  final List videos;
  final List pastQuestions;
  final List<Assignment> assignments;
  final bool isAdmin;

  const PDFPage({
    super.key,
    required this.courseTitle,
    required this.pdfs,
    required this.videos,
    this.pastQuestions = const [],
    this.assignments = const <Assignment>[],
    this.isAdmin = false,
  });

  @override
  State<PDFPage> createState() => _PDFPageState();
}

class _PDFPageState extends State<PDFPage> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBarColor = isDark ? AcademicTheme.primary : AcademicTheme.primary;
    final titleColor = isDark ? AcademicTheme.darkPrimary : Colors.white;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarColor,
        title: Text(
          widget.courseTitle, 
          style: TextStyle(fontWeight: FontWeight.bold, color: titleColor)
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: titleColor),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: Responsive.isDesktop(context) ? 900 : double.infinity),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _supabase.from('course_materials').stream(primaryKey: ['id']).eq('course', widget.courseTitle),
            builder: (context, materialSnapshot) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _supabase.from('videos').stream(primaryKey: ['id']).eq('course', widget.courseTitle),
                builder: (context, videoSnapshot) {
                  return StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _supabase.from('assignments').stream(primaryKey: ['id']).eq('course', widget.courseTitle),
                    builder: (context, assignmentSnapshot) {
                      
                      // Process Supabase materials
                      List firestorePdfs = [];
                      List firestoreLectureNotes = [];
                      List firestorePQs = [];
                      List firestoreAssignments = [];
                      
                      if (materialSnapshot.hasData) {
                        for (var data in materialSnapshot.data!) {
                          final item = {
                            "id": data['id'],
                            "title": data['title'], 
                            "path": data['url'],
                            "isDynamic": true
                          };
                          
                          if (data['type'] == 'Assignment') {
                            final String fileName = data['file_name'] ?? "";
                            String dueDateStr = "";
                            try {
                              if (fileName.contains("|DUE:")) {
                                dueDateStr = fileName.split("|DUE:").last;
                              }
                            } catch (_) {}

                            if (fileName.startsWith("TEXT_ASSIGNMENT")) {
                              firestoreAssignments.add({
                                "id": data['id'],
                                "title": data['url'], // The actual questions
                                "dueDate": dueDateStr,
                                "isText": true,
                                "isDynamic": true,
                              });
                            } else {
                              // Handle PDF-based assignment (either with PDF_ASSIGNMENT marker or legacy)
                              firestoreAssignments.add({
                                "id": data['id'],
                                "title": data['title'],
                                "path": data['url'],
                                "dueDate": dueDateStr,
                                "isText": false,
                                "isDynamic": true,
                              });
                            }
                          } else if (data['type'] == 'Course Material') {
                            firestorePdfs.add(item);
                          } else if (data['type'] == 'Lecture Note') {
                            firestoreLectureNotes.add(item);
                          } else if (data['type'] == 'Past Question') {
                            firestorePQs.add(item);
                          }
                        }
                      }

                      // Process dedicated assignments table if it exists
                      try {
                        if (assignmentSnapshot.hasData) {
                          for (var data in assignmentSnapshot.data!) {
                            firestoreAssignments.add({
                              "id": data['id'],
                              "title": data['questions'],
                              "dueDate": data['due_date'],
                              "isText": true,
                              "isDynamic": true,
                            });
                          }
                        }
                      } catch (_) {
                        // Table likely doesn't exist, already handled via course_materials
                      }

                      // Process Supabase videos
                      List firestoreVideos = [];
                      if (videoSnapshot.hasData) {
                        for (var data in videoSnapshot.data!) {
                          firestoreVideos.add({
                            "id": data['id'],
                            "title": data['title'],
                            "url": data['url'],
                            "thumbnail": data['thumbnail'] ?? "https://img.youtube.com/vi/${YoutubePlayer.convertUrlToId(data['url'])}/0.jpg",
                            "isDynamic": true
                          });
                        }
                      }

                      // Merge static and firestore content with deduplication
                      final List allPdfs = [...widget.pdfs];
                      for (var item in firestorePdfs) {
                        if (!allPdfs.any((p) => p['path'] == item['path'])) {
                          allPdfs.add(item);
                        }
                      }

                      final List allLectureNotes = firestoreLectureNotes;

                      final List allVideos = [...widget.videos];
                      for (var item in firestoreVideos) {
                        if (!allVideos.any((v) => v['url'] == item['url'])) {
                          allVideos.add(item);
                        }
                      }

                      final List allPQs = [...widget.pastQuestions];
                      for (var item in firestorePQs) {
                        if (!allPQs.any((p) => p['path'] == item['path'])) {
                          allPQs.add(item);
                        }
                      }

                      final allAssignments = List<Assignment>.from(widget.assignments);
                      
                      if (materialSnapshot.connectionState == ConnectionState.waiting && allPdfs.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      return Column(
                        children: [
                          _buildHeader(materialSnapshot.hasData, isDark),
                          Expanded(
                            child: RefreshIndicator(
                              onRefresh: () async => setState(() {}),
                              child: ListView(
                                padding: EdgeInsets.symmetric(
                                  horizontal: Responsive.getHorizontalPadding(context),
                                  vertical: 16,
                                ),
                                children: [
                                  _MaterialTile(
                                    title: "Lecture Notes",
                                    subtitle: "Detailed notes from class (${allLectureNotes.length})",
                                    icon: Icons.note_alt_rounded,
                                    color: Colors.blue,
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFListPage(courseName: widget.courseTitle, pdfs: allLectureNotes, titleOverride: "Lecture Notes", isAdmin: widget.isAdmin))),
                                  ),
                                  _MaterialTile(
                                    title: "${widget.courseTitle} PDF Materials",
                                    subtitle: "Notes and handouts (${allPdfs.length})",
                                    icon: Icons.picture_as_pdf_rounded,
                                    color: Colors.red,
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFListPage(courseName: widget.courseTitle, pdfs: allPdfs, isAdmin: widget.isAdmin))),
                                  ),
                                  _MaterialTile(
                                    title: "Youtube Videos",
                                    subtitle: "Watch lessons (${allVideos.length})",
                                    icon: Icons.play_circle_fill_rounded,
                                    color: Colors.redAccent,
                                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => YoutubeVideosPage(courseName: widget.courseTitle, videos: allVideos, isAdmin: widget.isAdmin))),
                                  ),
                                  _MaterialTile(
                                    title: "Past Questions",
                                    subtitle: "Practice exams (${allPQs.length})",
                                    icon: Icons.quiz_rounded,
                                    color: Colors.orange,
                                    onTap: () {
                                      final pqs = allPQs.isEmpty && widget.courseTitle == "ECE 537" ? [
                                        {"title": "2023 Exam", "path": CourseData.getPath("assets/pdfs/ECE 537 - Lect - Introduction-1.pdf")},
                                        {"title": "2022 Exam", "path": CourseData.getPath("assets/pdfs/ECE 537 - Lect - Introduction-1.pdf")}
                                      ] : allPQs;
                                      Navigator.push(context, MaterialPageRoute(builder: (_) => PastQuestionsPage(courseName: widget.courseTitle, questions: pqs, isAdmin: widget.isAdmin)));
                                    },
                                  ),
                                  _MaterialTile(
                                    title: "Assignments",
                                    subtitle: "Weekly tasks (${allAssignments.length + firestoreAssignments.length})",
                                    icon: Icons.assignment_rounded,
                                    color: Colors.green,
                                    onTap: () => Navigator.push(
                                      context, 
                                      MaterialPageRoute(
                                        builder: (_) => AssignmentsPage(
                                          courseName: widget.courseTitle, 
                                          assignments: allAssignments,
                                          dynamicAssignments: firestoreAssignments,
                                          isAdmin: widget.isAdmin,
                                        )
                                      )
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  );
                }
              );
            }
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool hasData, bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AcademicTheme.primary : AcademicTheme.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AcademicTheme.primary).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Course Materials", 
            style: TextStyle(
              color: isDark ? AcademicTheme.darkTextPrimary : Colors.white, 
              fontSize: 24, 
              fontWeight: FontWeight.bold
            )
          ),
          const SizedBox(height: 6),
          Text(
            "Everything you need in one place",
            style: TextStyle(
              color: (isDark ? AcademicTheme.darkTextSecondary : Colors.white).withValues(alpha: 0.7), 
              fontSize: 15
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MaterialTile({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: AcademicTheme.accent),
          ],
        ),
      ),
    );
  }
}
