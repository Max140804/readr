import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'services/connectivity_service.dart';
import 'data/timetable_data.dart';
import 'package:intl/intl.dart';
import 'utils/responsive_utils.dart';

class Message {
  final String id;
  final String sender;
  final String? text;
  final String? imageUrl;
  final String? localPath;
  final DateTime timestamp;
  final String uid;
  final bool isPending;
  final String? replyToName;
  final String? replyToText;
  final String? replyToId;
  final Map<String, dynamic> reactions;

  Message({
    required this.id,
    required this.sender,
    this.text,
    this.imageUrl,
    this.localPath,
    required this.timestamp,
    required this.uid,
    this.isPending = false,
    this.replyToName,
    this.replyToText,
    this.replyToId,
    this.reactions = const {},
  });

  factory Message.fromMap(Map<String, dynamic> data) {
    final dynamic stamp = data['timestamp'];
    DateTime time = stamp != null ? DateTime.parse(stamp) : DateTime.now();

    return Message(
      id: data['id']?.toString() ?? '',
      sender: data['sender'] ?? 'Anonymous',
      text: data['text'],
      imageUrl: data['image_url'],
      timestamp: time,
      uid: data['uid']?.toString() ?? '',
      isPending: false,
      replyToName: data['reply_to_name'],
      replyToText: data['reply_to_text'],
      replyToId: data['reply_to_id']?.toString(),
      reactions: (data['reactions'] is Map) 
          ? Map<String, dynamic>.from(data['reactions']) 
          : {},
    );
  }
}

class CommunityForumPage extends StatefulWidget {
  final String userName;
  final String userId;
  const CommunityForumPage({super.key, this.userName = "Scholr", this.userId = "user_1"});

  @override
  State<CommunityForumPage> createState() => _CommunityForumPageState();
}

