import 'package:flutter/material.dart';
import 'services/notification_service.dart';
import 'data/timetable_data.dart';
import 'package:intl/intl.dart';
import 'utils/responsive_utils.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationHistoryItem> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await NotificationService().getHistory();
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    await NotificationService().clearHistory();
    _loadHistory();
  }

  Future<void> _markAllRead() async {
    await NotificationService().markAllAsRead();
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Notifications", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_history.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') _clearAll();
                if (value == 'read') _markAllRead();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'read', child: Text("Mark all as read")),
                const PopupMenuItem(value: 'clear', child: Text("Clear all", style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_outlined, size: 80, color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey),
                          const SizedBox(height: 16),
                          Text("No notifications yet", style: TextStyle(fontSize: 18, color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: BorderRadius.circular(16),
                            border: item.isRead 
                              ? null 
                              : Border.all(color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary, width: 1),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.1),
                              child: Icon(Icons.notifications, color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary),
                            ),
                            title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.body),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMM d, h:mm a').format(item.timestamp),
                                  style: TextStyle(fontSize: 11, color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ),
    );
  }
}
