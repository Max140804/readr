import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';
import 'assistant_page.dart';
import 'services/notification_service.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
  final bool isAdmin;

  const AssignmentsPage({
    super.key,
    required this.courseName,
    required this.assignments,
    this.dynamicAssignments = const [],
    this.isAdmin = false,
  });

  @override
  State<AssignmentsPage> createState() => _AssignmentsPageState();
}

class _AssignmentsPageState extends State<AssignmentsPage> {
  final _supabase = Supabase.instance.client;
  final List<String> _completedIds = [];

  @override
  void initState() {
    super.initState();
    _loadCompleted();
  }

  Future<void> _loadCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _completedIds.addAll(prefs.getStringList('completed_assignments') ?? []);
    });
  }

  Future<void> _toggleComplete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
      } else {
        _completedIds.add(id);
        NotificationService().cancelAssignmentReminders(id);
      }
    });
    await prefs.setStringList('completed_assignments', _completedIds);
  }

  Future<void> _deleteAssignment(Map item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Assignment?"),
        content: Text("Are you sure you want to delete '${item['title']}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (item['id'] != null) {
          await _supabase.from('course_materials').delete().eq('id', item['id']);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assignment deleted")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AcademicTheme.primary,
        title: Text(
          widget.courseName == "All" ? "All Assignments" : "${widget.courseName} Assignments",
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: widget.courseName == "All" 
            ? _buildUnifiedView(isDark)
            : _buildList(widget.assignments, widget.dynamicAssignments, isDark),
        ),
      ),
    );
  }

  Widget _buildUnifiedView(bool isDark) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _supabase.from('course_materials').stream(primaryKey: ['id']).eq('type', 'Assignment'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final List dynamicItems = [];
        if (snapshot.hasData) {
          for (var data in snapshot.data!) {
            final String fileName = data['file_name'] ?? "";
            String dueDateStr = "";
            try {
              if (fileName.contains("|DUE:")) {
                dueDateStr = fileName.split("|DUE:").last;
              }
            } catch (_) {}

            if (fileName.startsWith("TEXT_ASSIGNMENT")) {
              dynamicItems.add({
                "id": data['id'],
                "title": data['url'],
                "dueDate": dueDateStr,
                "isText": true,
                "course": data['course'],
              });
            } else {
              dynamicItems.add({
                "id": data['id'],
                "title": data['title'],
                "path": data['url'],
                "dueDate": dueDateStr,
                "isText": false,
                "course": data['course'],
              });
            }
          }
        }

        return _buildList([], dynamicItems, isDark);
      },
    );
  }

  Widget _buildList(List<Assignment> staticList, List dynamicList, bool isDark) {
    final allItemsCount = staticList.length + dynamicList.length;
    if (allItemsCount == 0) return _buildEmptyState(isDark);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...staticList.map((a) => _AssignmentCard(assignment: a)),
        ...dynamicList.map((d) {
          final id = d['id']?.toString() ?? "";
          final isCompleted = _completedIds.contains(id);
          return _DynamicAssignmentCard(
            data: d, 
            courseName: d['course'] ?? widget.courseName,
            isAdmin: widget.isAdmin,
            onDelete: () => _deleteAssignment(d),
            isCompleted: isCompleted,
            onToggleComplete: () => _toggleComplete(id),
          );
        }),
      ],
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

class _DynamicAssignmentCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final String courseName;
  final bool isAdmin;
  final VoidCallback onDelete;
  final bool isCompleted;
  final VoidCallback onToggleComplete;

  const _DynamicAssignmentCard({
    required this.data, 
    required this.courseName,
    this.isAdmin = false,
    required this.onDelete,
    required this.isCompleted,
    required this.onToggleComplete,
  });

  @override
  State<_DynamicAssignmentCard> createState() => _DynamicAssignmentCardState();
}