class _CommunityForumPageState extends State<CommunityForumPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final _supabase = Supabase.instance.client;
  final List<Message> _pendingMessages = [];
  final Map<String, GlobalKey> _messageKeys = {};
  Message? _replyMessage;
  String? _selectedImagePath;
  bool _isUploading = false;
  String? _highlightedMessageId;
  bool _isOffline = false;
  bool _showEmojiPicker = false;
  bool _showScrollToBottom = false;

  late Stream<List<Map<String, dynamic>>> _messageStream;
  StreamSubscription? _connectivitySubscription;
  List<Message> _cachedMessages = [];
  List<Message> _allMessages = []; // For robust scrolling

  @override
  void initState() {
    super.initState();
    _loadCache();
    _messageStream = _supabase
        .from('forum_messages')
        .stream(primaryKey: ['id'])
        .order('timestamp', ascending: true);
    FlutterBackgroundService().invoke('setForumOpen', {'open': true});
    _markAsRead();
    
    _scrollController.addListener(_scrollListener);
    
    _isOffline = !ConnectivityService().isConnected;
    _connectivitySubscription = ConnectivityService().connectivityStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isOffline = !connected;
        });
      }
    });
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      final show = _scrollController.offset < _scrollController.position.maxScrollExtent - 300;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('forum_cache_${widget.userId}');
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _cachedMessages = decoded.map((m) => Message.fromMap(m)).toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading forum cache: $e");
    }
  }

  Future<void> _saveToCache(List<Message> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only cache last 100 messages for performance
      final toCache = messages.length > 100 ? messages.sublist(messages.length - 100) : messages;
      final String encoded = jsonEncode(toCache.map((m) => {
        'id': m.id,
        'sender': m.sender,
        'text': m.text,
        'image_url': m.imageUrl,
        'timestamp': m.timestamp.toIso8601String(),
        'uid': m.uid,
        'reply_to_name': m.replyToName,
        'reply_to_text': m.replyToText,
        'reply_to_id': m.replyToId,
        'reactions': m.reactions,
      }).toList());
      await prefs.setString('forum_cache_${widget.userId}', encoded);
    } catch (e) {
      debugPrint("Error saving forum cache: $e");
    }
  }

  @override
  void dispose() {
    FlutterBackgroundService().invoke('setForumOpen', {'open': false});
    _connectivitySubscription?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onReply(Message msg) {
    setState(() => _replyMessage = msg);
    _focusNode.requestFocus();
  }

  void _scrollToMessage(String? messageId) {
    if (messageId == null || messageId.isEmpty) return;
    
    // Check if the message is already in the view
    var key = _messageKeys[messageId];
    if (key != null && key.currentContext != null) {
      _performScrollAndHighlight(messageId, key.currentContext!);
      return;
    }

    // If not in view, find its index in the full list
    final index = _allMessages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    if (_scrollController.hasClients) {
      final double totalExtent = _scrollController.position.maxScrollExtent;
      final double estimatedOffset = (totalExtent / _allMessages.length) * index;
      
      // Jump to the estimated position to bring it into the builder's context
      _scrollController.animateTo(
        estimatedOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ).then((_) {
        // Wait for the list to build the newly visible items
        Future.delayed(const Duration(milliseconds: 150), () {
          var keyRetry = _messageKeys[messageId];
          if (keyRetry != null && keyRetry.currentContext != null) {
            _performScrollAndHighlight(messageId, keyRetry.currentContext!);
          } else {
            // Refined fallback: try ensuring visibility with broader constraints
            WidgetsBinding.instance.addPostFrameCallback((_) {
              var finalKey = _messageKeys[messageId];
              if (finalKey != null && finalKey.currentContext != null) {
                _performScrollAndHighlight(messageId, finalKey.currentContext!);
              }
            });
          }
        });
      });
    }
  }

  void _performScrollAndHighlight(String messageId, BuildContext context) {
    setState(() => _highlightedMessageId = messageId);
    HapticFeedback.lightImpact();
    
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 600),
      curve: Curves.fastOutSlowIn,
      alignment: 0.5,
    );
    
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _markAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('last_seen_forum_${widget.userId}', now);
    await prefs.remove('last_notified_msg_id_${widget.userId}');
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image != null) {
      setState(() {
        _selectedImagePath = image.path;
      });
    }
  }

  void _sendMessage() async {
    if (_isUploading) return;
    
    final String text = _controller.text.trim();
    final String? imagePath = _selectedImagePath;

    if (text.isEmpty && imagePath == null) return;

    final replyingTo = _replyMessage;
    setState(() {
      _isUploading = true;
      _replyMessage = null;
      _selectedImagePath = null;
      _controller.clear();
    });

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    
    final pendingMsg = Message(
      id: tempId,
      sender: widget.userName,
      text: text.isNotEmpty ? text : null,
      imageUrl: null, 
      localPath: imagePath,
      timestamp: DateTime.now(),
      uid: widget.userId,
      isPending: true,
      replyToName: replyingTo?.sender,
      replyToText: replyingTo?.text ?? (replyingTo?.imageUrl != null ? "Image 🖼️" : null),
      replyToId: replyingTo?.id,
    );

    setState(() {
      _pendingMessages.add(pendingMsg);
    });

    String? imageUrl;
    if (imagePath != null) {
      try {
        final file = File(imagePath);
        final extension = imagePath.split('.').last;
        final fileName = '${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.$extension';
        
        await _supabase.storage.from('forum_images').upload(
          fileName, 
          file,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
        imageUrl = _supabase.storage.from('forum_images').getPublicUrl(fileName);
      } catch (e) {
        debugPrint("Image upload failed: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Attachment failed: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }

    // Prepare message data with proper type conversion for Supabase
    final dynamic numericUid = int.tryParse(widget.userId);
    final dynamic numericReplyId = replyingTo != null ? int.tryParse(replyingTo.id) : null;

    final messageData = {
      'sender': widget.userName,
      'text': text.isNotEmpty ? text : null,
      'image_url': imageUrl, 
      'uid': numericUid ?? widget.userId,
      'reply_to_name': replyingTo?.sender,
      'reply_to_text': replyingTo?.text ?? (replyingTo?.imageUrl != null ? "Image 🖼️" : null),
      'reply_to_id': numericReplyId ?? replyingTo?.id,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      await _supabase.from('forum_messages').insert(messageData);
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.id == tempId);
          _isUploading = false;
        });
      }
    } catch (e) {
      debugPrint("Send error: $e");
      
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.id == tempId);
          _isUploading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Send failed: You may be disconnected from the internet, please check in later"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _deleteMessage(Message msg) async {
    try {
      if (msg.imageUrl != null) {
        final fileName = msg.imageUrl!.split('/').last.split('?').first;
        await _supabase.storage.from('forum_images').remove([fileName]);
      }
      final dynamic numericId = int.tryParse(msg.id) ?? msg.id;
      await _supabase.from('forum_messages').delete().match({'id': numericId});
    } catch (e) {
      debugPrint("Delete failed: $e");
    }
  }

  void _toggleReaction(Message msg, String emoji) async {
    final Map<String, dynamic> currentReactions = Map<String, dynamic>.from(msg.reactions);
    final String myId = widget.userId;
    
    List<dynamic> users = List<dynamic>.from(currentReactions[emoji] ?? []);
    if (users.contains(myId)) {
      users.remove(myId);
    } else {
      users.add(myId);
    }
    
    if (users.isEmpty) {
      currentReactions.remove(emoji);
    } else {
      currentReactions[emoji] = users;
    }

    // Optimistic UI update could go here, but we'll rely on the stream
    try {
      final dynamic numericId = int.tryParse(msg.id) ?? msg.id;
      await _supabase
          .from('forum_messages')
          .update({'reactions': currentReactions})
          .eq('id', numericId);
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint("Reaction failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to react: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AcademicTheme.darkBackground : const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Community Forum", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
            Text("Shared Study Space", style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.7), letterSpacing: 1)),
          ],
        ),
        backgroundColor: AcademicTheme.primary,
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: Responsive.isDesktop(context) ? 900 : double.infinity),
          child: Stack(
            children: [
              Column(
                children: [
                  if (_isOffline)
                    Container(
                      width: double.infinity,
                      color: Colors.orange.withValues(alpha: 0.9),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: const Text(
                        "You may be disconnected from the internet, please check in later",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _messageStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return _buildErrorView("Sync lost. Showing cached messages.");
                        
                        List<Message> streamMessages = [];
                        if (snapshot.hasData) {
                          streamMessages = snapshot.data!.map((d) => Message.fromMap(d)).toList();
                          // Save to cache asynchronously
                          _saveToCache(streamMessages);
                          
                          // Scroll to bottom on first load or new messages if we are already at bottom
                          if (_allMessages.isEmpty && streamMessages.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
                          }
                        } else if (_cachedMessages.isNotEmpty) {
                          streamMessages = _cachedMessages;
                        } else {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final filteredPending = _pendingMessages.where((pending) {
                          return !streamMessages.any((stream) => 
                            stream.uid == pending.uid && 
                            ((stream.text == pending.text && pending.text != null) || 
                             (stream.imageUrl != null && pending.localPath != null))
                          );
                        }).toList();

                        final allMessages = [...streamMessages, ...filteredPending];
                        allMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                        
                        _allMessages = allMessages;

                        if (allMessages.isEmpty) {
                          return _buildEmptyState(isDark);
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          cacheExtent: 5000, 
                          padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
                          itemCount: allMessages.length,
                          itemBuilder: (context, index) {
                            final msg = allMessages[index];
                            final bool isMe = msg.uid.toString() == widget.userId.toString();
                            
                            bool showDate = false;
                            if (index == 0) {
                              showDate = true;
                            } else {
                              final prevMsg = allMessages[index - 1];
                              if (prevMsg.timestamp.day != msg.timestamp.day) showDate = true;
                            }

                            return Column(
                              key: _messageKeys.putIfAbsent(msg.id, () => GlobalKey()),
                              children: [
                                if (showDate) _buildDateHeader(msg.timestamp, isDark),
                                _ChatBubble(
                                  message: msg, 
                                  isDark: isDark, 
                                  isMe: isMe,
                                  userId: widget.userId,
                                  onDelete: () => _deleteMessage(msg),
                                  onReply: () => _onReply(msg),
                                  onReaction: (emoji) => _toggleReaction(msg, emoji),
                                  onReplyTap: () => _scrollToMessage(msg.replyToId),
                                  isHighlighted: _highlightedMessageId == msg.id,
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                  _buildMessageInput(isDark),
                ],
              ),
              if (_showScrollToBottom)
                Positioned(
                  bottom: _showEmojiPicker ? 360 : 110,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _scrollToBottom,
                    backgroundColor: AcademicTheme.primary,
                    foregroundColor: Colors.white,
                    child: const Icon(Icons.arrow_downward),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader(DateTime date, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        DateFormat('MMMM dd, yyyy').format(date),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? Colors.white38 : Colors.grey),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: (isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 60,
                color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "Let's get the party started!",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : AcademicTheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "This is the beginning of your legendary conversation. Share notes, ask questions, or just vibe with your fellow scholars.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AcademicTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AcademicTheme.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tips_and_updates_outlined, size: 16, color: AcademicTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    "Try saying 'Hi' to get things started!",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AcademicTheme.darkAccent : AcademicTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(String msg) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text(msg, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AcademicTheme.darkCard : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: AcademicTheme.primary, width: 4), bottom: BorderSide(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: AcademicTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Replying to ${_replyMessage!.sender}: ${_replyMessage!.text ?? '🖼️ Attachment'}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyMessage = null)),
                ],
              ),
            ),
          if (_selectedImagePath != null)
            Container(
              height: 90,
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_selectedImagePath!), fit: BoxFit.cover, width: 80, height: 80),
                  ),
                  Positioned(
                    top: 0, right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedImagePath = null),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  child: IconButton(
                    icon: Icon(
                      _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined, 
                      color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey[600], 
                      size: 28
                    ),
                    onPressed: () {
                      setState(() => _showEmojiPicker = !_showEmojiPicker);
                      if (_showEmojiPicker) {
                        _focusNode.unfocus();
                      } else {
                        _focusNode.requestFocus();
                      }
                    },
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      onTap: () {
                        if (_showEmojiPicker) setState(() => _showEmojiPicker = false);
                      },
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: "Message...",
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[500]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file_rounded, size: 22),
                              onPressed: _pickImage,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.camera_alt_outlined, size: 22),
                              onPressed: () async {
                                final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                                if (image != null) setState(() => _selectedImagePath = image.path);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isUploading ? null : _sendMessage,
                  child: Container(
                    height: 44,
                    width: 44,
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: AcademicTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AcademicTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: _isUploading 
                      ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (_showEmojiPicker)
            Container(
              height: 250,
              color: isDark ? AcademicTheme.darkCard : Colors.white,
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: _emojis.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () {
                      _controller.text += _emojis[index];
                      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
                    },
                    child: Center(
                      child: Text(_emojis[index], style: const TextStyle(fontSize: 24)),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  final List<String> _emojis = [
    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰",
    "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🤩", "🥳", "😏",
    "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠",
    "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗", "🤔", "🤭", "🤫", "🤥",
    "😶", "😐", "😑", "😬", "🙄", "😯", "😦", "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵", "🤐",
    "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "😈", "👿", "👹", "👺", "🤡", "👻", "💀",
    "☠️", "👽", "👾", "🤖", "🎃", "😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾", "🤲", "👐",
    "🙌", "👏", "🤝", "👍", "👎", "👊", "✊", "🤛", "🤜", "🤞", "🤟", "🤘", "👌", "🤌", "🤏", "👈",
    "👉", "👆", "👇", "💪", "🦾", "🖕", "✍️", "🙏", "🤳", "💅", "🤝", "🫂", "👂", "🦻", "👃", "🧠",
    "🫀", "🫁", "🦷", "🦴", "👀", "👁", "👅", "👄", "👶", "🧒", "👦", "👧", "🧑", "👱", "👨", "🧔",
  ];
}

class _ChatBubble extends StatefulWidget {
  final Message message;
  final bool isDark;
  final bool isMe;
  final String userId;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final VoidCallback? onReplyTap;
  final Function(String) onReaction;
  final bool isHighlighted;
  const _ChatBubble({
    required this.message, 
    required this.isDark, 
    required this.isMe, 
    required this.userId,
    required this.onDelete, 
    required this.onReply,
    this.onReplyTap,
    required this.onReaction,
    this.isHighlighted = false,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  double _swipeOffset = 0;

  void _showActionMenu() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => _MessageOptionsMenu(
        isMe: widget.isMe,
        onDelete: widget.onDelete,
        onReply: widget.onReply,
        onReaction: widget.onReaction,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = widget.isHighlighted
        ? (widget.isDark ? Colors.orange.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.2))
        : (widget.isMe 
            ? AcademicTheme.primary 
            : (widget.isDark ? AcademicTheme.darkCard : Colors.white));
    
    final textColor = widget.isMe 
        ? Colors.white 
        : (widget.isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87);

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0 && !widget.isMe) {
          setState(() => _swipeOffset = (_swipeOffset + details.delta.dx).clamp(0, 70));
        } else if (details.delta.dx < 0 && widget.isMe) {
          setState(() => _swipeOffset = (_swipeOffset + details.delta.dx).clamp(-70, 0));
        }
      },
      onHorizontalDragEnd: (details) {
        if (_swipeOffset.abs() >= 50) {
          HapticFeedback.mediumImpact();
          widget.onReply();
        }
        setState(() => _swipeOffset = 0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.translationValues(_swipeOffset, 0, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (_swipeOffset.abs() > 10)
              Positioned(
                left: widget.isMe ? null : -40,
                right: widget.isMe ? -40 : null,
                top: 0, bottom: 0,
                child: Icon(Icons.reply, color: AcademicTheme.primary.withValues(alpha: _swipeOffset.abs() / 70)),
              ),
            Align(
              alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (!widget.isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 4),
                        child: Text(
                          widget.message.sender,
                          style: TextStyle(
                            fontSize: 11, 
                            fontWeight: FontWeight.bold, 
                            color: widget.isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onLongPress: _showActionMenu,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: bubbleColor,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(20),
                                topRight: const Radius.circular(20),
                                bottomLeft: Radius.circular(widget.isMe ? 20 : 6),
                                bottomRight: Radius.circular(widget.isMe ? 6 : 20),
                              ),
                              border: widget.isHighlighted
                                  ? Border.all(color: Colors.orange, width: 2)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: widget.isDark ? 0.2 : 0.05), 
                                  blurRadius: 8, 
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.message.replyToName != null)
                                  _buildReplyPreview(widget.isMe, widget.isDark),
                                if (widget.message.imageUrl != null || widget.message.localPath != null)
                                  _buildImage(context),
                                if (widget.message.text != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Text(
                                      widget.message.text!, 
                                      style: TextStyle(
                                        color: textColor, 
                                        fontSize: 15,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 10, 6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DateFormat('HH:mm').format(widget.message.timestamp),
                                        style: TextStyle(fontSize: 9, color: widget.isMe ? Colors.white60 : Colors.grey),
                                      ),
                                      if (widget.isMe) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          widget.message.isPending ? Icons.schedule_rounded : Icons.done_all_rounded, 
                                          size: 11, 
                                          color: widget.message.isPending ? Colors.white54 : Colors.white70,
                                        ),
                                      ]
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.message.reactions.isNotEmpty)
                          Positioned(
                            bottom: -12,
                            right: widget.isMe ? 0 : null,
                            left: !widget.isMe ? 0 : null,
                            child: _buildReactionsDisplay(),
                          ),
                      ],
                    ),
                    if (widget.message.reactions.isNotEmpty)
                      const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionsDisplay() {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        children: widget.message.reactions.entries.map((e) {
          final List users = e.value;
          final bool reactedByMe = users.contains(widget.userId);
          return TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            curve: Curves.elasticOut,
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onReaction(e.key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: reactedByMe 
                      ? AcademicTheme.primary.withValues(alpha: 0.15) 
                      : (widget.isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: reactedByMe 
                        ? AcademicTheme.primary.withValues(alpha: 0.4) 
                        : Colors.transparent,
                    width: 1.5,
                  ),
                  boxShadow: reactedByMe ? [
                    BoxShadow(
                      color: AcademicTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 4,
                      spreadRadius: 0,
                    )
                  ] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      users.length.toString(), 
                      style: TextStyle(
                        fontSize: 11, 
                        fontWeight: FontWeight.w900, 
                        color: reactedByMe ? AcademicTheme.primary : (widget.isDark ? Colors.white70 : Colors.black87)
                      )
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReplyPreview(bool isMe, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onReplyTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: isMe ? Colors.white38 : AcademicTheme.primary, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.reply_rounded, 
                    size: 12, 
                    color: isMe ? Colors.white70 : AcademicTheme.primary
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.message.replyToName!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 11, 
                        color: isMe ? Colors.white.withValues(alpha: 0.9) : AcademicTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.message.replyToText ?? "Attachment 🖼️",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11, 
                  color: isMe ? Colors.white.withValues(alpha: 0.7) : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => _FullScreenImage(imageUrl: widget.message.imageUrl, localPath: widget.message.localPath)));
      },
      child: Hero(
        tag: widget.message.id,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: widget.message.localPath != null 
            ? Image.file(File(widget.message.localPath!), fit: BoxFit.cover, width: double.infinity, height: 200)
            : Image.network(
                widget.message.imageUrl!, 
                fit: BoxFit.cover, 
                width: double.infinity, 
                height: 200,
                loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
              ),
        ),
      ),
    );
  }
}

class _MessageOptionsMenu extends StatelessWidget {
  final bool isMe;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final Function(String) onReaction;
  const _MessageOptionsMenu({required this.isMe, required this.onDelete, required this.onReply, required this.onReaction});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reactions Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ["❤️", "😂", "😮", "😢", "🔥", "👍", "👏", "💯"].map((emoji) {
                return _AnimatedEmojiButton(
                  emoji: emoji,
                  onTap: () {
                    onReaction(emoji);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // Options Menu
          Material(
            color: Colors.transparent,
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.reply),
                    title: const Text("Reply"),
                    onTap: () {
                      Navigator.pop(context);
                      onReply();
                    },
                  ),
                  if (isMe)
                    ListTile(
                      leading: const Icon(Icons.delete, color: Colors.red),
                      title: const Text("Delete", style: TextStyle(color: Colors.red)),
                      onTap: () {
                        Navigator.pop(context);
                        onDelete();
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedEmojiButton extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;
  const _AnimatedEmojiButton({required this.emoji, required this.onTap});

  @override
  State<_AnimatedEmojiButton> createState() => _AnimatedEmojiButtonState();
}

class _AnimatedEmojiButtonState extends State<_AnimatedEmojiButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  final String? imageUrl;
  final String? localPath;
  const _FullScreenImage({this.imageUrl, this.localPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: localPath != null ? Image.file(File(localPath!)) : Image.network(imageUrl!),
        ),
      ),
    );
  }
}
