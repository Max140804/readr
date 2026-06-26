import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data/timetable_data.dart';
import 'services/activity_service.dart';

import 'services/material_sync_service.dart';
import 'SmartPDFViewerPage.dart';
import 'utils/responsive_utils.dart';

class PDFListPage extends StatefulWidget {
  final String courseName;
  final List pdfs;
  final String? titleOverride;
  final bool isAdmin;

  const PDFListPage({
    super.key,
    required this.courseName,
    required this.pdfs,
    this.titleOverride,
    this.isAdmin = false,
  });

  @override
  State<PDFListPage> createState() => _PDFListPageState();
}

class _PDFListPageState extends State<PDFListPage> {
  late List filteredPdfs;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  final _supabase = Supabase.instance.client;
  List<String> _cachedPaths = [];
  final Map<String, bool> _isDownloadingMap = {};
  final Map<String, double> _downloadProgressMap = {};

  @override
  void initState() {
    super.initState();
    filteredPdfs = widget.pdfs;
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

  String _getFileName(String url) {
    try {
      final uri = Uri.parse(url);
      // Decode the path to handle spaces and special characters consistently
      final decodedPath = Uri.decodeFull(uri.path);
      if (decodedPath.contains('public/materials/')) {
        // Extract the part after 'public/materials/' and flatten it into a filename
        return decodedPath.split('public/materials/').last.replaceAll('/', '_');
      }
      return decodedPath.split('/').last;
    } catch (_) {
      return url.split('/').last.split('?').first;
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
      final response = await client.send(request).timeout(const Duration(seconds: 30));

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
        final fileName = _getFileName(url);
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
  void didUpdateWidget(PDFListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pdfs != oldWidget.pdfs) {
      filteredPdfs = widget.pdfs;
    }
  }

  void filterSearch(String query) {
    setState(() {
      filteredPdfs = widget.pdfs
          .where((pdf) => pdf["title"].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _onRefresh() async {
    try {
      final type = widget.titleOverride == "Lecture Notes" ? "Lecture Note" : "Course Material";
      final response = await _supabase
          .from('course_materials')
          .select()
          .eq('course', widget.courseName)
          .eq('type', type);
      
      final List firestorePdfs = (response as List).map((data) => {
        "id": data['id'],
        "title": data['title'], 
        "path": data['url'],
        "isDynamic": true,
        "topic": data['topic'] ?? "Other"
      }).toList();

      final staticPdfs = widget.pdfs.where((p) => p['isDynamic'] != true).toList();
      
      setState(() {
        final List allPdfs = [...staticPdfs];
        for (var item in firestorePdfs) {
          if (!allPdfs.any((p) => p['path'] == item['path'])) {
            allPdfs.add(item);
          }
        }
        filteredPdfs = allPdfs;
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

  Future<void> _deleteMaterial(Map item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Material?"),
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Material deleted")));
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

  Map<String, List<Map<String, dynamic>>> _groupPdfsByTopic() {
    Map<String, List<Map<String, dynamic>>> groups = {};
    for (var pdf in filteredPdfs) {
      String topic = pdf['topic'] ?? "General";
      if (!groups.containsKey(topic)) {
        groups[topic] = [];
      }
      groups[topic]!.add(Map<String, dynamic>.from(pdf));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBarColor = isDark ? AcademicTheme.darkCard : AcademicTheme.primary;
    final titleColor = isDark ? AcademicTheme.darkPrimary : Colors.white;

    final displayTitle = widget.titleOverride ?? "${widget.courseName} Materials";
    final groupedPdfs = _groupPdfsByTopic();
    final topics = groupedPdfs.keys.toList();

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
                  hintText: "Search materials...",
                  hintStyle: TextStyle(color: titleColor.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: titleColor),
                onChanged: filterSearch,
              )
            : Text(
                displayTitle, 
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)
              ),
        centerTitle: true,
        iconTheme: IconThemeData(color: titleColor),
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search, color: titleColor),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  filteredPdfs = widget.pdfs;
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
            child: filteredPdfs.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_stories_outlined, size: 60, color: isDark ? Colors.grey[700] : Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            isSearching ? "No matching materials found." : "No materials available here yet.",
                            style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
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
                    itemCount: topics.length,
                    itemBuilder: (context, topicIndex) {
                      final topic = topics[topicIndex];
                      final topicPdfs = groupedPdfs[topic]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 8, bottom: 12),
                            child: Text(
                              topic.toUpperCase(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AcademicTheme.darkAccent : AcademicTheme.primary,
                                letterSpacing: 1.2,
                                shadows: isDark ? null : [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.1),
                                    offset: const Offset(0, 1),
                                    blurRadius: 1,
                                  )
                                ],
                              ),
                            ),
                          ),
                          ...topicPdfs.map((item) {
                            final path = item["path"] as String? ?? "";
                            final lowerPath = path.toLowerCase();
                            final isPdf = lowerPath.endsWith('.pdf');
                            final isDocx = lowerPath.endsWith('.docx') || lowerPath.endsWith('.doc');
                            final isImage = lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg') || 
                                          lowerPath.endsWith('.png') || lowerPath.endsWith('.webp');

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
                                tileColor: theme.cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AcademicTheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isPdf ? Icons.picture_as_pdf : 
                                    (isDocx ? Icons.description : 
                                    (isImage ? Icons.image : Icons.insert_drive_file)),
                                    color: isPdf ? Colors.red : 
                                           (isDocx ? Colors.blue : 
                                           (isImage ? Colors.green : Colors.orange)),
                                  ),
                                ),
                                title: Text(
                                  item["title"],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                                  ),
                                ),
                                subtitle: ListenableBuilder(
                                  listenable: MaterialSyncService(),
                                  builder: (context, _) {
                                    final syncService = MaterialSyncService();
                                    final isCached = _cachedPaths.contains(path);
                                    
                                    if (isCached) {
                                      return Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, size: 12, color: Colors.green),
                                          const SizedBox(width: 4),
                                          Text("Available Offline", style: TextStyle(color: isDark ? Colors.green[300] : Colors.green[700], fontSize: 11)),
                                        ],
                                      );
                                    }

                                    if (syncService.isSyncing) {
                                      return Row(
                                        children: [
                                          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.orange))),
                                          const SizedBox(width: 6),
                                          Text("Syncing...", style: TextStyle(color: Colors.orange[700], fontSize: 11)),
                                        ],
                                      );
                                    }

                                    return Text(
                                      isPdf ? "Tap to open PDF" : 
                                      (isDocx ? "Tap to open Document" : 
                                      (isImage ? "Tap to view Image" : "Tap to open File")),
                                      style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
                                    );
                                  },
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.isAdmin && item['id'] != null)
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        onPressed: () => _deleteMaterial(item),
                                      ),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  // Save to recent activity
                                  await ActivityService().trackActivity(
                                    title: item["title"],
                                    subtitle: "Continue reading from ${widget.courseName}",
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
                          }).toList(),
                          const SizedBox(height: 8),
                        ],
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
