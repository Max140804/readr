import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'data/timetable_data.dart';
import 'services/activity_service.dart';
import 'utils/responsive_utils.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class AssistantPage extends StatefulWidget {
  final String? initialPrompt;
  final Uint8List? pdfBytes;
  final String? youtubeUrl;
  
  const AssistantPage({
    super.key, 
    this.initialPrompt,
    this.pdfBytes,
    this.youtubeUrl,
  });

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, String>> messages = [];
  List<Map<String, dynamic>> _sessions = [];
  String? _currentSessionId;
  bool isLoading = false;
  String? _errorMessage;
  String _activeKey = "";
  
  // For file attachments and context
  Uint8List? _attachedFileBytes;
  String? _attachedFileName;
  String? _extractedContext;

  @override
  void initState() {
    super.initState();
    _initConfiguration();
  }

  void _initConfiguration() async {
    _activeKey = dotenv.env['GROQ_API_KEY']?.trim() ?? "";
    
    if (widget.pdfBytes != null) {
      _attachedFileBytes = widget.pdfBytes;
      _attachedFileName = "Current Document.pdf";
      await _extractContextFromActiveFile();
    }

    await _loadSessions();
    
    if (widget.initialPrompt != null && messages.isEmpty) {
      sendMessage(widget.initialPrompt!);
    }
  }

  Future<void> _extractContextFromActiveFile() async {
    if (_attachedFileBytes == null) return;

    try {
      String? text;
      if (_attachedFileName?.toLowerCase().endsWith('.pdf') ?? false) {
        final PdfDocument document = PdfDocument(inputBytes: _attachedFileBytes);
        text = PdfTextExtractor(document).extractText();
        document.dispose();
      } else if (_attachedFileName?.toLowerCase().endsWith('.txt') ?? false) {
        text = utf8.decode(_attachedFileBytes!);
      }

      if (text != null && text.trim().isNotEmpty) {
        setState(() {
          // Limit to ~2500-3000 tokens (10k chars) to be safe and efficient
          _extractedContext = text!.length > 10000 
              ? text.substring(0, 10000) + "..." 
              : text;
        });
      }
    } catch (e) {
      debugPrint("Context extraction failed: $e");
    }
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionsData = prefs.getString("groq_sessions_v2");
    
    if (sessionsData != null) {
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(jsonDecode(sessionsData));
      });
    } else {
      // Migration logic from old single-session history
      final String? oldData = prefs.getString("groq_chat_history");
      if (oldData != null) {
        try {
          final List<dynamic> decoded = jsonDecode(oldData);
          final List<Map<String, String>> oldMessages = decoded.map((m) => Map<String, String>.from(m)).toList();
          
          if (oldMessages.isNotEmpty) {
            final String newId = DateTime.now().millisecondsSinceEpoch.toString();
            final Map<String, dynamic> migratedSession = {
              "id": newId,
              "title": _generateTitle(oldMessages),
              "messages": oldMessages,
              "timestamp": DateTime.now().millisecondsSinceEpoch,
            };
            setState(() {
              _sessions = [migratedSession];
              _currentSessionId = newId;
              messages = oldMessages;
            });
            await _saveSessions();
          }
        } catch (e) {
          debugPrint("Migration failed: $e");
        }
      }
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("groq_sessions_v2", jsonEncode(_sessions));
  }

  void _startNewChat() {
    setState(() {
      messages = [];
      _currentSessionId = null;
      _attachedFileBytes = null;
      _attachedFileName = null;
      _extractedContext = null;
    });
  }

  void _loadSession(Map<String, dynamic> session) {
    setState(() {
      _currentSessionId = session["id"];
      messages = List<Map<String, String>>.from(
        (session["messages"] as List).map((m) => Map<String, String>.from(m))
      );
      _attachedFileBytes = null;
      _attachedFileName = null;
      _extractedContext = null;
    });
    Navigator.pop(context); // Close drawer
  }

  void _deleteSession(String id) {
    setState(() {
      _sessions.removeWhere((s) => s["id"] == id);
      if (_currentSessionId == id) {
        _startNewChat();
      }
    });
    _saveSessions();
  }

  String _generateTitle(List<Map<String, String>> msgs) {
    if (msgs.isEmpty) return "New Chat";
    final firstUserMsg = msgs.firstWhere((m) => m["role"] == "user", orElse: () => {"content": "New Chat"});
    String content = firstUserMsg["content"] ?? "New Chat";
    if (content.length > 30) {
      return content.substring(0, 27) + "...";
    }
    return content;
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
      withData: true, // Crucial for getting bytes on all platforms
    );

    if (result != null) {
      Uint8List? bytes = result.files.first.bytes;
      
      // On some mobile devices, bytes might still be null, so read from path
      if (bytes == null && result.files.first.path != null) {
        bytes = await File(result.files.first.path!).readAsBytes();
      }

      setState(() {
        _attachedFileBytes = bytes;
        _attachedFileName = result.files.first.name;
        _extractedContext = null;
      });
      await _extractContextFromActiveFile();
    }
  }

  void _handleRateLimit(String text) async {
    setState(() {
      _errorMessage = "Rate limit reached. Redirecting to Groq website...";
      messages.add({
        "role": "assistant",
        "content": "⚠️ **Rate limit reached.** I'm opening the Groq website for you so you can continue your conversation there."
      });
    });

    final url = Uri.parse("https://groq.com/chat?q=${Uri.encodeComponent(text)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty && _attachedFileBytes == null) return;
    
    if (_activeKey.isEmpty) {
      setState(() => _errorMessage = "Groq API Key missing in .env");
      return;
    }

    String displayText = text;
    if (_attachedFileName != null && text.isEmpty) {
      displayText = "Analyze attached file: $_attachedFileName";
    }

    setState(() {
      messages.add({"role": "user", "content": displayText});
      isLoading = true;
      _errorMessage = null;
    });

    controller.clear();
    scrollToBottom();

    try {
      String systemPrompt = "You are Readr Study Assistant. Be helpful, academic, and concise. Support the student with their queries.";
      
      if (_extractedContext != null) {
        systemPrompt += "\n\n[DOCUMENT CONTEXT: $_attachedFileName]\n$_extractedContext\n[END DOCUMENT CONTEXT]";
        systemPrompt += "\n\nInstructions: Use the provided document context to answer the student's questions. If the answer isn't in the document, you may use your general knowledge but mention it's not in the file.";
      }
      
      if (widget.youtubeUrl != null) {
        systemPrompt += "\n[VIDEO CONTEXT: ${widget.youtubeUrl}. Help the student understand this video.]";
      }

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_activeKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {"role": "system", "content": systemPrompt},
            ...messages,
          ],
          "temperature": 0.7,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['choices'][0]['message']['content'];

        setState(() {
          messages.add({"role": "assistant", "content": reply});
          
          // Update or create session
          if (_currentSessionId == null) {
            _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
            _sessions.insert(0, {
              "id": _currentSessionId,
              "title": _generateTitle(messages),
              "messages": messages,
              "timestamp": DateTime.now().millisecondsSinceEpoch,
            });
          } else {
            final index = _sessions.indexWhere((s) => s["id"] == _currentSessionId);
            if (index != -1) {
              _sessions[index]["messages"] = messages;
              _sessions[index]["timestamp"] = DateTime.now().millisecondsSinceEpoch;
              // Move to top
              final session = _sessions.removeAt(index);
              _sessions.insert(0, session);
            }
          }
        });

        ActivityService().trackActivity(
          title: "Groq AI Chat",
          subtitle: displayText.length > 30 ? '${displayText.substring(0, 30)}...' : displayText,
          type: 'Ai',
        );
      } else if (response.statusCode == 429) {
        _handleRateLimit(displayText);
      } else {
        throw "Error ${response.statusCode}: ${response.body}";
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Connection error. Please try again.";
        messages.add({
          "role": "assistant", 
          "content": "⚠️ **Error:** $e"
        });
      });
    } finally {
      setState(() => isLoading = false);
      _saveSessions();
      scrollToBottom();
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appBarColor = isDark ? AcademicTheme.darkCard : AcademicTheme.primary;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
      endDrawer: _buildHistoryDrawer(isDark),
      appBar: AppBar(
        title: const Text(
          "Study Assistant",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: appBarColor,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'new') {
                _startNewChat();
                _saveSessions();
              } else if (value == 'delete_all') {
                _showDeleteConfirm();
              } else if (value == 'past') {
                _scaffoldKey.currentState?.openEndDrawer();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [Icon(Icons.add, size: 20), SizedBox(width: 8), Text("New Chat")],
                ),
              ),
              const PopupMenuItem(
                value: 'past',
                child: Row(
                  children: [Icon(Icons.history, size: 20), SizedBox(width: 8), Text("Past Chats")],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [Icon(Icons.delete_sweep, size: 20, color: Colors.red), SizedBox(width: 8), Text("Delete All", style: TextStyle(color: Colors.red))],
                ),
              ),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.red.withValues(alpha: 0.1),
              width: double.infinity,
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          Expanded(
            child: Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: Responsive.isDesktop(context) ? 900 : double.infinity),
                child: messages.isEmpty && !isLoading
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _buildBubble(messages[index], isDark),
                      ),
              ),
            ),
          ),
          if (isLoading) LinearProgressIndicator(color: AcademicTheme.primary, backgroundColor: AcademicTheme.primary.withValues(alpha: 0.1)),
          if (_attachedFileName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? Colors.blueGrey.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.05),
              child: Row(
                children: [
                  Icon(
                    _extractedContext != null ? Icons.fact_check : Icons.attach_file, 
                    size: 16, 
                    color: _extractedContext != null ? Colors.green : AcademicTheme.primary
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _extractedContext != null 
                        ? "Context Active: $_attachedFileName" 
                        : "Attaching: $_attachedFileName...",
                      style: TextStyle(
                        fontSize: 12, 
                        fontWeight: FontWeight.w500,
                        color: _extractedContext != null ? (isDark ? Colors.greenAccent : Colors.green[700]) : null
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() {
                      _attachedFileBytes = null;
                      _attachedFileName = null;
                      _extractedContext = null;
                    }),
                  )
                ],
              ),
            ),
          _buildInput(isDark),
        ],
      ),
    );
  }

  void _showDeleteConfirm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AcademicTheme.darkCard : Colors.white,
        title: Text("Delete All Chats?", style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: Text(
          "This will permanently delete all your chat history.",
          style: TextStyle(color: isDark ? Colors.white70 : AcademicTheme.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              setState(() {
                messages.clear();
                _sessions.clear();
                _currentSessionId = null;
              });
              _saveSessions();
              Navigator.pop(context);
            },
            child: const Text("Delete All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer(bool isDark) {
    return Drawer(
      backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: isDark ? AcademicTheme.darkCard : AcademicTheme.primary,
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, color: Colors.white, size: 40),
                  SizedBox(height: 10),
                  Text(
                    "Chat History",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _sessions.isEmpty
                ? Center(
                    child: Text(
                      "No past chats yet",
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final isCurrent = session["id"] == _currentSessionId;
                      return ListTile(
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          color: isCurrent ? AcademicTheme.primary : (isDark ? Colors.white54 : Colors.black54),
                        ),
                        title: Text(
                          session["title"] ?? "Untitled Chat",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          DateTime.fromMillisecondsSinceEpoch(session["timestamp"]).toString().split('.')[0],
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                        onTap: () => _loadSession(session),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                          onPressed: () => _deleteSession(session["id"]),
                        ),
                        selected: isCurrent,
                        selectedTileColor: AcademicTheme.primary.withValues(alpha: 0.1),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                _startNewChat();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add),
              label: const Text("New Chat"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                backgroundColor: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bolt, 
            size: 80, 
            color: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.3)
          ),
          const SizedBox(height: 16),
          Text(
            "Powered by Groq High-Speed AI",
            style: TextStyle(
              fontSize: 18, 
              fontWeight: FontWeight.w500,
              color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Ask a question or attach a file to start.",
            style: TextStyle(
              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg, bool isDark) {
    bool isUser = msg["role"] == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isUser 
              ? (isDark ? AcademicTheme.darkSecondary : AcademicTheme.primary) 
              : (isDark ? AcademicTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: MarkdownBody(
          data: msg["content"] ?? "",
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(
              color: isUser ? Colors.white : (isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary),
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: isDark ? AcademicTheme.darkCard : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file, color: isDark ? Colors.white54 : Colors.black54),
            onPressed: _pickFile,
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                borderRadius: BorderRadius.circular(28),
              ),
              child: TextField(
                controller: controller,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 15),
                decoration: InputDecoration(
                  hintText: "Ask a question...",
                  hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onSubmitted: sendMessage,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => sendMessage(controller.text),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
