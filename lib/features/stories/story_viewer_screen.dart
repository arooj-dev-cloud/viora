import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/viora_theme.dart';
import '../../data/repositories/vibe_repository.dart';

/// Full-screen, WhatsApp-style story viewer for one person's active stories.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.stories});

  /// Oldest first. Each map: id, user_id, body, media_path, media_type,
  /// created_at, display_name, avatar_url, seen.
  final List<Map<String, dynamic>> stories;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  static const _imageDuration = Duration(seconds: 5);

  late int _index;
  Timer? _timer;
  double _progress = 0;
  bool _paused = false;
  String? _mediaUrl;
  VideoPlayerController? _video;
  bool _loadingMedia = false;
  Duration _currentDuration = _imageDuration;
  List<Map<String, dynamic>> _viewers = const [];

  Map<String, dynamic> get _story => widget.stories[_index];

  @override
  void initState() {
    super.initState();
    final firstUnseen = widget.stories.indexWhere((s) => s['seen'] != true);
    _index = firstUnseen < 0 ? 0 : firstUnseen;
    unawaited(_showCurrent());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _showCurrent() async {
    _timer?.cancel();
    await _video?.dispose();
    _video = null;
    _mediaUrl = null;
    _progress = 0;
    _currentDuration = _imageDuration;
    final story = _story;
    unawaited(_loadViewers());
    unawaited(
      VibeRepository(Supabase.instance.client).markSeen(
        story['id'] as String,
        story['user_id'] as String,
      ),
    );
    final path = story['media_path'] as String?;
    if (path == null) {
      if (mounted) setState(() {});
      _startTimer();
      return;
    }
    setState(() => _loadingMedia = true);
    try {
      final url = await Supabase.instance.client.storage
          .from('status-media')
          .createSignedUrl(path, 3600);
      if (!mounted) return;
      if (story['media_type'] == 'video') {
        final controller = VideoPlayerController.networkUrl(Uri.parse(url));
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        _video = controller;
        _currentDuration = controller.value.duration > Duration.zero
            ? controller.value.duration
            : _imageDuration;
        await controller.play();
      }
      setState(() {
        _mediaUrl = url;
        _loadingMedia = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMedia = false);
    }
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    const tick = Duration(milliseconds: 50);
    _timer = Timer.periodic(tick, (timer) {
      if (_paused || _loadingMedia || !mounted) return;
      final next =
          _progress + tick.inMilliseconds / _currentDuration.inMilliseconds;
      if (next >= 1) {
        timer.cancel();
        _next();
      } else {
        setState(() => _progress = next);
      }
    });
  }

  void _next() {
    if (_index >= widget.stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _index++);
    unawaited(_showCurrent());
  }

  void _previous() {
    if (_index == 0) {
      unawaited(_showCurrent());
      return;
    }
    setState(() => _index--);
    unawaited(_showCurrent());
  }

  void _setPaused(bool paused) {
    _paused = paused;
    final video = _video;
    if (video != null) {
      paused ? video.pause() : video.play();
    }
  }

  bool get _isMine =>
      _story['user_id'] == Supabase.instance.client.auth.currentUser?.id;

  Future<void> _loadViewers() async {
    if (!_isMine) {
      if (_viewers.isNotEmpty && mounted) setState(() => _viewers = const []);
      return;
    }
    final id = _story['id'] as String;
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_status_viewers',
        params: {'p_status_id': id},
      );
      if (!mounted || _story['id'] != id) return;
      setState(() {
        _viewers = (rows as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
      });
    } catch (_) {
      // Run sql/viora_v4.sql to enable "viewed by".
    }
  }

  Future<void> _showViewers() async {
    _setPaused(true);
    await _loadViewers();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _viewers.isEmpty
                      ? 'No views yet'
                      : 'Viewed by ${_viewers.length}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final v in _viewers)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: VioraColors.mauve,
                        child: Text(
                          ((v['display_name'] as String?)?.trim().isNotEmpty ==
                                      true
                                  ? v['display_name'] as String
                                  : '${v['username'] ?? 'V'}')
                              .characters
                              .first
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(
                        (v['display_name'] as String?)?.trim().isNotEmpty ==
                                true
                            ? v['display_name'] as String
                            : '@${v['username'] ?? 'viora_user'}',
                      ),
                      subtitle: Text(_age(v['viewed_at'] as String?)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    _setPaused(false);
  }

  /// Lets people remove their own Vibe, like "Delete status" in WhatsApp.
  Future<void> _deleteCurrent() async {
    _setPaused(true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this Vibe?'),
        content: const Text('It will be removed for everyone who can see it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      _setPaused(false);
      return;
    }
    final story = _story;
    final client = Supabase.instance.client;
    try {
      await client
          .from('vibes_statuses')
          .delete()
          .eq('id', story['id'] as String);
      final path = story['media_path'] as String?;
      if (path != null) {
        try {
          await client.storage.from('status-media').remove([path]);
        } catch (_) {
          // The Vibe is already gone; media cleanup is best effort.
        }
      }
      VibeSeenStore.bump();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      _setPaused(false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete Vibe: $error')));
    }
  }

  String _age(String? value) {
    final created = DateTime.tryParse(value ?? '')?.toLocal();
    if (created == null) return '';
    final diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    final name = story['display_name'] as String? ?? 'Viora user';
    final avatar = story['avatar_url'] as String?;
    final body = (story['body'] as String?) ?? '';
    final hasMedia = story['media_path'] != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (_) => _setPaused(true),
        onLongPressEnd: (_) => _setPaused(false),
        onTapUp: (details) {
          final width = MediaQuery.sizeOf(context).width;
          details.localPosition.dx < width / 3 ? _previous() : _next();
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).maybePop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!hasMedia)
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [VioraColors.mauve, VioraColors.midnight],
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      body.isEmpty ? '…' : body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else if (_loadingMedia || _mediaUrl == null)
              const Center(child: CircularProgressIndicator())
            else if (story['media_type'] == 'video' && _video != null)
              Center(
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                ),
              )
            else
              Image.network(
                _mediaUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            if (hasMedia && body.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 40, 20, 36),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.3),
                  ),
                ),
              ),
            if (_isMine)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: InkWell(
                    onTap: _showViewers,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.visibility_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _viewers.isEmpty
                                ? 'Viewed by'
                                : 'Viewed by ${_viewers.length}',
                          ),
                          const Icon(Icons.keyboard_arrow_up_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < widget.stories.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: LinearProgressIndicator(
                                value: i < _index
                                    ? 1
                                    : i == _index
                                    ? _progress
                                    : 0,
                                minHeight: 3,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: VioraColors.mauve,
                          backgroundImage: avatar == null
                              ? null
                              : NetworkImage(avatar),
                          child: avatar == null
                              ? Text(
                                  name.characters.first.toUpperCase(),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _age(story['created_at'] as String?),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: VioraColors.silver,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isMine)
                          IconButton(
                            tooltip: 'Delete Vibe',
                            onPressed: _deleteCurrent,
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
