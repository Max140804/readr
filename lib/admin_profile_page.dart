import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/timetable_data.dart';
import 'services/notification_service.dart';
import 'utils/responsive_utils.dart';

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  bool _isDev = false;
  
  // Announcement Controllers
  final TextEditingController _annTitleController = TextEditingController();
  final TextEditingController _annBodyController = TextEditingController();
  bool _isBroadcasting = false;

  // Document Controllers
  final TextEditingController _docTitleController = TextEditingController();
  String _selectedCourse = "ECE 527";
  String _selectedDocType = "Course Material";
  String? _selectedFileName;
  String? _selectedFilePath;
  bool _isUploading = false;

  // Video Controllers
  final TextEditingController _vidTitleController = TextEditingController();
  final TextEditingController _vidUrlController = TextEditingController();

  // App Update Controllers (Dev Only)
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _externalUrlController = TextEditingController();
  String? _selectedUpdatePath;
  String? _selectedUpdateName;

  // Assignment Controllers (Admin Only)
  final TextEditingController _assignQuestionsController = TextEditingController();
  DateTime? _selectedDueDate;
  String? _selectedAssignFileName;
  String? _selectedAssignFilePath;

  final List<String> _courses = ["ECE 527", "ECE 537", "ECE 541", "ECE 539", "ECE 505", "ECE 517", "ECE 519", "ECE 529"];
  final List<String> _docTypes = ["Course Material", "Lecture Note", "Past Question", "Assignment"];

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDev = prefs.getBool('isDev') ?? false;
      _tabController = TabController(length: _isDev ? 1 : 4, vsync: this);
    });
  }

  Future<void> _pickUpdateFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['apk', 'exe', 'msi'],
    );

    if (result != null) {
      setState(() {
        _selectedUpdateName = result.files.single.name;
        _selectedUpdatePath = result.files.single.path;
      });
    }
  }

  Future<void> _pushUpdate() async {
    if (_versionController.text.isEmpty || (_selectedUpdatePath == null && _externalUrlController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Provide a file or an external URL")));
      return;
    }

    setState(() => _isUploading = true);
    try {
      String finalUrl = _externalUrlController.text;

      if (_selectedUpdatePath != null) {
        File file = File(_selectedUpdatePath!);
        String fileName = 'updates/${DateTime.now().millisecondsSinceEpoch}_$_selectedUpdateName';
        
        await _supabase.storage.from('materials').upload(
          fileName, 
          file,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: false,
          ),
        );
        finalUrl = _supabase.storage.from('materials').getPublicUrl(fileName);
      }

      await _supabase.from('app_updates').insert({
        "version": _versionController.text,
        "url": finalUrl,
        "release_notes": _notesController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update Published Successfully!"), backgroundColor: Colors.green));
      }
      _versionController.clear();
      _notesController.clear();
      _externalUrlController.clear();
      setState(() {
        _selectedUpdateName = null;
        _selectedUpdatePath = null;
      });
    } catch (e) {
      debugPrint("Update error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Update failed: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _postAssignment() async {
    if (_assignQuestionsController.text.isEmpty && _selectedAssignFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please provide questions or a PDF file")));
      return;
    }
    if (_selectedDueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a due date")));
      return;
    }

    setState(() => _isUploading = true);
    try {
      final String dueDateStr = _selectedDueDate!.toIso8601String();
      String finalUrl = "";
      String metadata = "TEXT_ASSIGNMENT|DUE:$dueDateStr";
      String title = "New Assignment";

      if (_selectedAssignFilePath != null) {
        // Upload PDF Assignment
        File file = File(_selectedAssignFilePath!);
        String fileName = 'assignments/${DateTime.now().millisecondsSinceEpoch}_$_selectedAssignFileName';
        await _supabase.storage.from('materials').upload(fileName, file);
        finalUrl = _supabase.storage.from('materials').getPublicUrl(fileName);
        metadata = "PDF_ASSIGNMENT|DUE:$dueDateStr";
        title = _selectedAssignFileName!.split('.').first;
      } else {
        // Text Assignment
        finalUrl = _assignQuestionsController.text;
        title = finalUrl.split('\n').first;
        if (title.length > 50) title = "${title.substring(0, 47)}...";
      }

      await _supabase.from('course_materials').insert({
        "course": _selectedCourse,
        "title": title,
        "type": "Assignment",
        "url": finalUrl,
        "file_name": metadata,
      });

      // Also post an announcement for it
      await _supabase.from('announcements').insert({
        'title': "New Assignment: $_selectedCourse",
        'body': "Due: ${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}\n${_selectedAssignFilePath != null ? 'PDF Attached: $title' : 'Questions: ' + (finalUrl.length > 50 ? finalUrl.substring(0, 50) + '...' : finalUrl)}",
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Assignment Posted!"), backgroundColor: Colors.green));
      }
      _assignQuestionsController.clear();
      setState(() {
        _selectedDueDate = null;
        _selectedAssignFileName = null;
        _selectedAssignFilePath = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to post assignment: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAssignmentFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedAssignFileName = result.files.single.name;
        _selectedAssignFilePath = result.files.single.path;
      });
    }
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

    setState(() => _isBroadcasting = true);

    try {
      await _supabase.from('announcements').insert({
        'title': _annTitleController.text,
        'body': _annBodyController.text,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Broadcast saved!"), backgroundColor: Colors.green));
      }
      _annTitleController.clear();
      _annBodyController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Broadcast failed: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isBroadcasting = false);
    }
  }

  Future<void> _uploadDocument() async {
    if (_docTitleController.text.isEmpty || _selectedFilePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select a file and enter a title")));
      return;
    }

    setState(() => _isUploading = true);

    try {
      File file = File(_selectedFilePath!);
      String fileName = '${DateTime.now().millisecondsSinceEpoch}_$_selectedFileName';
      await _supabase.storage.from('materials').upload(fileName, file);
      final String downloadUrl = _supabase.storage.from('materials').getPublicUrl(fileName);

      await _supabase.from('course_materials').insert({
        "title": _docTitleController.text,
        "course": _selectedCourse,
        "type": _selectedDocType,
        "url": downloadUrl,
        "file_name": _selectedFileName,
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Material uploaded!"), backgroundColor: Colors.green));
      
      setState(() {
        _docTitleController.clear();
        _selectedFileName = null;
        _selectedFilePath = null;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _addVideo() async {
    if (_vidTitleController.text.isEmpty || _vidUrlController.text.isEmpty) return;
    setState(() => _isUploading = true);

    try {
      String videoId = "";
      if (_vidUrlController.text.contains("v=")) {
        videoId = _vidUrlController.text.split("v=")[1].split("&")[0];
      } else if (_vidUrlController.text.contains("youtu.be/")) {
        videoId = _vidUrlController.text.split("youtu.be/")[1].split("?")[0];
      }

      await _supabase.from('videos').insert({
        "title": _vidTitleController.text,
        "url": _vidUrlController.text,
        "course": _selectedCourse,
        "thumbnail": videoId.isNotEmpty ? "https://img.youtube.com/vi/$videoId/0.jpg" : "",
      });

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video added!"), backgroundColor: Colors.green));
      _vidTitleController.clear();
      _vidUrlController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync failed: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_tabController.length == 0) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_isDev ? "Developer Panel" : "Admin Management", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: _isDev ? false : true,
          tabAlignment: _isDev ? TabAlignment.fill : TabAlignment.center,
          tabs: _isDev 
            ? [const Tab(icon: Icon(Icons.system_update), text: "App Update")]
            : const [
                Tab(icon: Icon(Icons.announcement), text: "Broadcast"),
                Tab(icon: Icon(Icons.upload_file), text: "Materials"),
                Tab(icon: Icon(Icons.video_library), text: "Videos"),
                Tab(icon: Icon(Icons.assignment), text: "Assignments"),
              ],
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: TabBarView(
            controller: _tabController,
            children: _isDev 
              ? [_buildUpdateTab(isDark)]
              : [
                  _buildAnnouncementTab(isDark),
                  _buildMaterialsTab(isDark),
                  _buildVideoTab(isDark),
                  _buildAssignmentTab(isDark),
                ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Post New Assignment", "Assignments will sync across all student devices."),
          const SizedBox(height: 20),
          _buildDropdown("Select Course", _selectedCourse, _courses, (v) => setState(() => _selectedCourse = v!), isDark),
          const SizedBox(height: 15),
          
          if (_selectedAssignFilePath == null) ...[
            const SizedBox(height: 8),
            _buildTextField("Assignment Questions", _assignQuestionsController, Icons.help_outline, isDark, maxLines: 6, hint: "Enter questions here. Supports Markdown."),
            const SizedBox(height: 10),
            const Center(child: Text("OR", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
            const SizedBox(height: 10),
          ],

          GestureDetector(
            onTap: _isUploading ? null : _pickAssignmentFile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : AcademicTheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: _selectedAssignFilePath != null ? Colors.green : (isDark ? Colors.white30 : AcademicTheme.primary.withValues(alpha: 0.2)),
                  width: _selectedAssignFilePath != null ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _selectedAssignFileName != null ? Icons.check_circle : Icons.picture_as_pdf, 
                    size: 30, 
                    color: _selectedAssignFileName != null ? Colors.green : (isDark ? Colors.white : AcademicTheme.primary)
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedAssignFileName ?? "Upload PDF Assignment Instead", 
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _selectedAssignFileName != null ? Colors.green : (isDark ? Colors.white : AcademicTheme.primary), 
                      fontWeight: FontWeight.w500,
                      fontSize: 12
                    )
                  ),
                  if (_selectedAssignFilePath != null)
                    TextButton(
                      onPressed: () => setState(() { _selectedAssignFileName = null; _selectedAssignFilePath = null; }),
                      child: const Text("Remove PDF", style: TextStyle(color: Colors.red, fontSize: 10)),
                    )
                ],
              ),
            ),
          ),

          const SizedBox(height: 15),
          ListTile(
            tileColor: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text(
              _selectedDueDate == null 
                  ? "Select Due Date" 
                  : "Due Date: ${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}",
              style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w500),
            ),
            trailing: Icon(Icons.calendar_month, color: AcademicTheme.primary),
            onTap: () async {
              final date = await showDatePicker(
                context: context, 
                initialDate: DateTime.now().add(const Duration(days: 7)), 
                firstDate: DateTime.now(), 
                lastDate: DateTime.now().add(const Duration(days: 365))
              );
              if (date != null) setState(() => _selectedDueDate = date);
            },
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _postAssignment,
              icon: _isUploading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white),
              label: Text(_isUploading ? "Syncing Assignment..." : "Post Assignment", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: AcademicTheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberingButton(String label, String prefix, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: () {
          final text = _assignQuestionsController.text;
          final selection = _assignQuestionsController.selection;
          final newText = text.replaceRange(selection.start, selection.end, prefix);
          _assignQuestionsController.text = newText;
          _assignQuestionsController.selection = TextSelection.collapsed(offset: selection.start + prefix.length);
        },
        backgroundColor: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.1),
      ),
    );
  }

  Widget _buildUpdateTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader("Push App Update", "Upload a new APK or provide a download link."),
          const SizedBox(height: 20),
          _buildTextField("New Version (e.g. 1.0.1+6)", _versionController, Icons.vibration, isDark),
          const SizedBox(height: 15),
          _buildTextField("External Download URL (Optional)", _externalUrlController, Icons.link, isDark, hint: "GitHub/Drive link if file > 50MB"),
          const SizedBox(height: 15),
          _buildTextField("Release Notes", _notesController, Icons.list, isDark, maxLines: 3),
          const SizedBox(height: 25),
          if (_externalUrlController.text.isEmpty) ...[
            const Text("OR UPLOAD DIRECTLY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isUploading ? null : _pickUpdateFile,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.blue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white30 : Colors.blue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(_selectedUpdateName != null ? Icons.check_circle : Icons.android, size: 40, color: Colors.blue),
                    const SizedBox(height: 10),
                    Text(_selectedUpdateName ?? "Select APK File", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _pushUpdate,
              icon: _isUploading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.publish, color: Colors.white),
              label: Text(_isUploading ? "Uploading App..." : "Publish Update", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
            ),
          ),
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
          _buildHeader("Post Global Announcement", "This will be sent to all students."),
          const SizedBox(height: 20),
          _buildTextField("Headline", _annTitleController, Icons.title, isDark),
          const SizedBox(height: 15),
          _buildTextField("Detailed Message", _annBodyController, Icons.message, isDark, maxLines: 5),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isBroadcasting ? null : _postAnnouncement,
              icon: _isBroadcasting 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white),
              label: Text(
                _isBroadcasting ? "Sending Broadcast..." : "Broadcast to Students", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
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
          _buildHeader("Upload Study Materials", "Add PDFs to specific courses and categories."),
          const SizedBox(height: 20),
          _buildTextField("Document Name", _docTitleController, Icons.description, isDark),
          const SizedBox(height: 15),
          _buildDropdown("Course", _selectedCourse, _courses, (v) => setState(() => _selectedCourse = v!), isDark),
          const SizedBox(height: 15),
          _buildDropdown("Category", _selectedDocType, _docTypes, (v) => setState(() => _selectedDocType = v!), isDark),
          const SizedBox(height: 25),
          GestureDetector(
            onTap: _isUploading ? null : _pickFile,
            child: _buildFilePickerPlaceholder(isDark),
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadDocument,
              icon: _isUploading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text(
                _isUploading ? "Uploading..." : "Finalize & Upload",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
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
              onPressed: _isUploading ? null : _addVideo,
              icon: _isUploading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.add_to_queue, color: Colors.white),
              label: Text(
                _isUploading ? "Syncing..." : "Add to Catalogue", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AcademicTheme.secondary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
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
        fillColor: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.05),
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
            border: Border.all(color: isDark ? Colors.white54 : AcademicTheme.primary.withValues(alpha: 0.3)),
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
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilePickerPlaceholder(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : AcademicTheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white30 : AcademicTheme.primary.withValues(alpha: 0.2), style: BorderStyle.solid),
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
