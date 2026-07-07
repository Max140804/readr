import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data/timetable_data.dart';
import 'services/material_sync_service.dart';
import 'services/sync_service.dart';
import 'assistant_page.dart';
import 'utils/responsive_utils.dart';

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
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  late AnimationController _bookmarkController;

  bool get _isPdf {
    final path = widget.assetPath.toLowerCase().split('?').first;
    return path.endsWith('.pdf');
  }

  bool get _isImage {
    final path = widget.assetPath.toLowerCase().split('?').first;
    return path.endsWith('.jpg') || 
           path.endsWith('.jpeg') || 
           path.endsWith('.png') || 
           path.endsWith('.gif') ||
           path.endsWith('.webp');
  }

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
    if (widget.assetPath.startsWith('http')) {
      // Check if we have a cached version
      final cachedFile = await _getCachedFile(widget.assetPath);
      if (await cachedFile.exists()) {
        if (mounted) {
          setState(() {
            _localCachedPath = cachedFile.path;
            _isLoading = false;
          });
        }
        debugPrint("Loading from cache: ${cachedFile.path}");
        return;
      }
      
      // If not cached, we need to download it
      debugPrint("Not in cache, downloading: ${widget.assetPath}");
      _downloadAndCache(widget.assetPath);
      return;
    }

    if (widget.assetPath.startsWith('assets/')) {
      if (widget.assetPath.toLowerCase().endsWith('.docx') || widget.assetPath.toLowerCase().endsWith('.doc')) {
        try {
          final byteData = await rootBundle.load(widget.assetPath);
          final directory = await getTemporaryDirectory();
          final fileName = widget.assetPath.split('/').last;
          final file = File('${directory.path}/$fileName');
          await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
          if (mounted) {
            setState(() {
              _localCachedPath = file.path;
              _isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = "Error loading document: $e";
              _isLoading = false;
            });
          }
        }
        return;
      }
    }

    try {
      await rootBundle.load(widget.assetPath);
      if (mounted) setState(() => _isLoading = false);
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

  String? _localCachedPath;

  String _getFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final decodedPath = Uri.decodeFull(uri.path);
      // Ensure we use the exact same filename logic as PDFListPage
      if (decodedPath.contains('public/materials/')) {
        return decodedPath.split('public/materials/').last.replaceAll('/', '_');
      }
      return decodedPath.split('/').last;
    } catch (_) {
      return url.split('/').last.split('?').first;
    }
  }

  Future<File> _getCachedFile(String url) async {
    final directory = await getApplicationDocumentsDirectory();
    final fileName = _getFileName(url);
    return File('${directory.path}/$fileName');
  }

  Future<void> _downloadAndCache(String url) async {
    if (_isDownloading) return;
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
    }

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
              _downloadProgress = received / total;
            });
          }
        }

        final file = await _getCachedFile(url);
        await file.writeAsBytes(bytes);
        
        // Save to cache registry
        final prefs = await SharedPreferences.getInstance();
        final List<String> cachedUrls = prefs.getStringList('cached_pdfs') ?? [];
        if (!cachedUrls.contains(url)) {
          cachedUrls.add(url);
          await prefs.setStringList('cached_pdfs', cachedUrls);
        }

        if (mounted) {
          setState(() {
            _localCachedPath = file.path;
            _isLoading = false;
            _isDownloading = false;
            _downloadProgress = 0.0;
          });
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.offline_pin, color: Colors.white),
                  SizedBox(width: 12),
                  Text("Saved for offline reading"),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception("Failed to download file: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
          if (_localCachedPath == null) {
            _hasError = true;
            _errorMessage = "Failed to load document. Please check your connection or try again.";
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Download failed: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> openExternally() async {
    try {
      if (_localCachedPath != null) {
        await OpenFile.open(_localCachedPath!);
        return;
      }

      if (widget.assetPath.startsWith('http')) {
        final uri = Uri.parse(widget.assetPath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error opening file: $e")),
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
      SyncService().pushToCloud();
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
    SyncService().pushToCloud();
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

  Future<void> _saveToPublicDownloads() async {
    if (_localCachedPath == null) {
      await _downloadAndCache(widget.assetPath);
    }
    
    if (_localCachedPath == null) return;

    try {
      bool hasPermission = false;
      if (Platform.isAndroid) {
        // Check for permission based on Android version
        // For Android 13+ (API 33), we don't necessarily need MANAGE_EXTERNAL_STORAGE for Downloads
        // but Permission.storage is the standard way for flutter
        final status = await Permission.storage.request();
        hasPermission = status.isGranted;
      } else {
        hasPermission = true;
      }

      if (!hasPermission && Platform.isAndroid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Storage permission denied. Cannot export file.")),
          );
        }
        return;
      }

      // Try to get public downloads directory
      String? downloadsPath;
      if (Platform.isAndroid) {
        downloadsPath = '/storage/emulated/0/Download/Readr';
        final dir = Directory(downloadsPath);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
      } else {
        final dir = await getDownloadsDirectory();
        downloadsPath = dir?.path;
      }

      if (downloadsPath == null) throw Exception("Could not find downloads directory");

      final fileName = widget.assetPath.split('/').last.split('?').first;
      final savedFile = File('$downloadsPath/$fileName');
      await File(_localCachedPath!).copy(savedFile.path);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text("Saved to $downloadsPath/$fileName")),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving to storage: $e"), backgroundColor: Colors.red),
        );
      }
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
                color: _isBookmarked ? Colors.amber : Colors.white,
              ),
            ),
            onPressed: () {
              HapticFeedback.mediumImpact();
              _saveBookmark();
            },
            tooltip: "Bookmark",
          ),
          ListenableBuilder(
            listenable: MaterialSyncService(),
            builder: (context, _) {
              final syncService = MaterialSyncService();
              if (!syncService.isSyncing) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                width: 24,
                height: 24,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              );
            },
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
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Stack(
            children: [
              if (!_hasError && _isPdf)
                _localCachedPath != null
                    ? SfPdfViewer.file(
                        File(_localCachedPath!),
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
                    : widget.assetPath.startsWith('assets/')
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
                        : SfPdfViewer.network(
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
              else if (!_hasError && _isImage)
                Center(
                  child: InteractiveViewer(
                    child: _localCachedPath != null
                        ? Image.file(File(_localCachedPath!), 
                            errorBuilder: (_, __, ___) => _buildErrorUI())
                        : widget.assetPath.startsWith('assets/')
                            ? Image.asset(widget.assetPath,
                                errorBuilder: (_, __, ___) => _buildErrorUI())
                            : Image.network(widget.assetPath,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(child: CircularProgressIndicator());
                                },
                                errorBuilder: (_, __, ___) => _buildErrorUI()),
                  ),
                )
              else if (!_hasError && !_isPdf && !_isImage && !_isLoading)
                _buildUnsupportedUI(),
              
              if (_isLoading && !_hasError)
                Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),

              if (_hasError)
                _buildErrorUI(),
            ],
          ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [AcademicTheme.primary, AcademicTheme.primary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AcademicTheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () async {
            HapticFeedback.mediumImpact();
            // Show a premium processing indicator
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Text(
                        "Analyzing '${widget.title}'...",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                backgroundColor: AcademicTheme.primary,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 2),
              ),
            );

            Uint8List? bytes;
            try {
              if (_localCachedPath != null) {
                bytes = await File(_localCachedPath!).readAsBytes();
              } else if (widget.assetPath.startsWith('assets/')) {
                final data = await rootBundle.load(widget.assetPath);
                bytes = data.buffer.asUint8List();
              } else if (widget.assetPath.startsWith('http')) {
                final response = await http.get(Uri.parse(widget.assetPath));
                if (response.statusCode == 200) {
                  bytes = response.bodyBytes;
                }
              }
            } catch (e) {
              debugPrint("Error reading PDF bytes: $e");
            }

            if (!mounted) return;

            if (bytes == null) {
               ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Could not read document for AI analysis. Proceeding with text only.")),
              );
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AssistantPage(
                  pdfBytes: bytes,
                  initialPrompt: "I am currently reading '${widget.title}' for the course '${widget.courseName}'. Can you identify the main topic and help me understand it?",
                ),
              ),
            );
          },
          label: const Text("Ask AI Assistant", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          icon: const Icon(Icons.auto_awesome),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildOfflineOptions(BuildContext context, bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.offline_pin, color: Colors.green, size: 28),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Offline Ready",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      ),
                      Text(
                        "This file is stored on your device",
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildOptionTile(
              icon: Icons.folder_shared_outlined,
              title: "Export to Phone Storage",
              subtitle: "Save a copy to your Downloads folder",
              color: AcademicTheme.accent,
              onTap: () {
                Navigator.pop(context);
                _saveToPublicDownloads();
              },
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.launch_rounded,
              title: "Open in External App",
              subtitle: "View using system default viewer",
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                openExternally();
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.03),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupportedUI() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final extension = widget.assetPath.split('.').last.toUpperCase();
    final primaryColor = theme.colorScheme.primary;
    final isDocx = extension == 'DOCX' || extension == 'DOC';
    
    // Use Google Docs Viewer for high fidelity if it's a network URL
    final String gViewUrl = "https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.assetPath)}";

    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isDocx && widget.assetPath.startsWith('http'))
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(gViewUrl)),
                initialSettings: InAppWebViewSettings(
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  supportZoom: true,
                  builtInZoomControls: true,
                ),
                onLoadStop: (controller, url) {
                  setState(() => _isLoading = false);
                },
              ),
            )
          else ...[
            const SizedBox(height: 40),
            Icon(
              isDocx ? Icons.description : Icons.insert_drive_file,
              size: 80,
              color: primaryColor,
            ),
            const SizedBox(height: 24),
            Text(
              "$extension Document",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                isDocx 
                  ? "To preserve full styling, headers, and layout, it's best to open this document in a dedicated viewer."
                  : "This file type can be viewed better with an external app.",
                textAlign: TextAlign.center,
                style: TextStyle(color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  openExternally();
                },
                icon: const Icon(Icons.launch_rounded),
                label: Text(
                  "Open in ${isDocx ? 'Word / Office' : 'External App'}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const Spacer(),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorUI() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      color: theme.scaffoldBackgroundColor,
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.redAccent),
          ),
          const SizedBox(height: 24),
          Text(
            "Offline Access Required",
            style: TextStyle(
              fontSize: 24, 
              fontWeight: FontWeight.bold, 
              color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _errorMessage.contains("Offline") 
              ? "This document hasn't been downloaded for offline use yet. Please connect to the internet to download it."
              : _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary
            ),
          ),
          const SizedBox(height: 40),
          if (_errorMessage.contains("Offline"))
            Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [AcademicTheme.primary, AcademicTheme.primary.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AcademicTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () => _downloadAndCache(widget.assetPath),
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text(
                  "Download for Offline Access",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text("Go Back"),
            style: TextButton.styleFrom(
              foregroundColor: AcademicTheme.accent,
            ),
          ),
        ],
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
    return GestureDetector(
      onTap: isDownloading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDownloading 
              ? Colors.white.withValues(alpha: 0.1) 
              : AcademicTheme.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDownloading 
                ? Colors.white.withValues(alpha: 0.2) 
                : AcademicTheme.accent.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isDownloading)
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 3,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            AnimatedRotation(
              duration: const Duration(milliseconds: 400),
              turns: isDownloading ? 1.0 : 0,
              child: Icon(
                isDownloading ? Icons.sync_rounded : Icons.downloading_rounded,
                size: 22,
                color: Colors.white,
              ),
            ),
            if (isDownloading && progress > 0)
              Positioned(
                bottom: 2,
                child: Text(
                  "${(progress * 100).toInt()}%",
                  style: const TextStyle(
                    fontSize: 8,
                    color: Colors.white,
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
