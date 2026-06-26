import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';
import 'services/activity_service.dart';
import 'utils/responsive_utils.dart';

class PastQuestionsPage extends StatefulWidget {
  final String courseName;
  final List questions;
  final bool isAdmin;

  const PastQuestionsPage({
    super.key,
    required this.courseName,
    required this.questions,
    this.isAdmin = false,
  });

  @override
  State<PastQuestionsPage> createState() => _PastQuestionsPageState();
}

class _PastQuestionsPageState extends State<PastQuestionsPage> {
  late List filteredQuestions;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  List<String> _cachedPaths = [];
  final Map<String, bool> _isDownloadingMap = {};
  final Map<String, double> _downloadProgressMap = {};

  @override
  void initState() {
    super.initState();
    filteredQuestions = widget.questions;
    _loadCacheRegistry();
  }

  Future<void> _loadCacheRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _cachedPaths = prefs.getStringList('cached_pdfs') ?? [];
      });
    }
  }

  Future<void> _downloadFile(Map item) async {
    final url = item['path'] as String;
    if (!url.startsWith('http')) return;

    if (_isDownloadingMap[url] == true) return;

    setState(() {
      _isDownloadingMap[url] = true;
      _downloadProgressMap[url] = 0.0;
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final List<int> bytes = [];
        final int total = response.contentLength ?? 0;
        int received = 0;

        await for (var chunk in response.stream) {
          bytes.addAll(chunk);
          received += chunk.length;
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgressMap[url] = received / total;
            });
          }
        }

        final directory = await getApplicationDocumentsDirectory();
        final fileName = url.split('/').last.split('?').first;
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(bytes);
        
        final prefs = await SharedPreferences.getInstance();
        final List<String> cachedUrls = prefs.getStringList('cached_pdfs') ?? [];
        if (!cachedUrls.contains(url)) {
          cachedUrls.add(url);
          await prefs.setStringList('cached_pdfs', cachedUrls);
        }
        
        if (mounted) {
          setState(() {
            _cachedPaths = cachedUrls;
            _isDownloadingMap[url] = false;
            _downloadProgressMap[url] = 0.0;
          });
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${item['title']} downloaded for offline use"),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception("Failed to download file: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingMap[url] = false;
          _downloadProgressMap[url] = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Download failed: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void didUpdateWidget(PastQuestionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.questions != oldWidget.questions) {
      filteredQuestions = widget.questions;
    }
  }

  void filterSearch(String query) {
    setState(() {
      filteredQuestions = widget.questions
          .where((q) => q["title"].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _onRefresh() async {
    try {
      final response = await _supabase
          .from('course_materials')
          .select()
          .eq('course', widget.courseName)
          .eq('type', 'Past Question');
      
      final List firestorePQs = (response as List).map((data) => {
        "id": data['id'],
        "title": data['title'], 
        "path": data['url'],
        "isDynamic": true
      }).toList();

      final staticPQs = widget.questions.where((q) => q['isDynamic'] != true).toList();
      
      setState(() {
        final List allPQs = [...staticPQs];
        for (var item in firestorePQs) {
          if (!allPQs.any((p) => p['path'] == item['path'])) {
            allPQs.add(item);
          }
        }
        filteredQuestions = allPQs;
        if (isSearching && searchController.text.isNotEmpty) {
          filterSearch(searchController.text);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Refresh failed: $e")));
      }
    }
  }

  Future<void> _deleteQuestion(Map item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Past Question?"),
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Past question deleted")));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot delete static local files")));
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
    final appBarColor = isDark ? AcademicTheme.darkCard : AcademicTheme.primary;
    final titleColor = isDark ? AcademicTheme.darkPrimary : Colors.white;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Search questions...",
                  hintStyle: TextStyle(color: titleColor.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: titleColor),
                onChanged: filterSearch,
              )
            : Text(
                "${widget.courseName} Past Questions", 
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)
              ),
        iconTheme: IconThemeData(color: titleColor),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search, color: titleColor),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  filteredQuestions = widget.questions;
                }
              });
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: filteredQuestions.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.quiz_outlined, size: 80, color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            isSearching ? "No matching questions found." : "No past questions available yet.",
                            style: TextStyle(
                              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text("Pull down to refresh", style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredQuestions.length,
                    itemBuilder: (context, index) {
                    final item = filteredQuestions[index];

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
                        tileColor: isDark ? AcademicTheme.darkCard : AcademicTheme.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
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
                        trailing: Builder(
                          builder: (context) {
                            final path = item["path"] as String? ?? "";
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (path.startsWith('http')) ...[
                                  _cachedPaths.contains(path)
                                      ? Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: const Icon(Icons.offline_pin_rounded, color: Colors.green, size: 20),
                                        )
                                      : _PremiumDownloadButton(
                                          progress: _downloadProgressMap[path] ?? 0.0,
                                          isDownloading: _isDownloadingMap[path] ?? false,
                                          onTap: () {
                                            HapticFeedback.lightImpact();
                                            _downloadFile(item);
                                          },
                                        ),
                                  const SizedBox(width: 8),
                                ],
                                if (widget.isAdmin && item['id'] != null)
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    onPressed: () => _deleteQuestion(item),
                                  ),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                                ),
                              ],
                            );
                          },
                        ),
                        onTap: () async {
                          // Save to recent activity
                          await ActivityService().trackActivity(
                            title: item["title"],
                            subtitle: "Past Question: ${widget.courseName}",
                            type: 'pdf',
                            path: item["path"],
                            course: widget.courseName,
                          );

                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SmartPDFViewerPage(
                                  title: item["title"],
                                  assetPath: item["path"],
                                  courseName: widget.courseName,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }
}

class _PremiumDownloadButton extends StatelessWidget {
  final double progress;
  final bool isDownloading;
  final VoidCallback onTap;

  const _PremiumDownloadButton({
    required this.progress,
    required this.isDownloading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: isDownloading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDownloading 
              ? (isDark ? Colors.white.withValues(alpha: 0.1) : AcademicTheme.primary.withValues(alpha: 0.1))
              : AcademicTheme.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDownloading 
                ? (isDark ? Colors.white.withValues(alpha: 0.2) : AcademicTheme.primary.withValues(alpha: 0.2))
                : AcademicTheme.accent.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isDownloading)
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.white : AcademicTheme.primary),
                  backgroundColor: (isDark ? Colors.white : AcademicTheme.primary).withValues(alpha: 0.1),
                ),
              ),
            AnimatedRotation(
              duration: const Duration(milliseconds: 400),
              turns: isDownloading ? 1.0 : 0,
              child: Icon(
                isDownloading ? Icons.sync_rounded : Icons.download_for_offline_rounded,
                size: 20,
                color: isDownloading 
                    ? (isDark ? Colors.white : AcademicTheme.primary)
                    : AcademicTheme.accent,
              ),
            ),
            if (isDownloading && progress > 0)
              Positioned(
                bottom: 1,
                child: Text(
                  "${(progress * 100).toInt()}%",
                  style: TextStyle(
                    fontSize: 7,
                    color: isDark ? Colors.white : AcademicTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
