import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'connectivity_service.dart';
import '../data/course_data.dart';

class MaterialSyncService extends ChangeNotifier {
  static final MaterialSyncService _instance = MaterialSyncService._internal();
  factory MaterialSyncService() => _instance;
  MaterialSyncService._internal() {
    // Listen for connectivity changes to auto-resume sync
    ConnectivityService().connectivityStream.listen((connected) {
      if (connected) {
        syncAllMaterials();
      }
    });
  }

  bool _isSyncing = false;
  double _syncProgress = 0.0;
  int _totalFiles = 0;
  int _downloadedFiles = 0;

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  int get totalFiles => _totalFiles;
  int get downloadedFiles => _downloadedFiles;

  static String getFileName(String url) {
    try {
      final uri = Uri.parse(url);
      final decodedPath = Uri.decodeFull(uri.path);
      if (decodedPath.contains('public/materials/')) {
        return decodedPath.split('public/materials/').last.replaceAll('/', '_');
      }
      return decodedPath.split('/').last;
    } catch (_) {
      return url.split('/').last.split('?').first;
    }
  }

  String? _documentsPath;
  List<String> _cachedUrls = [];

  bool isCached(String url) => _cachedUrls.contains(url);

  Future<void> init() async {
    final directory = await getApplicationDocumentsDirectory();
    _documentsPath = directory.path;
    final prefs = await SharedPreferences.getInstance();
    _cachedUrls = prefs.getStringList('cached_pdfs') ?? [];
    notifyListeners();
  }

  File? getCachedFile(String url) {
    if (_documentsPath == null || !isCached(url)) return null;
    final fileName = getFileName(url);
    final file = File('$_documentsPath/$fileName');
    return file.existsSync() ? file : null;
  }

  Future<void> syncAllMaterials() async {
    if (_isSyncing) return;
    
    if (_documentsPath == null) await init();
    
    // Check connectivity first
    if (!ConnectivityService().isConnected) {
      debugPrint("Skipping sync: No internet connection");
      return;
    }
    
    final prefs = await SharedPreferences.getInstance();
    // If we want to strictly only do this once ever:
    // if (prefs.getBool('initial_sync_complete') ?? false) return;
    
    _isSyncing = true;
    notifyListeners();
    
    try {
      final courses = CourseData.getCourses();
      List<String> allUrls = [];

      for (var course in courses) {
        if (course['pdfs'] != null) {
          for (var pdf in course['pdfs']) {
            if (pdf['path'] != null && pdf['path'].toString().startsWith('http')) {
              allUrls.add(pdf['path']);
            }
          }
        }
        if (course['pastQuestions'] != null) {
          for (var pq in course['pastQuestions']) {
            if (pq['path'] != null && pq['path'].toString().startsWith('http')) {
              allUrls.add(pq['path']);
            }
          }
        }
      }

      _totalFiles = allUrls.length;
      _downloadedFiles = 0;
      _syncProgress = 0.0;
      notifyListeners();

      bool changed = false;

      for (String url in allUrls) {
        if (!_isSyncing) break; // Allow cancellation if we add it later
        final fileName = getFileName(url);
        final file = File('$_documentsPath/$fileName');

        if (await file.exists()) {
          _downloadedFiles++;
          if (!_cachedUrls.contains(url)) {
            _cachedUrls.add(url);
            changed = true;
          }
        } else {
          try {
            final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
            if (response.statusCode == 200) {
              await file.writeAsBytes(response.bodyBytes);
              _downloadedFiles++;
              if (!_cachedUrls.contains(url)) {
                _cachedUrls.add(url);
                changed = true;
              }
              debugPrint("Synced: $fileName");
            }
          } catch (e) {
            debugPrint("Failed to sync $url: $e");
          }
        }
        
        _syncProgress = _totalFiles > 0 ? _downloadedFiles / _totalFiles : 1.0;
        notifyListeners();
        if (changed) {
          await prefs.setStringList('cached_pdfs', _cachedUrls);
          changed = false;
        }
      }
      
      await prefs.setBool('initial_sync_complete', true);
      
    } catch (e) {
      debugPrint("Error during material sync: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (_documentsPath == null) await init();

    for (String url in _cachedUrls) {
      final fileName = getFileName(url);
      final file = File('$_documentsPath/$fileName');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint("Error deleting file $fileName: $e");
        }
      }
    }

    await prefs.remove('cached_pdfs');
    _cachedUrls = [];
    await prefs.remove('initial_sync_complete');
    _downloadedFiles = 0;
    _syncProgress = 0.0;
    notifyListeners();
  }

  Future<double> getCacheSize() async {
    final directory = await getApplicationDocumentsDirectory();
    double totalSize = 0;
    try {
      if (await directory.exists()) {
        await for (var file in directory.list(recursive: true, followLinks: false)) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }
    } catch (e) {
      debugPrint("Error calculating cache size: $e");
    }
    return totalSize / (1024 * 1024); // Size in MB
  }
}
