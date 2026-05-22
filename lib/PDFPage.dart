import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'pdf_list_page.dart';
import 'youtube_videos_page.dart';
import 'past_questions_page.dart';
import 'assignments_page.dart';
import 'data/timetable_data.dart';

class PDFPage extends StatefulWidget {
  final String courseTitle;
  final List pdfs;
  final List videos;
  final List pastQuestions;
  final List assignments;

  const PDFPage({
    super.key,
    required this.courseTitle,
    required this.pdfs,
    required this.videos,
    this.pastQuestions = const [],
    this.assignments = const [],
  });

  @override
  State<PDFPage> createState() => _PDFPageState();
}

class _PDFPageState extends State<PDFPage> {
  List _dynamicPdfs = [];
  List _dynamicVideos = [];
  List _dynamicPQs = [];
  List _dynamicAssignments = [];

  @override
  void initState() {
    super.initState();
    _loadDynamicContent();
  }

  Future<void> _loadDynamicContent() async {
    final prefs = await SharedPreferences.getInstance();
    final String key = 'custom_docs_${widget.courseTitle.replaceAll(" ", "_")}';
    final String vidKey = 'custom_videos_${widget.courseTitle.replaceAll(" ", "_")}';

    final String? docsJson = prefs.getString(key);
    final String? vidsJson = prefs.getString(vidKey);

    if (mounted) {
      setState(() {
        if (docsJson != null) {
          final List decoded = jsonDecode(docsJson);
          _dynamicPdfs = decoded.where((d) => d['type'] == 'Course Material').toList();
          _dynamicPQs = decoded.where((d) => d['type'] == 'Past Question').toList();
          _dynamicAssignments = decoded.where((d) => d['type'] == 'Assignment').toList();
        }
        if (vidsJson != null) {
          _dynamicVideos = jsonDecode(vidsJson);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Merge static and dynamic content
    final allPdfs = [...widget.pdfs, ..._dynamicPdfs];
    final allVideos = [...widget.videos, ..._dynamicVideos];
    final allPQs = [...widget.pastQuestions, ..._dynamicPQs];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AcademicTheme.primary,
        title: Text(widget.courseTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _MaterialTile(
                  title: "${widget.courseTitle} PDF Materials",
                  subtitle: "Notes and handouts (${allPdfs.length})",
                  icon: Icons.picture_as_pdf_rounded,
                  color: Colors.red,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PDFListPage(courseName: widget.courseTitle, pdfs: allPdfs))),
                ),
                _MaterialTile(
                  title: "Youtube Videos",
                  subtitle: "Watch lessons (${allVideos.length})",
                  icon: Icons.play_circle_fill_rounded,
                  color: Colors.redAccent,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => YoutubeVideosPage(courseName: widget.courseTitle, videos: allVideos))),
                ),
                _MaterialTile(
                  title: "Past Questions",
                  subtitle: "Practice exams (${allPQs.length})",
                  icon: Icons.quiz_rounded,
                  color: Colors.orange,
                  onTap: () {
                    final pqs = allPQs.isEmpty && widget.courseTitle == "ECE 537" ? [
                      {"title": "2023 Exam", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"},
                      {"title": "2022 Exam", "path": "assets/pdfs/ECE 537 - Lect - Introduction-1.pdf"}
                    ] : allPQs;
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PastQuestionsPage(courseName: widget.courseTitle, questions: pqs)));
                  },
                ),
                _MaterialTile(
                  title: "Assignments",
                  subtitle: "Weekly tasks (${widget.assignments.length + _dynamicAssignments.length})",
                  icon: Icons.assignment_rounded,
                  color: Colors.green,
                  onTap: () => Navigator.push(
                    context, 
                    MaterialPageRoute(
                      builder: (_) => AssignmentsPage(
                        courseName: widget.courseTitle, 
                        assignments: widget.assignments.cast<Assignment>().toList(),
                        dynamicAssignments: _dynamicAssignments,
                      )
                    )
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AcademicTheme.primary, AcademicTheme.secondary]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AcademicTheme.primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Course Materials", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          Text("Everything you need in one place", style: TextStyle(color: Colors.white70, fontSize: 15)),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(18)),
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
