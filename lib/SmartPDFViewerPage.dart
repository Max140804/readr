import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'data/timetable_data.dart';
import 'assistant_page.dart';

class SmartPDFViewerPage extends StatefulWidget {
  final String title;
  final String assetPath;
  final String courseName;

  const SmartPDFViewerPage({
    super.key,
    required this.title,
    required this.assetPath,
    this.courseName = "General",
  });

  @override
  State<SmartPDFViewerPage> createState() => _SmartPDFViewerPageState();
}

class _SmartPDFViewerPageState extends State<SmartPDFViewerPage> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = "";
  bool _isBookmarked = false;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  late AnimationController _bookmarkController;

  bool get _isPdf => widget.assetPath.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    _bookmarkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _checkFile();
    _checkInitialBookmark();
  }

  @override
  void dispose() {
    _bookmarkController.dispose();
    super.dispose();
  }

  Future<void> _checkInitialBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final String? bookmarksJson = prefs.getString('bookmarks');
    if (bookmarksJson != null) {
      final List<dynamic> bookmarks = jsonDecode(bookmarksJson);
      if (mounted) {
        setState(() {
          _isBookmarked = bookmarks.any((b) => b['path'] == widget.assetPath);
          if (_isBookmarked) {
            _bookmarkController.value = 1.0;
          }
        });
      }
    }
  }

  Future<void> _checkFile() async {
    try {
      await rootBundle.load(widget.assetPath);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = "File not found: ${widget.assetPath}";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> openExternally() async {
    try {
      final byteData = await rootBundle.load(widget.assetPath);
      final tempDir = await getTemporaryDirectory();
      
      // Sanitize file name and preserve extension
      final extension = widget.assetPath.split('.').last;
      final fileName = widget.title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');
      final file = File('${tempDir.path}/$fileName.$extension');

      await file.writeAsBytes(byteData.buffer.asUint8List());
      await OpenFile.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not open external app: $e")),
        );
      }
    }
  }

  Future<void> _saveBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final String? bookmarksJson = prefs.getString('bookmarks');
    List<Map<String, dynamic>> bookmarks = [];
    if (bookmarksJson != null) {
      bookmarks = List<Map<String, dynamic>>.from(jsonDecode(bookmarksJson));
    }

    // Check if already bookmarked
    final index = bookmarks.indexWhere((b) => b['path'] == widget.assetPath);
    
    if (index != -1) {
      // Remove bookmark
      bookmarks.removeAt(index);
      await prefs.setString('bookmarks', jsonEncode(bookmarks));
      if (mounted) {
        setState(() {
          _isBookmarked = false;
          _bookmarkController.reverse();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Removed from bookmarks")),
        );
      }
      return;
    }

    // Add bookmark
    bookmarks.add({
      'title': widget.title,
      'path': widget.assetPath,
      'type': 'pdf',
      'course': widget.courseName,
      'timestamp': DateTime.now().toIso8601String(),
    });

    await prefs.setString('bookmarks', jsonEncode(bookmarks));
    if (mounted) {
      setState(() {
        _isBookmarked = true;
        _bookmarkController.forward();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Added to bookmarks")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: isDark ? AcademicTheme.darkCard : AcademicTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.2).animate(
                CurvedAnimation(
                  parent: _bookmarkController,
                  curve: Curves.elasticOut,
                ),
              ),
              child: Icon(
                _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                color: _isBookmarked ? Colors.blue : Colors.white,
              ),
            ),
            onPressed: _saveBookmark,
            tooltip: "Bookmark",
          ),
          if (_isPdf)
            IconButton(
              icon: const Icon(Icons.zoom_in),
              onPressed: () => _pdfViewerController.zoomLevel = (_pdfViewerController.zoomLevel + 0.5),
              tooltip: "Zoom In",
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: openExternally,
            tooltip: "Open in External App",
          )
        ],
      ),
      body: Stack(
        children: [
          if (!_hasError && _isPdf)
            widget.assetPath.startsWith('assets/')
                ? SfPdfViewer.asset(
                    widget.assetPath,
                    controller: _pdfViewerController,
                    onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                      setState(() => _isLoading = false);
                    },
                    onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                      setState(() {
                        _hasError = true;
                        _errorMessage = details.description;
                        _isLoading = false;
                      });
                    },
                  )
                : SfPdfViewer.file(
                    File(widget.assetPath),
                    controller: _pdfViewerController,
                    onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                      setState(() => _isLoading = false);
                    },
                    onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                      setState(() {
                        _hasError = true;
                        _errorMessage = details.description;
                        _isLoading = false;
                      });
                    },
                  )
          else if (!_hasError && !_isPdf)
            _buildUnsupportedUI(),
          
          if (_isLoading && !_hasError && _isPdf)
            Center(
              child: CircularProgressIndicator(color: primaryColor),
            ),

          if (_hasError)
            _buildErrorUI(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AssistantPage(
                initialPrompt: "I am currently reading '${widget.title}' for the course '${widget.courseName}'. Can you help me understand the key concepts or answer questions I might have about this topic?",
              ),
            ),
          );
        },
        label: const Text("Ask AI"),
        icon: const Icon(Icons.auto_awesome),
        backgroundColor: AcademicTheme.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildUnsupportedUI() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final extension = widget.assetPath.split('.').last.toUpperCase();
    final primaryColor = theme.colorScheme.primary;
    
    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            extension == 'DOCX' || extension == 'DOC' 
                ? Icons.description 
                : Icons.insert_drive_file, 
            size: 80, 
            color: primaryColor
          ),
          const SizedBox(height: 24),
          Text(
            "$extension File",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            "This $extension file cannot be viewed directly inside the app. Please open it with an external document viewer.",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: openExternally,
            icon: const Icon(Icons.launch),
            label: const Text("Open in External App"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorUI() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    
    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_outlined, size: 80, color: Colors.redAccent),
          const SizedBox(height: 24),
          Text(
            "Couldn't Open PDF",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage.isNotEmpty ? _errorMessage : "Something went wrong while loading the document.",
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: openExternally,
            icon: const Icon(Icons.launch),
            label: const Text("Try External App"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: isDark ? Colors.black : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
