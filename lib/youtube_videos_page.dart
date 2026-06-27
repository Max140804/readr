import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/timetable_data.dart';
import 'services/activity_service.dart';
import 'services/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'assistant_page.dart';

class YoutubeVideosPage extends StatefulWidget {
  final String courseName;
  final List videos;
  final bool isAdmin;

  const YoutubeVideosPage({
    super.key,
    required this.courseName,
    required this.videos,
    this.isAdmin = false,
  });

  @override
  State<YoutubeVideosPage> createState() => _YoutubeVideosPageState();
}

class _YoutubeVideosPageState extends State<YoutubeVideosPage> {
  late List filteredVideos;
  bool isSearching = false;
  final TextEditingController searchController = TextEditingController();
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    filteredVideos = widget.videos;
  }

  @override
  void didUpdateWidget(YoutubeVideosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videos != oldWidget.videos) {
      filteredVideos = widget.videos;
    }
  }

  void filterSearch(String query) {
    setState(() {
      filteredVideos = widget.videos
          .where((v) => v["title"].toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _onRefresh() async {
    try {
      final response = await _supabase
          .from('videos')
          .select()
          .eq('course', widget.courseName);
      
      final List firestoreVideos = (response as List).map((data) => {
        "id": data['id'],
        "title": data['title'],
        "url": data['url'],
        "thumbnail": data['thumbnail'] ?? "https://img.youtube.com/vi/${YoutubePlayer.convertUrlToId(data['url'])}/0.jpg",
        "isDynamic": true
      }).toList();

      final staticVideos = widget.videos.where((v) => v['isDynamic'] != true).toList();
      
      setState(() {
        final List allVideos = [...staticVideos];
        for (var item in firestoreVideos) {
          if (!allVideos.any((v) => v['url'] == item['url'])) {
            allVideos.add(item);
          }
        }
        filteredVideos = allVideos;
        if (isSearching && searchController.text.isNotEmpty) {
          filterSearch(searchController.text);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Refresh failed: $e")));
      }
    }
  }

  Future<void> _deleteVideo(Map video) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Video?"),
        content: Text("Are you sure you want to delete '${video['title']}'?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (video['id'] != null) {
          await _supabase.from('videos').delete().eq('id', video['id']);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video deleted")));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cannot delete static local videos")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appBarColor = isDark ? AcademicTheme.darkCard : AcademicTheme.primary;
    final titleColor = isDark ? AcademicTheme.darkPrimary : Colors.white;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        title: isSearching
            ? TextField(
                controller: searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "Search videos...",
                  hintStyle: TextStyle(color: titleColor.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: titleColor),
                onChanged: filterSearch,
              )
            : Text(
                "${widget.courseName} Videos", 
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)
              ),
        iconTheme: IconThemeData(color: titleColor),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isSearching ? Icons.close : Icons.search, color: titleColor),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  filteredVideos = widget.videos;
                }
              });
            },
          ),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            child: filteredVideos.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.video_library_outlined, 
                            size: 100, 
                            color: isDark ? Colors.white10 : Colors.black12
                          ),
                          const SizedBox(height: 24),
                          Text(
                            isSearching ? "No matching videos found." : "No videos available", 
                            style: TextStyle(
                              fontSize: 20, 
                              fontWeight: FontWeight.bold,
                              color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary
                            )
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Check back later or pull down to refresh.", 
                            style: TextStyle(
                              color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary
                            )
                          ),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredVideos.length,
                    itemBuilder: (context, index) {
                    final video = filteredVideos[index];

                    return GestureDetector(
                      onTap: () async {
                        await ActivityService().trackActivity(
                          title: video["title"]!,
                          subtitle: "Watch again from ${widget.courseName}",
                          type: 'video',
                          url: video["url"]!,
                          course: widget.courseName,
                        );

                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoPlayerPage(
                                videoUrl: video["url"]!,
                                title: video["title"]!,
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        decoration: BoxDecoration(
                          color: isDark ? AcademicTheme.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(25),
                                  ),
                                  child: Image.network(
                                    video["thumbnail"]!,
                                    height: 200,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Container(
                                  height: 200,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                                  ),
                                ),
                                const CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.white24,
                                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 45),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video["title"]!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.video_collection_outlined, size: 14, color: AcademicTheme.accent),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.courseName,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (widget.isAdmin && video['id'] != null)
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () => _deleteVideo(video),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        )
                                      else
                                        const Icon(Icons.more_vert, color: Colors.grey),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerPage({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late YoutubePlayerController controller;

  @override
  void initState() {
    super.initState();
    String? videoId = YoutubePlayer.convertUrlToId(widget.videoUrl);
    if (videoId == null) {
      if (widget.videoUrl.contains("v=")) {
        videoId = widget.videoUrl.split("v=").last.split("&").first;
      } else if (widget.videoUrl.contains("youtu.be/")) {
        videoId = widget.videoUrl.split("youtu.be/").last.split("?").first;
      }
    }

    controller = YoutubePlayerController(
      initialVideoId: videoId ?? "",
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        isLive: false,
        forceHD: false,
        enableCaption: true,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: controller,
        showVideoProgressIndicator: true,
        progressIndicatorColor: AcademicTheme.accent,
      ),
      builder: (context, player) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(widget.title, style: const TextStyle(fontSize: 16)),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.auto_awesome),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AssistantPage(
                        youtubeUrl: widget.videoUrl,
                        initialPrompt: "I am watching this video: '${widget.title}'. Can you help me summarize it or explain the key concepts discussed?",
                      ),
                    ),
                  );
                },
                tooltip: "Ask AI",
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_border),
                onPressed: _saveBookmark,
              ),
            ],
          ),
          body: Center(
            child: player,
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AssistantPage(
                    youtubeUrl: widget.videoUrl,
                    initialPrompt: "I am watching this video: '${widget.title}'. Can you help me summarize it or explain the key concepts discussed?",
                  ),
                ),
              );
            },
            backgroundColor: AcademicTheme.primary,
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
        );
      },
    );
  }

  Future<void> _saveBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    final String? bookmarksJson = prefs.getString('bookmarks');
    List<Map<String, dynamic>> bookmarks = [];
    if (bookmarksJson != null) {
      bookmarks = List<Map<String, dynamic>>.from(jsonDecode(bookmarksJson));
    }

    final exists = bookmarks.any((b) => b['url'] == widget.videoUrl);
    if (exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Already bookmarked!")),
        );
      }
      return;
    }

    bookmarks.add({
      'title': widget.title,
      'url': widget.videoUrl,
      'type': 'video',
      'course': 'General',
    });

    await prefs.setString('bookmarks', jsonEncode(bookmarks));
    SyncService().pushToCloud();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Added to bookmarks")),
      );
    }
  }
}
