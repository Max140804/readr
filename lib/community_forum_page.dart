import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'data/timetable_data.dart';

class Message {
  final String sender;
  final String? text;
  final String? imagePath;
  final DateTime timestamp;
  final String uid;

  Message({
    required this.sender,
    this.text,
    this.imagePath,
    required this.timestamp,
    required this.uid,
  });

  Map<String, dynamic> toMap() => {
    'sender': sender,
    'text': text,
    'imagePath': imagePath,
    'timestamp': Timestamp.fromDate(timestamp),
    'uid': uid,
  };

  factory Message.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      sender: data['sender'] ?? 'Anonymous',
      text: data['text'],
      imagePath: data['imagePath'],
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      uid: data['uid'] ?? '',
    );
  }
}

class CommunityForumPage extends StatefulWidget {
  final String userName;
  final String userId; // Added to identify 'Me' vs 'Others'
  const CommunityForumPage({super.key, this.userName = "Scholr", this.userId = "user_1"});

  @override
  State<CommunityForumPage> createState() => _CommunityForumPageState();
}

class _CommunityForumPageState extends State<CommunityForumPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage({String? text, String? imagePath}) async {
    String? trimmedText = text?.trim();
    if ((trimmedText == null || trimmedText.isEmpty) && imagePath == null) return;
    
    final newMessage = Message(
      sender: widget.userName,
      text: trimmedText,
      imagePath: imagePath,
      timestamp: DateTime.now(),
      uid: widget.userId,
    );

    await _firestore.collection('forum_messages').add(newMessage.toMap());
    _controller.clear();
    _scrollToBottom();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      _sendMessage(imagePath: image.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Community Forum", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('forum_messages').orderBy('timestamp').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final docs = snapshot.data!.docs;
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final msg = Message.fromDoc(docs[index]);
                    return _ChatBubble(
                      message: msg, 
                      isDark: isDark, 
                      isMe: msg.uid == widget.userId
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(isDark),
        ],
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AcademicTheme.darkCard : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined, color: AcademicTheme.primary),
              onPressed: _pickImage,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  hintStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                onSubmitted: (val) => _sendMessage(text: val.trim()),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: AcademicTheme.primary,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () => _sendMessage(text: _controller.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Message message;
  final bool isDark;
  final bool isMe;

  const _ChatBubble({required this.message, required this.isDark, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? AcademicTheme.primary
              : (isDark ? AcademicTheme.darkCard : Colors.grey[200]),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                message.sender,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.blueAccent,
                ),
              ),
            if (!isMe) const SizedBox(height: 4),
            if (message.imagePath != null && message.imagePath!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: message.imagePath!.startsWith('http') 
                    ? Image.network(message.imagePath!) 
                    : Image.file(
                        File(message.imagePath!),
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50),
                      ),
                ),
              ),
            if (message.text != null)
              Text(
                message.text!,
                style: TextStyle(
                  color: isMe
                      ? Colors.white
                      : (isDark ? Colors.white : Colors.black87),
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              "${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}",
              style: TextStyle(
                fontSize: 10,
                color: isMe ? Colors.white70 : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
