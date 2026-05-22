import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/timetable_data.dart';

class YoutubeVideosPage extends StatelessWidget {
  final String courseName;
  final List videos;

  const YoutubeVideosPage({
    super.key,
    required this.courseName,
    required this.videos,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (videos.isEmpty) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: AcademicTheme.primary,
          title: Text("$courseName Videos", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined, 
                size: 100, 
                color: isDark ? Colors.white10 : Colors.black12
              ),
              const SizedBox(height: 24),
              Text(
                "No videos available", 
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary
                )
              ),
              const SizedBox(height: 8),
              Text(
                "Check back later for tutorials.", 
                style: TextStyle(
                  color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary
                )
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: AcademicTheme.primary,
        title: Text(
          "$courseName Videos",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];

          return GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('recent_title', video["title"]);
              await prefs.setString('recent_subtitle', "Watch again from $courseName");
              await prefs.setString('recent_type', 'video');
              await prefs.setString('recent_url', video["url"]);
              await prefs.setString('recent_course', courseName);

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
                    color: Colors.black.withOpacity(0.08),
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
                          color: Colors.black.withOpacity(0.2),
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
                              courseName,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AcademicTheme.darkTextSecondary : AcademicTheme.textSecondary,
                              ),
                            ),
                            const Spacer(),
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
                icon: const Icon(Icons.bookmark_border),
                onPressed: _saveBookmark,
              ),
            ],
          ),
          body: Center(
            child: player,
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Added to bookmarks")),
      );
    }
  }
}
