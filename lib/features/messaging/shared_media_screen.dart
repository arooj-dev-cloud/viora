import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class SharedMediaScreen extends StatefulWidget {
  const SharedMediaScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen> {
  late Future<List<Map<String, dynamic>>> _media;

  @override
  void initState() {
    super.initState();
    _media = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return const [];
    }
    return Supabase.instance.client
        .from('messages')
        .select('id,attachment_path,created_at')
        .eq('conversation_id', widget.conversationId)
        .not('attachment_path', 'is', null)
        .not('attachment_path', 'like', '%.m4a')
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<String> _signedUrl(String path) => Supabase.instance.client.storage
      .from('message-attachments')
      .createSignedUrl(path, 3600);

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _media = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the connection error.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Shared Media')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _media,
      builder: (context, snapshot) {
        if (!AppConfig.supabaseConfigured ||
            Supabase.instance.client.auth.currentUser == null) {
          return const Center(child: Text('Sign in to see shared media.'));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Shared media could not load. Check your connection.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Photos and videos shared here will appear here.',
              style: TextStyle(color: VioraColors.silver),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final path = items[index]['attachment_path'] as String;
              return FutureBuilder<String>(
                future: _signedUrl(path),
                builder: (context, url) {
                  if (!url.hasData) {
                    return const ColoredBox(
                      color: Color(0xFF291733),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  return InkWell(
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => _MediaViewer(url: url.data!, tag: path),
                      ),
                    ),
                    child: Hero(
                      tag: path,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (path.toLowerCase().endsWith('.mp4'))
                            const ColoredBox(
                              color: Color(0xFF291733),
                              child: Icon(Icons.movie_outlined, size: 38),
                            )
                          else
                            Image.network(
                              url.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Color(0xFF291733),
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          if (path.toLowerCase().endsWith('.mp4'))
                            const Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.play_circle_fill, size: 24),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    ),
  );
}

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({required this.url, required this.tag});
  final String url;
  final String tag;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.tag.toLowerCase().endsWith('.mp4')) {
      _video = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      title: const Text('Shared Media'),
    ),
    body: Center(
      child: widget.tag.toLowerCase().endsWith('.mp4')
          ? _video == null || !_video!.value.isInitialized
                ? const CircularProgressIndicator()
                : GestureDetector(
                    onTap: () => setState(
                      () => _video!.value.isPlaying
                          ? _video!.pause()
                          : _video!.play(),
                    ),
                    child: Hero(
                      tag: widget.tag,
                      child: AspectRatio(
                        aspectRatio: _video!.value.aspectRatio,
                        child: VideoPlayer(_video!),
                      ),
                    ),
                  )
          : InteractiveViewer(
              child: Hero(
                tag: widget.tag,
                child: Image.network(widget.url, fit: BoxFit.contain),
              ),
            ),
    ),
  );
}
