import 'package:flutter/material.dart';
import 'data/timetable_data.dart';
import 'utils/responsive_utils.dart';

class TimetablePage extends StatelessWidget {
  const TimetablePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Weekly Timetable", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: Responsive.isDesktop(context) ? 900 : double.infinity),
          child: ListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: Responsive.getHorizontalPadding(context),
              vertical: 16,
            ),
            itemCount: timetable.length,
            itemBuilder: (context, index) {
              final day = timetable.keys.elementAt(index);
              final classes = timetable[day] ?? [];
              final isToday = _isDayToday(day);

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isDark ? AcademicTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: isToday 
                    ? Border.all(color: AcademicTheme.accent.withValues(alpha: 0.5), width: 2)
                    : null,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      decoration: BoxDecoration(
                        color: isToday 
                            ? AcademicTheme.accent 
                            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            day,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isToday 
                                  ? Colors.white 
                                  : (isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.primary),
                            ),
                          ),
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                "TODAY",
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Classes List
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: classes.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  "Lecture free day! 🌴",
                                  style: TextStyle(
                                    color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: classes.map((c) {
                                return _buildClassItem(context, c, isDark);
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildClassItem(BuildContext context, Map<String, String> c, bool isDark) {
    final timeStr = c["time"]!;
    final startTime = timeStr.split("-")[0].trim();
    final endTime = timeStr.split("-")[1].trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Column
          SizedBox(
            width: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  startTime,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(width: 10, height: 1, color: AcademicTheme.accent),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          "to",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AcademicTheme.accent),
                        ),
                      ),
                      Container(width: 10, height: 1, color: AcademicTheme.accent),
                    ],
                  ),
                ),
                Text(
                  endTime,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Indicator Line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AcademicTheme.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              Container(
                width: 2,
                height: 60,
                color: isDark ? Colors.white10 : Colors.grey[200],
              ),
            ],
          ),

          const SizedBox(width: 16),

          // Course Info
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50],
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c["course"]!,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.bookmark_outline_rounded,
                        size: 14,
                        color: AcademicTheme.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "3 Credit Units",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined, 
                        size: 14, 
                        color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Engineering Block B",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
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
    );
  }

  bool _isDayToday(String day) {
    final now = DateTime.now();
    final weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    return weekdays[now.weekday - 1] == day;
  }
}