class _DynamicAssignmentCardState extends State<_DynamicAssignmentCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9).chain(CurveTween(curve: Curves.easeIn)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 30),
    ]).animate(_controller);

    _rotateAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.1).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: -0.1).chain(CurveTween(curve: Curves.easeInOut)), weight: 50),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 25),
    ]).animate(_controller);
  }

  Future<void> _pickReminder(BuildContext context, DateTime? existingDueDate) async {
    final DateTime now = DateTime.now();
    final DateTime initialDate = existingDueDate ?? now.add(const Duration(days: 1));
    
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AcademicTheme.primary,
            onPrimary: Colors.white,
            onSurface: AcademicTheme.textPrimary,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate != null && mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initialDate),
      );

      if (pickedTime != null) {
        final DateTime scheduledDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        if (scheduledDateTime.isAfter(now)) {
          final String id = widget.data['id']?.toString() ?? widget.data['title'] ?? "assignment";
          await NotificationService().scheduleCustomEvent(
            "Reminder: ${widget.data['title'] ?? 'Assignment'}",
            "Don't forget to work on your assignment for ${widget.courseName}!",
            scheduledDateTime,
          );
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Reminder set for ${DateFormat('MMM dd, HH:mm').format(scheduledDateTime)}"),
                backgroundColor: AcademicTheme.primary,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Please pick a future time")),
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final path = widget.data['path'] as String? ?? "";
    final isPdf = path.toLowerCase().endsWith('.pdf');
    final isText = widget.data['isText'] == true;
    
    String rawTitle = widget.data['title'] ?? (isText ? "Assignment Task" : "Assignment Document");
    String displayTitle = rawTitle;
    
    if (isText) {
      final lines = rawTitle.split('\n').where((l) => l.trim().isNotEmpty).toList();
      displayTitle = lines.isNotEmpty ? lines.first.replaceAll('#', '').trim() : "Text Assignment";
      if (displayTitle.length > 60) displayTitle = displayTitle.substring(0, 57) + "...";
    }

    final String? dueDateStr = widget.data['dueDate'];
    DateTime? dueDate;
    if (dueDateStr != null && dueDateStr.isNotEmpty) {
      try {
        dueDate = DateTime.parse(dueDateStr);
      } catch (_) {}
    }
    
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: widget.isCompleted ? 0.7 : 1.0,
      child: Container(
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (isText) {
                _showTextAssignment(context, rawTitle);
              } else if (isPdf) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmartPDFViewerPage(
                      title: displayTitle,
                      assetPath: path,
                      courseName: widget.courseName,
                    ),
                  ),
                );
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 6,
                      color: widget.isCompleted ? Colors.green : (dueDate != null && dueDate.isBefore(DateTime.now()) ? Colors.red : Colors.orange),
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
                                    displayTitle,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                                      decoration: widget.isCompleted ? TextDecoration.lineThrough : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    if (!widget.isCompleted) {
                                      _controller.forward(from: 0);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text("Great job! Assignment marked as done! 🎉"),
                                          duration: Duration(seconds: 2),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                    widget.onToggleComplete();
                                  },
                                  child: AnimatedBuilder(
                                    animation: _controller,
                                    builder: (context, child) => Transform.scale(
                                      scale: _scaleAnimation.value,
                                      child: Transform.rotate(
                                        angle: _rotateAnimation.value,
                                        child: child,
                                      ),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (widget.isCompleted ? Colors.green : (dueDate != null && dueDate.isBefore(DateTime.now()) ? Colors.red : Colors.orange)).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        widget.isCompleted ? "Done" : (dueDate != null && dueDate.isBefore(DateTime.now()) ? "Overdue" : "Pending"),
                                        style: TextStyle(
                                          color: widget.isCompleted ? Colors.green : (dueDate != null && dueDate.isBefore(DateTime.now()) ? Colors.red : Colors.orange),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  isPdf ? Icons.picture_as_pdf : Icons.description,
                                  size: 16,
                                  color: isPdf ? Colors.red : Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isText ? "Tap to read questions" : "Tap to view document",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today_rounded, size: 14, color: AcademicTheme.accent),
                                const SizedBox(width: 6),
                                Text(
                                  dueDate != null 
                                    ? "Deadline: ${dueDate.day}/${dueDate.month}/${dueDate.year}"
                                    : "No deadline set",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AcademicTheme.accent,
                                  ),
                                ),
                                const Spacer(),
                                if (!widget.isCompleted)
                                  IconButton(
                                    icon: const Icon(Icons.notification_add_outlined, color: AcademicTheme.accent, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _pickReminder(context, dueDate),
                                    tooltip: "Set Reminder",
                                  ),
                                if (widget.isAdmin && widget.data['id'] != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: widget.onDelete,
                                  ),
                                ]
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
          ),
        ),
      ),
    );
  }

  void _showTextAssignment(BuildContext context, String content) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121212) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: Column(
          children: [
            // Handle Bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Assignment Details",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : AcademicTheme.textPrimary,
                          ),
                        ),
                        Text(
                          widget.courseName,
                          style: TextStyle(
                            fontSize: 14,
                            color: AcademicTheme.accent.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Premium AI Assistant Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AssistantPage(
                              initialPrompt: "I am working on an assignment for '${widget.courseName}'. Here is the task content:\n\n$content\n\nCan you help me answer these questions?",
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AcademicTheme.primary, AcademicTheme.primary.withValues(alpha: 0.8)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AcademicTheme.primary.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.auto_awesome, size: 18, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              "Ask AI",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Premium Copy Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: content));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white, size: 20),
                                SizedBox(width: 12),
                                Text("Content copied to clipboard"),
                              ],
                            ),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            backgroundColor: Colors.green.shade700,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AcademicTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AcademicTheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.content_copy_rounded,
                          size: 20,
                          color: AcademicTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 20),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // Content
            Expanded(
              child: Stack(
                children: [
                  Markdown(
                    data: content,
                    selectable: true,
                    padding: const EdgeInsets.all(24),
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: isDark ? Colors.grey[300] : Colors.grey[800],
                      ),
                      h1: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AcademicTheme.textPrimary,
                        height: 2.0,
                      ),
                      h2: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AcademicTheme.textPrimary,
                        height: 1.8,
                      ),
                      listBullet: TextStyle(
                        color: AcademicTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      blockquote: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                      blockquoteDecoration: BoxDecoration(
                        color: AcademicTheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: const Border(
                          left: BorderSide(color: AcademicTheme.primary, width: 4),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.all(16),
                      code: TextStyle(
                        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[200],
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Fade at the bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (isDark ? const Color(0xFF121212) : Colors.white).withValues(alpha: 0),
                            (isDark ? const Color(0xFF121212) : Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Bottom Action Bar
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    if (!widget.isCompleted) {
                      _controller.forward(from: 0);
                    }
                    widget.onToggleComplete();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isCompleted ? Colors.grey.shade400 : AcademicTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.isCompleted ? Icons.undo_rounded : Icons.check_circle_outline_rounded,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.isCompleted ? "Mark as Pending" : "Complete Assignment",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
