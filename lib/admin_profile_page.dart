import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'data/timetable_data.dart';
import 'services/notification_service.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Announcement Controllers
  final TextEditingController _annTitleController = TextEditingController();
  final TextEditingController _annBodyController = TextEditingController();

  // Document Controllers
  final TextEditingController _docTitleController = TextEditingController();
  String _selectedCourse = "ECE 527";
  String _selectedDocType = "Course Material";
  String? _selectedFileName;
  String? _selectedFilePath;

  // Video Controllers
  final TextEditingController _vidTitleController = TextEditingController();
  final TextEditingController _vidUrlController = TextEditingController();

  final List<String> _courses = ["ECE 527", "ECE 537", "ECE 541", "ECE 539", "ECE 505", "ECE 517", "ECE 529", "ECE 531", "ECE 535"];
  final List<String> _docTypes = ["Course Material", "Past Question", "Assignment"];

  List<dynamic> _existingDocs = [];
  List<dynamic> _existingVideos = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadExistingContent();
  }

  Future<void> _loadExistingContent() async {
    final prefs = await SharedPreferences.getInstance();
    final String docKey = 'custom_docs_${_selectedCourse.replaceAll(" ", "_")}';
    final String vidKey = 'custom_videos_${_selectedCourse.replaceAll(" ", "_")}';

    setState(() {
      _existingDocs = jsonDecode(prefs.getString(docKey) ?? '[]');
      _existingVideos = jsonDecode(prefs.getString(vidKey) ?? '[]');
    });
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx'],
    );

    if (result != null) {
      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path;
        if (_docTitleController.text.isEmpty) {
          _docTitleController.text = _selectedFileName!.split('.').first;
        }
      });
    }
  }

  Future<void> _postAnnouncement() async {
    if (_annTitleController.text.isEmpty || _annBodyController.text.isEmpty) return;

    // Simulate Global Sync by triggering notification
    await NotificationService().showNotificationNow(
      "📢 ${_annTitleController.text}",
      _annBodyController.text,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Announcement published and synced!")),
    );
    _annTitleController.clear();
    _annBodyController.clear();
  }

  Future<void> _uploadDocument() async {
    if (_docTitleController.text.isEmpty || _selectedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a file and enter a title")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final String key = 'custom_docs_${_selectedCourse.replaceAll(" ", "_")}';
    
    List<dynamic> docs = jsonDecode(prefs.getString(key) ?? '[]');
    docs.add({
      "title": _docTitleController.text,
      "type": _selectedDocType,
      "path": _selectedFilePath, // In a real app, you'd upload this to a server
      "date": DateTime.now().toIso8601String(),
    });

    await prefs.setString(key, jsonEncode(docs));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Document synced to $_selectedCourse")),
    );
    
    setState(() {
      _docTitleController.clear();
      _selectedFileName = null;
      _selectedFilePath = null;
    });
    _loadExistingContent();
  }

  Future<void> _deleteDocument(int index) async {
    final confirm = await _showDeleteConfirmation();
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final String key = 'custom_docs_${_selectedCourse.replaceAll(" ", "_")}';
    
    List<dynamic> docs = jsonDecode(prefs.getString(key) ?? '[]');
    docs.removeAt(index);
    await prefs.setString(key, jsonEncode(docs));
    
    _loadExistingContent();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Document deleted")));
    }
  }

  Future<void> _addVideo() async {
    if (_vidTitleController.text.isEmpty || _vidUrlController.text.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final String key = 'custom_videos_${_selectedCourse.replaceAll(" ", "_")}';
    
    List<dynamic> vids = jsonDecode(prefs.getString(key) ?? '[]');
    
    // Extract YT ID for thumbnail
    String videoId = "";
    if (_vidUrlController.text.contains("v=")) {
      videoId = _vidUrlController.text.split("v=")[1].split("&")[0];
    } else if (_vidUrlController.text.contains("youtu.be/")) {
      videoId = _vidUrlController.text.split("youtu.be/")[1].split("?")[0];
    }

    vids.add({
      "title": _vidTitleController.text,
      "url": _vidUrlController.text,
      "thumbnail": videoId.isNotEmpty ? "https://img.youtube.com/vi/$videoId/0.jpg" : "",
    });

    await prefs.setString(key, jsonEncode(vids));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Video catalogue synced successfully")),
    );
    _vidTitleController.clear();
    _vidUrlController.clear();
    _loadExistingContent();
  }

  Future<void> _deleteVideo(int index) async {
    final confirm = await _showDeleteConfirmation();
    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    final String key = 'custom_videos_${_selectedCourse.replaceAll(" ", "_")}';
    
    List<dynamic> vids = jsonDecode(prefs.getString(key) ?? '[]');
    vids.removeAt(index);
    await prefs.setString(key, jsonEncode(vids));
    
    _loadExistingContent();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video removed from catalogue")));
    }
  }

  Future<bool?> _showDeleteConfirmation() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: const Text("Are you sure you want to delete this item? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Management", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.announcement), text: "Broadcast"),
            Tab(icon: Icon(Icons.upload_file), text: "Materials"),
            Tab(icon: Icon(Icons.video_library), text: "Videos"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnnouncementTab(isDark),
          _buildMaterialsTab(isDark),
          _buildVideoTab(isDark),
        ],
      ),
    );
  }

  Widget _buildAnnouncementTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Post Global Announcement", "This will be synced to all student devices."),
          const SizedBox(height: 20),
          _buildTextField("Headline", _annTitleController, Icons.title, isDark),
          const SizedBox(height: 15),
          _buildTextField("Detailed Message", _annBodyController, Icons.message, isDark, maxLines: 5),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _postAnnouncement,
              icon: const Icon(Icons.send, color: Colors.white),
              label: const Text("Broadcast to Students", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AcademicTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialsTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Upload Study Materials", "Add PDFs or Docx files to specific courses."),
          const SizedBox(height: 20),
          _buildTextField("Document Name", _docTitleController, Icons.description, isDark),
          const SizedBox(height: 15),
          _buildDropdown("Course", _selectedCourse, _courses, (v) => setState(() => _selectedCourse = v!), isDark),
          const SizedBox(height: 15),
          _buildDropdown("Category", _selectedDocType, _docTypes, (v) => setState(() => _selectedDocType = v!), isDark),
          const SizedBox(height: 25),
          GestureDetector(
            onTap: _pickFile,
            child: _buildFilePickerPlaceholder(isDark),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _uploadDocument,
              icon: const Icon(Icons.cloud_upload, color: Colors.white),
              label: const Text("Finalize & Sync Material", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AcademicTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
          const SizedBox(height: 30),
          _buildExistingItemsList("Manage Materials for $_selectedCourse", _existingDocs, _deleteDocument, isDark),
        ],
      ),
    );
  }

  Widget _buildVideoTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Video Catalogue", "Add YouTube lectures to the video library."),
          const SizedBox(height: 20),
          _buildTextField("Video Title", _vidTitleController, Icons.video_collection, isDark),
          const SizedBox(height: 15),
          _buildTextField("YouTube Link", _vidUrlController, Icons.link, isDark, hint: "https://youtu.be/..."),
          const SizedBox(height: 15),
          _buildDropdown("Assign to Course", _selectedCourse, _courses, (v) => setState(() => _selectedCourse = v!), isDark),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _addVideo,
              icon: const Icon(Icons.add_to_queue, color: Colors.white),
              label: const Text("Add to Catalogue & Sync", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AcademicTheme.secondary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
          const SizedBox(height: 30),
          _buildExistingItemsList("Manage Videos for $_selectedCourse", _existingVideos, _deleteVideo, isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(String title, String sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AcademicTheme.primary)),
        const SizedBox(height: 5),
        Text(sub, style: const TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, IconData icon, bool isDark, {int maxLines = 1, String? hint}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: isDark ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: isDark ? Colors.white : AcademicTheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: isDark ? Colors.white30 : Colors.grey.shade400)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: AcademicTheme.primary, width: 2)),
        filled: true,
        fillColor: isDark ? Colors.white10 : Colors.grey.withOpacity(0.05),
      ),
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, Function(String?) onChanged, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AcademicTheme.primary)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white54 : AcademicTheme.primary.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(15),
            color: isDark ? Colors.white10 : Colors.white,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: isDark ? AcademicTheme.darkCard : Colors.white,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
              onChanged: (val) {
                onChanged(val);
                _loadExistingContent();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExistingItemsList(String title, List<dynamic> items, Function(int) onDelete, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AcademicTheme.primary)),
        const SizedBox(height: 10),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text("No custom items added yet.", style: TextStyle(color: Colors.grey))),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                color: isDark ? Colors.white10 : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    item.containsKey('url') ? Icons.play_circle : Icons.description,
                    color: item.containsKey('url') ? Colors.red : Colors.blue,
                  ),
                  title: Text(item['title'] ?? 'Untitled', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                  subtitle: Text(item['type'] ?? (item.containsKey('url') ? 'YouTube Video' : 'File'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => onDelete(index),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilePickerPlaceholder(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : AcademicTheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white30 : AcademicTheme.primary.withOpacity(0.2), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(
            _selectedFileName != null ? Icons.check_circle : Icons.insert_drive_file, 
            size: 40, 
            color: _selectedFileName != null ? Colors.green : (isDark ? Colors.white : AcademicTheme.primary)
          ),
          const SizedBox(height: 10),
          Text(
            _selectedFileName ?? "Tap to select PDF/Docx from device", 
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : AcademicTheme.primary, 
              fontWeight: FontWeight.w500
            )
          ),
        ],
      ),
    );
  }
}
