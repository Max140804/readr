import 'package:flutter/material.dart';
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';

enum AssignmentStatus { pending, completed, overdue }

class Assignment {
  final String id;
  final String title;
  final DateTime dueDate;
  final AssignmentStatus status;
  final String description;

  Assignment({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.status,
    this.description = "",
  });
}

class AssignmentsPage extends StatefulWidget {
  final String courseName;
  final List<Assignment> assignments;
  final List dynamicAssignments;

  const AssignmentsPage({
    super.key,
    required this.courseName,
    required this.assignments,
    this.dynamicAssignments = const [],
  });

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final allItemsCount = widget.assignments.length + widget.dynamicAssignments.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AcademicTheme.primary,
        title: Text(
          "${widget.courseName} Assignments",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: allItemsCount == 0
          ? _buildEmptyState(isDark)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...widget.assignments.map((a) => _AssignmentCard(assignment: a)),
                ...widget.dynamicAssignments.map((d) => _DynamicAssignmentCard(data: d, courseName: widget.courseName)),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            size: 80,
            color: (isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            "No assignments yet",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Enjoy your free time!",
            style: TextStyle(
              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final Assignment assignment;

  const _AssignmentCard({required this.assignment});

  Color _getStatusColor() {
    switch (assignment.status) {
      case AssignmentStatus.completed:
        return Colors.green;
      case AssignmentStatus.overdue:
        return Colors.red;
      case AssignmentStatus.pending:
        return Colors.orange;
    }
  }

  String _getStatusText() {
    switch (assignment.status) {
      case AssignmentStatus.completed:
        return 'Completed';
      case AssignmentStatus.overdue:
        return 'Overdue';
      case AssignmentStatus.pending:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = _getStatusColor();
    final deadlineStr = "${assignment.dueDate.day}/${assignment.dueDate.month}/${assignment.dueDate.year}";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 6,
                color: statusColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              assignment.title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusText(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (assignment.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          assignment.description,
                          style: TextStyle(
                            color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: AcademicTheme.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Deadline: $deadlineStr",
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AcademicTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DynamicAssignmentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String courseName;

  const _DynamicAssignmentCard({required this.data, required this.courseName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final path = data['path'] as String? ?? "";
    final isPdf = path.toLowerCase().endsWith('.pdf');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
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
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(isPdf ? Icons.picture_as_pdf : Icons.description, color: isPdf ? Colors.red : Colors.blue),
        ),
        title: Text(
          data['title'] ?? 'Assignment Document',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
          ),
        ),
        subtitle: const Text("Tap to view assignment instructions"),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AcademicTheme.accent),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SmartPDFViewerPage(
                title: data['title'] ?? 'Assignment',
                assetPath: path,
                courseName: courseName,
              ),
            ),
          );
        },
      ),
    );
  }
}
