import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'PDFPage.dart';
import 'assignments_page.dart';
import 'data/timetable_data.dart';
import 'utils/responsive_utils.dart';
import 'data/course_data.dart';

class AllCoursesPage extends StatefulWidget {
  final bool isAdmin;
  const AllCoursesPage({super.key, this.isAdmin = false});

  @override
  State<AllCoursesPage> createState() => _AllCoursesPageState();
}

class _AllCoursesPageState extends State<AllCoursesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? AcademicTheme.darkCard : AcademicTheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "All Courses",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AcademicTheme.accent,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "First Semester"),
            Tab(text: "Second Semester"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCourseList(1),
          _buildCourseList(2),
        ],
      ),
    );
  }

  Widget _buildCourseList(int semester) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final courses = CourseData.getCourses().where((c) => c['semester'] == semester).toList();

    if (courses.isEmpty) {
      return Center(
        child: Text(
          "No courses registered for this semester",
          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
        ),
      );
    }

    return ListView.builder(
      itemCount: courses.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final course = courses[index];
        final credits = course["credits"] as int? ?? 3;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? AcademicTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                course["icon"] as IconData? ?? Icons.book_rounded,
                color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
              ),
            ),
            title: Text(
              course["title"].toString(),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  course["subtitle"].toString(),
                  style: TextStyle(
                    color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$credits Credit Units",
                  style: const TextStyle(
                    color: AcademicTheme.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AcademicTheme.accent),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PDFPage(
                    courseTitle: course["title"] as String,
                    pdfs: (course["pdfs"] as List?) ?? [],
                    videos: (course["videos"] as List?) ?? [],
                    pastQuestions: (course["pastQuestions"] as List?) ?? [],
                    assignments: (course["assignments"] as List? ?? []).cast<Assignment>(),
                    isAdmin: widget.isAdmin,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
