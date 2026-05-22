import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'data/timetable_data.dart';
import 'SmartPDFViewerPage.dart';
import 'youtube_videos_page.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  State<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends State<BookmarksPage> {
  List<Map<String, dynamic>> _bookmarks = [];
  bool _isLoading = true;
  final Map<int, bool> _isDeleting = {};

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? bookmarksJson = prefs.getString('bookmarks');
    if (bookmarksJson != null) {
      setState(() {
        _bookmarks = List<Map<String, dynamic>>.from(jsonDecode(bookmarksJson));
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _removeBookmark(int index) async {
    setState(() {
      _isDeleting[index] = true;
    });

    // Thanos snap delay
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    setState(() {
      _bookmarks.removeAt(index);
      // We need to shift the deleting states because indices changed
      Map<int, bool> newDeleting = {};
      _isDeleting.forEach((key, value) {
        if (key > index) newDeleting[key - 1] = value;
      });
      _isDeleting.clear();
      _isDeleting.addAll(newDeleting);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bookmarks', jsonEncode(_bookmarks));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Bookmarks", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AcademicTheme.primary))
          : _bookmarks.isEmpty
              ? _buildEmptyState(isDark)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    final isPdf = bookmark['type'] == 'pdf';
                    final deleting = _isDeleting[index] ?? false;
                    
                    return _ThanosEffect(
                      isDeleting: deleting,
                      child: Card(
                        color: isDark ? AcademicTheme.darkCard : Colors.white,
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: (isPdf ? Colors.red : Colors.blue).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isPdf ? Icons.picture_as_pdf : Icons.play_circle_fill,
                              color: isPdf ? Colors.red : Colors.blue,
                              size: 28,
                            ),
                          ),
                          title: Text(
                            bookmark['title'], 
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                            )
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              bookmark['course'] ?? "General",
                              style: TextStyle(
                                color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                              ),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () => _removeBookmark(index),
                          ),
                          onTap: deleting ? null : () async {
                            if (isPdf) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SmartPDFViewerPage(
                                    title: bookmark['title'],
                                    assetPath: bookmark['path'],
                                    courseName: bookmark['course'] ?? "General",
                                  ),
                                ),
                              );
                              _loadBookmarks();
                            } else {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoPlayerPage(
                                    videoUrl: bookmark['url'],
                                    title: bookmark['title'],
                                  ),
                                ),
                              );
                              _loadBookmarks();
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bookmark_border_rounded, 
            size: 100, 
            color: isDark ? Colors.white10 : Colors.black12
          ),
          const SizedBox(height: 24),
          Text(
            "No bookmarks yet", 
            style: TextStyle(
              color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary, 
              fontSize: 20,
              fontWeight: FontWeight.bold
            )
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Save important PDF materials or videos to see them here for quick access.", 
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                fontSize: 14
              )
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanosEffect extends StatefulWidget {
  final Widget child;
  final bool isDeleting;

  const _ThanosEffect({required this.child, required this.isDeleting});

  @override
  State<_ThanosEffect> createState() => _ThanosEffectState();
}

class _ThanosEffectState extends State<_ThanosEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _disintegrate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );
    _disintegrate = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.2, 1.0, curve: Curves.easeIn)),
    );
  }

  @override
  void didUpdateWidget(_ThanosEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeleting && !oldWidget.isDeleting) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (!widget.isDeleting) return child!;
        
        return Transform.translate(
          offset: Offset(_disintegrate.value * 20, -_disintegrate.value * 10),
          child: Opacity(
            opacity: _opacity.value,
            child: Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_disintegrate.value * 0.2)
                ..scale(1.0 - (_disintegrate.value * 0.1)),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
