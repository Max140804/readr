import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'data/timetable_data.dart';

class AssistantPage extends StatefulWidget {
  final String? initialPrompt;
  const AssistantPage({super.key, this.initialPrompt});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final TextEditingController controller = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, String>> messages = [];
  bool isLoading = false;
  String? _errorMessage;
  String _activeKey = "";

  @override
  void initState() {
    super.initState();
    _initConfiguration();
  }

  void _initConfiguration() {
    // Attempt to load from .env
    String envKey = dotenv.env['GEMINI_API_KEY']?.trim() ?? "";
    setState(() {
      _activeKey = envKey;
      if (_activeKey.isEmpty) {
        _errorMessage = "No API Key found in .env. Use the 'Fix' button below.";
      }
    });

    loadMessages().then((_) {
      if (widget.initialPrompt != null && messages.isEmpty && _activeKey.isNotEmpty) {
        sendMessage(widget.initialPrompt!);
      }
    });
  }

  Future<void> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString("chat_history");
    if (data != null) {
      setState(() {
        messages = List<Map<String, String>>.from(jsonDecode(data));
      });
    }
  }

  Future<void> saveMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("chat_history", jsonEncode(messages));
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_activeKey.isEmpty) {
      _showKeyDialog();
      return;
    }

    setState(() {
      messages.add({"role": "user", "text": text});
      isLoading = true;
      _errorMessage = null;
    });

    controller.clear();
    scrollToBottom();

    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _activeKey);
      final content = [Content.text(text)];
      
      final response = await model.generateContent(content).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw "Request timed out. Check your internet connection.",
      );
      
      final reply = response.text ?? "AI returned an empty response.";

      setState(() {
        messages.add({"role": "model", "text": reply});
      });
    } catch (e) {
      String userFriendlyError = "Communication Error. Please try again.";
      final errorStr = e.toString().toLowerCase();
      
      if (errorStr.contains("403") || errorStr.contains("permission")) {
        userFriendlyError = "Invalid API Key. Please click the 'Fix Key' button at the top.";
      } else if (errorStr.contains("429") || errorStr.contains("quota")) {
        userFriendlyError = "API quota exceeded. Please wait a moment or check your Google Cloud billing.";
      } else if (errorStr.contains("timeout") || errorStr.contains("internet")) {
        userFriendlyError = "Network error. Check your internet connection.";
      }

      setState(() {
        _errorMessage = "AI Unavailable: $userFriendlyError";
        messages.add({
          "role": "model", 
          "text": "⚠️ **Error:** $userFriendlyError\n\n*(Technical details: $e)*"
        });
      });
    } finally {
      setState(() => isLoading = false);
      saveMessages();
      scrollToBottom();
    }
  }

  void _showKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Set API Key"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("The .env file failed to load. Please paste your Gemini API key below:"),
            const SizedBox(height: 10),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "AIzaSy..."),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _activeKey = _keyController.text.trim();
                _errorMessage = null;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Key updated! Try sending again.")));
            },
            child: const Text("Save Key"),
          ),
        ],
      ),
    );
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

    return Scaffold(
      appBar: AppBar(
        title: const Text("Study Assistant"),
        actions: [
          IconButton(icon: const Icon(Icons.vpn_key_outlined), onPressed: _showKeyDialog, tooltip: "Fix Key"),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() => messages.clear());
              saveMessages();
            },
          )
        ],
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            GestureDetector(
              onTap: _showKeyDialog,
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.orange.withOpacity(0.2),
                width: double.infinity,
                child: Text(
                  "$_errorMessage\nTap here to fix.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: messages.isEmpty && !isLoading
                ? _buildEmptyState()
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) => _buildBubble(messages[index], isDark),
                  ),
          ),
          if (isLoading) const LinearProgressIndicator(),
          _buildInput(isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, size: 60, color: AcademicTheme.primary.withOpacity(0.3)),
          const SizedBox(height: 10),
          const Text("Ready to help you study!"),
          const SizedBox(height: 5),
          Text("Current Key: ${_activeKey.isEmpty ? 'None' : 'Active'}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg, bool isDark) {
    bool isUser = msg["role"] == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? AcademicTheme.primary : (isDark ? Colors.grey[850] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(15),
        ),
        child: MarkdownBody(
          data: msg["text"] ?? "",
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87)),
          ),
        ),
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Ask a question...", border: InputBorder.none),
              onSubmitted: sendMessage,
            ),
          ),
          IconButton(icon: const Icon(Icons.send, color: AcademicTheme.primary), onPressed: () => sendMessage(controller.text)),
        ],
      ),
    );
  }
}
