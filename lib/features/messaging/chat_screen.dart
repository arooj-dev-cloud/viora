import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../core/config/app_config.dart';
import '../../core/services/gallery_service.dart';
import '../../core/theme/viora_theme.dart';
import '../../data/models/message_ordering.dart';
import '../../data/repositories/messaging_repository.dart';
import 'contact_info_screen.dart';
import 'group_info_screen.dart';
import 'call_screen.dart';
import 'shared_media_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.isGroup = false,
    this.memberCount = 2,
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final int memberCount;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  late final Stream<List<Map<String, dynamic>>> _messageStream;
  bool _sending = false;
  bool _sendOnEnter = true;
  String? _sendError;
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  bool _hasText = false;
  final Set<String> _hidden = <String>{};
  RealtimeChannel? _hideChannel;
  List<Map<String, dynamic>> _calls = <Map<String, dynamic>>[];
  RealtimeChannel? _callLogChannel;
  Timer? _callLogDebounce;
  Map<String, String> _memberNames = <String, String>{};
  Map<String, Map<String, dynamic>> _memberInfo = <String, Map<String, dynamic>>{};
  RealtimeChannel? _typingChannel;
  bool _peerTyping = false;
  Timer? _typingOff;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  int _wallpaper = 0;
  bool _searching = false;
  String _query = '';
  String? _peerId;
  String? _titleOverride;
  String get _title => _titleOverride ?? widget.title;
  String _presence = '';
  Timer? _presenceTimer;
  Timer? _readDebounce;
  Set<String> _readIds = <String>{};
  List<String> _myIds = <String>[];
  RealtimeChannel? _readChannel;
  late final MessagingRepository _repo = MessagingRepository(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _messageStream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', widget.conversationId)
        .order('created_at', ascending: false);
    _loadChatPreferences();
    _loadHiddenMessages();
    _loadCalls();
    _loadMembers();
    _subscribeReads();
    _setupTyping();
    _loadWallpaper();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
      if (hasText) _sendTyping();
    });
  }

  // ---- Typing indicator (Realtime broadcast, no database needed) ----
  void _setupTyping() {
    if (!AppConfig.supabaseConfigured) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    _typingChannel = Supabase.instance.client
        .channel('viora-typing-${widget.conversationId}')
        .onBroadcast(
      event: 'typing',
      callback: (payload) {
        if (payload['user'] == me || !mounted) return;
        setState(() => _peerTyping = true);
        _typingOff?.cancel();
        _typingOff = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _peerTyping = false);
        });
      },
    )
        .subscribe();
  }

  void _sendTyping() {
    final channel = _typingChannel;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (channel == null || me == null) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2000) return;
    _lastTypingSent = now;
    try {
      unawaited(
        channel
            .sendBroadcastMessage(event: 'typing', payload: {'user': me})
            .catchError((Object _) {}),
      );
    } catch (_) {}
  }

  // ---- Chat wallpaper (saved on this phone) ----
  static const List<List<Color>?> _wallpapers = [
    null,
    [Color(0xFF1A0B29), Color(0xFF3A1650)],
    [Color(0xFF06202B), Color(0xFF0F4C5C)],
    [Color(0xFF0B1F14), Color(0xFF1F5D3B)],
    [Color(0xFF2B0B1F), Color(0xFF7A2E4F)],
    [Color(0xFF0B1230), Color(0xFF4B2A8C)],
    [Color(0xFF111111), Color(0xFF2A2A2A)],
  ];

  Future<void> _loadWallpaper() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('viora_wallpaper_${widget.conversationId}') ?? 0;
      if (mounted) setState(() => _wallpaper = saved);
    } catch (_) {}
  }

  Future<void> _pickWallpaper() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chat wallpaper',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (var i = 0; i < _wallpapers.length; i++)
                    GestureDetector(
                      onTap: () => Navigator.pop(sheetContext, i),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: _wallpapers[i] == null
                              ? null
                              : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _wallpapers[i]!,
                          ),
                          color: _wallpapers[i] == null
                              ? const Color(0xFF200636)
                              : null,
                          border: Border.all(
                            color: _wallpaper == i
                                ? VioraColors.blush
                                : Colors.white24,
                            width: _wallpaper == i ? 3 : 1,
                          ),
                        ),
                        child: _wallpapers[i] == null
                            ? const Icon(Icons.block, size: 20)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _wallpaper = choice);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('viora_wallpaper_${widget.conversationId}', choice);
    } catch (_) {}
  }

  BoxDecoration _wallpaperDecoration(BuildContext context) {
    final colors = _wallpapers[_wallpaper.clamp(0, _wallpapers.length - 1)];
    if (colors == null) {
      return BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor);
    }
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ),
    );
  }

  Future<void> _loadMembers() async {
    if (!AppConfig.supabaseConfigured) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    try {
      final list = await _repo.members(widget.conversationId);
      final names = <String, String>{};
      final info = <String, Map<String, dynamic>>{};
      for (final m in list) {
        names[m['user_id'] as String] = m['name'] as String;
        info[m['user_id'] as String] = m;
      }
      String? peer;
      for (final id in names.keys) {
        if (id != me) peer = id;
      }
      if (!mounted) return;
      setState(() {
        _memberNames = names;
        _memberInfo = info;
        if (!widget.isGroup) _peerId = peer;
      });
      if (!widget.isGroup && peer != null) {
        _refreshPresence();
        _presenceTimer = Timer.periodic(
          const Duration(seconds: 30),
              (_) => _refreshPresence(),
        );
      }
    } catch (_) {
      // Names fall back to a short id until the v3 SQL is applied.
    }
  }

  Future<void> _refreshPresence() async {
    final peer = _peerId;
    if (peer == null) return;
    final seen = await _repo.lastSeen(peer);
    if (!mounted) return;
    setState(() => _presence = _presenceText(seen));
  }

  String _presenceText(DateTime? seen) {
    if (seen == null) return '';
    final local = seen.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inSeconds < 75) return 'online';
    final now = DateTime.now();
    final clock = _formatTime(seen.toIso8601String());
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final d = today.difference(day).inDays;
    if (d == 0) return 'last seen today at $clock';
    if (d == 1) return 'last seen yesterday at $clock';
    return 'last seen ${local.day}/${local.month}/${local.year}';
  }

  void _subscribeReads() {
    if (!AppConfig.supabaseConfigured) return;
    _readChannel = Supabase.instance.client
        .channel('viora-reads-${widget.conversationId}')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reads',
      callback: (_) => _loadReads(),
    )
        .subscribe();
  }

  Future<void> _loadReads() async {
    if (_myIds.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('message_reads')
          .select('message_id')
          .inFilter('message_id', _myIds);
      final counts = <String, int>{};
      for (final r in rows) {
        final id = r['message_id'] as String;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      final needed = widget.isGroup ? (widget.memberCount - 1).clamp(1, 999) : 1;
      final done = counts.entries
          .where((e) => e.value >= needed)
          .map((e) => e.key)
          .toSet();
      if (mounted && done.length != _readIds.length) {
        setState(() => _readIds = done);
      }
    } catch (_) {}
  }

  void _onMessages(List<Map<String, dynamic>> data, String? me) {
    final mine = data
        .where((m) => m['sender_id'] == me && m['deleted_at'] == null)
        .map((m) => m['id'] as String)
        .toList();
    final hasIncoming = data.any((m) => m['sender_id'] != me);
    if (mine.length != _myIds.length) {
      _myIds = mine;
      _readDebounce?.cancel();
      _readDebounce = Timer(const Duration(milliseconds: 300), _loadReads);
    }
    if (hasIncoming) {
      _readDebounce?.cancel();
      _readDebounce = Timer(const Duration(milliseconds: 400), () {
        _repo.markRead(widget.conversationId);
        _loadReads();
      });
    }
  }

  Future<void> _pickMemberToCall({required bool video}) async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    final others = _memberInfo.values.where((m) => m['user_id'] != me).toList();
    if (others.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members to call yet.')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                video ? 'Video call who?' : 'Call who?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            for (final m in others)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: VioraColors.mauve,
                  backgroundImage: m['avatar_url'] == null
                      ? null
                      : NetworkImage(m['avatar_url'] as String),
                  child: m['avatar_url'] == null
                      ? Text((m['name'] as String).characters.first.toUpperCase())
                      : null,
                ),
                title: Text(m['name'] as String),
                trailing: Icon(video ? Icons.videocam_outlined : Icons.call_outlined),
                onTap: () => Navigator.pop(c, m),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final convo = await _repo.openDirectConversation(picked['user_id'] as String);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            incoming: false,
            participantName: picked['name'] as String,
            conversationId: convo,
            calleeId: picked['user_id'] as String,
            mediaType: video ? 'video' : 'audio',
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start call: $e')),
        );
      }
    }
  }

  Future<void> _loadHiddenMessages() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('message_deletions')
          .select('message_id')
          .eq('user_id', userId);
      if (mounted) {
        setState(() => _hidden.addAll(rows.map((r) => r['message_id'] as String)));
      }
      // Keeps "delete for me" in sync across the user's own devices.
      _hideChannel = Supabase.instance.client
          .channel('viora-hidden-$userId-${widget.conversationId}')
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'message_deletions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final id = payload.newRecord['message_id'] as String?;
          if (id != null && mounted) setState(() => _hidden.add(id));
        },
      )
          .subscribe();
    } catch (_) {
      // Run sql/viora_upgrade.sql to enable "delete for me".
    }
  }

  /// Calls with this person are shown inside the chat, like WhatsApp
  /// ("Missed voice call", "Video call", ...).
  Future<void> _loadCalls() async {
    if (widget.isGroup || !AppConfig.supabaseConfigured) return;
    final client = Supabase.instance.client;
    final me = client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final members = await client
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', widget.conversationId);
      String? peer;
      for (final member in members) {
        if (member['user_id'] != me) peer = member['user_id'] as String?;
      }
      if (peer == null) return;
      final rows = await client
          .from('call_sessions')
          .select('id,caller_id,callee_id,media_type,status,created_at')
          .or(
        'and(caller_id.eq.$me,callee_id.eq.$peer),'
            'and(caller_id.eq.$peer,callee_id.eq.$me)',
      )
          .order('created_at', ascending: false)
          .limit(50);
      final entries = <Map<String, dynamic>>[];
      for (final row in rows) {
        final created = DateTime.tryParse(row['created_at'] as String? ?? '');
        var status = row['status'] as String? ?? 'ended';
        if (status == 'ringing') {
          // Still ringing: not part of the history yet, unless it was never
          // finished and is clearly stale.
          if (created == null ||
              DateTime.now().difference(created.toLocal()).inMinutes < 2) {
            continue;
          }
          status = 'missed';
        }
        final outgoing = row['caller_id'] == me;
        final video = row['media_type'] == 'video';
        final kind = video ? 'video call' : 'voice call';
        String label;
        var missed = false;
        if (status == 'missed') {
          label = outgoing ? 'No answer' : 'Missed $kind';
          missed = !outgoing;
        } else if (status == 'rejected') {
          label = outgoing ? 'Call declined' : 'Declined $kind';
        } else {
          label = '${outgoing ? 'Outgoing' : 'Incoming'} $kind';
        }
        entries.add({
          'id': 'call-${row['id']}',
          '_call': true,
          'created_at': row['created_at'],
          'video': video,
          'missed': missed,
          'label': label,
        });
      }
      if (mounted) setState(() => _calls = entries);
      _callLogChannel ??= client
          .channel('viora-chat-calls-${widget.conversationId}')
          .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'call_sessions',
        callback: (_) {
          _callLogDebounce?.cancel();
          _callLogDebounce = Timer(const Duration(milliseconds: 500), () {
            if (mounted) _loadCalls();
          });
        },
      )
          .subscribe();
    } catch (_) {
      // Calls simply do not appear in the chat if they cannot be loaded.
    }
  }

  Future<void> _loadChatPreferences() async {
    if (!AppConfig.supabaseConfigured) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('chat_preferences')
          .select('send_on_enter')
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted && row != null) {
        setState(() => _sendOnEnter = row['send_on_enter'] as bool? ?? true);
      }
    } catch (_) {
      // Keep the default until migration 0012 has been applied.
    }
  }

  @override
  void dispose() {
    _typingOff?.cancel();
    final typingChannel = _typingChannel;
    if (typingChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(typingChannel));
    }
    _presenceTimer?.cancel();
    _readDebounce?.cancel();
    final readChannel = _readChannel;
    if (readChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(readChannel));
    }
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    final channel = _hideChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    _callLogDebounce?.cancel();
    final callLogChannel = _callLogChannel;
    if (callLogChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(callLogChannel));
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _controller.text.trim();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (body.isEmpty || userId == null || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': body,
      });
      if (!mounted) return;
      _controller.clear();
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
              () =>
          _sendError = 'Message could not be sent. Check your connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveMessage(String messageId) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await client
          .from('saved_messages')
          .upsert(
        {'user_id': userId, 'message_id': messageId},
        onConflict: 'user_id,message_id',
        ignoreDuplicates: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to your messages.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _editMessage(String messageId, String body) async {
    final controller = TextEditingController(text: body);
    final replacement = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          maxLength: 4000,
          decoration: const InputDecoration(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (replacement == null || replacement.isEmpty || replacement == body) {
      return;
    }
    try {
      await Supabase.instance.client
          .from('messages')
          .update({
        'body': replacement,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      })
          .eq('id', messageId);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deleteMessage(
      String messageId,
      String? attachmentPath, {
        required bool mine,
      }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Delete message?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete for everyone'),
                onTap: () => Navigator.pop(sheetContext, 'everyone'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () => Navigator.pop(sheetContext, 'me'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    try {
      if (choice == 'me') {
        if (userId == null) return;
        await client.from('message_deletions').upsert(
          {'message_id': messageId, 'user_id': userId},
          onConflict: 'message_id,user_id',
          ignoreDuplicates: true,
        );
        if (mounted) setState(() => _hidden.add(messageId));
        return;
      }
      await _deleteForEveryone(messageId, attachmentPath);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  /// WhatsApp-style "Delete for everyone": the message stays in the chat as
  /// "This message was deleted" for both people and its media is removed.
  Future<void> _deleteForEveryone(
      String messageId,
      String? attachmentPath,
      ) async {
    final client = Supabase.instance.client;
    var path = attachmentPath;
    try {
      final result = await client.rpc(
        'delete_message_for_everyone',
        params: {'p_message_id': messageId},
      );
      if (result is String && result.isNotEmpty) path = result;
    } on PostgrestException {
      // The upgrade SQL has not been applied: fall back to a plain delete,
      // and say so clearly when the database refuses it too.
      final removed = await client
          .from('messages')
          .delete()
          .eq('id', messageId)
          .select('id');
      if (removed.isEmpty) {
        throw const FormatException(
          'Delete for everyone is not enabled on the server yet. '
              'Run sql/viora_whatsapp_upgrade.sql in the Supabase SQL Editor.',
        );
      }
    }
    if (path != null) {
      try {
        await client.storage.from('message-attachments').remove([path]);
      } catch (_) {
        // The message is already gone; storage cleanup is best effort.
      }
    }
  }

  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          setState(() => _sendError = 'Allow microphone access to send voice messages.');
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/viora_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
        path: path,
      );
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
      setState(() {
        _recording = true;
        _recordSeconds = 0;
        _sendError = null;
      });
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Could not start recording.');
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _finishRecordingAndSend() async {
    _recordTimer?.cancel();
    final seconds = _recordSeconds;
    String? filePath;
    try {
      filePath = await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (filePath == null) return;
    final file = File(filePath);
    if (seconds < 1) {
      if (await file.exists()) await file.delete();
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    String? uploadedPath;
    try {
      final bytes = await file.readAsBytes();
      final path = '${widget.conversationId}/$userId/${const Uuid().v4()}.m4a';
      await Supabase.instance.client.storage
          .from('message-attachments')
          .uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'audio/mp4'),
      );
      uploadedPath = path;
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': '',
        'attachment_path': path,
      });
      uploadedPath = null;
    } on StorageException catch (error) {
      if (mounted) setState(() => _sendError = 'Voice upload failed: ${error.message}');
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _sendError = 'Voice message could not be sent.');
      }
    } finally {
      if (uploadedPath != null) {
        try {
          await Supabase.instance.client.storage
              .from('message-attachments')
              .remove([uploadedPath]);
        } catch (_) {}
      }
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => _sending = false);
    }
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _saveToGallery(String path) async {
    final ok = await GalleryService.saveAttachment(path, force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Saved to your gallery.'
              : 'Could not save to gallery: ${GalleryService.lastError ?? 'unknown error'}',
        ),
      ),
    );
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final current = await client
          .from('message_reactions')
          .select('emoji')
          .eq('message_id', messageId)
          .eq('user_id', userId)
          .maybeSingle();
      if (current?['emoji'] == emoji) {
        await client
            .from('message_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', userId);
      } else if (current != null) {
        await client
            .from('message_reactions')
            .update({'emoji': emoji})
            .eq('message_id', messageId)
            .eq('user_id', userId);
      } else {
        await client.from('message_reactions').insert({
          'message_id': messageId,
          'user_id': userId,
          'emoji': emoji,
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _startCall({required bool video}) async {
    if (widget.isGroup) {
      await _pickMemberToCall(video: video);
      return;
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final members = await Supabase.instance.client
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', widget.conversationId);
      final peer =
      members.cast<Map<String, dynamic>>().firstWhere(
            (member) => member['user_id'] != userId,
        orElse: () => <String, dynamic>{},
      )['user_id']
      as String?;
      if (peer == null) {
        throw StateError('The other person is not in this chat.');
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            incoming: false,
            participantName: _title,
            conversationId: widget.conversationId,
            calleeId: peer,
            mediaType: video ? 'video' : 'audio',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start call: $error')));
      }
    }
  }

  Future<void> _blockPeer() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final members = await client
          .from('conversation_members')
          .select('user_id')
          .eq('conversation_id', widget.conversationId);
      final peerId =
      members.cast<Map<String, dynamic>>().firstWhere(
            (member) => member['user_id'] != userId,
        orElse: () => <String, dynamic>{},
      )['user_id']
      as String?;
      if (peerId == null) throw StateError('Could not find the other person.');
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Block $_title?'),
          content: const Text(
            'They will no longer be able to exchange messages with you in this direct chat.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await client.from('blocked_users').insert({
        'blocker_id': userId,
        'blocked_id': peerId,
      });
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('$_title blocked.')),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not block this account: $error')),
        );
      }
    }
  }

  Future<void> _muteConversation() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('muted_conversations')
          .upsert(
        {'user_id': userId, 'conversation_id': widget.conversationId},
        onConflict: 'user_id,conversation_id',
        ignoreDuplicates: true,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message alerts muted for this chat.')),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _pickAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, 'photo_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Choose a video'),
              onTap: () => Navigator.pop(context, 'video_gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || _sending) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    String? uploadedPath;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final isVideo = choice == 'video_gallery';
      final file = isVideo
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(
        source: choice == 'photo_camera'
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 25 MB.');
      }
      final extension = file.name.split('.').last.toLowerCase();
      const mimeTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'mp4': 'video/mp4',
      };
      final mimeType = mimeTypes[extension];
      if (mimeType == null || (isVideo && extension != 'mp4')) {
        throw FormatException(
          isVideo
              ? 'Choose an MP4 video.'
              : 'Choose a JPG, PNG, or WebP image.',
        );
      }
      final path =
          '${widget.conversationId}/$userId/${const Uuid().v4()}.$extension';
      await Supabase.instance.client.storage
          .from('message-attachments')
          .uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType),
      );
      uploadedPath = path;
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': userId,
        'body': '',
        'attachment_path': path,
      });
      uploadedPath = null;
      unawaited(
        GalleryService.saveSentBytes(path, bytes).then((error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error == null
                    ? 'Saved to your gallery.'
                    : 'Gallery save failed: $error',
              ),
            ),
          );
        }),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } on StorageException catch (error) {
      if (mounted) {
        setState(() => _sendError = 'Upload failed: ${error.message}');
      }
    } on PostgrestException catch (error) {
      if (mounted) setState(() => _sendError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
              () => _sendError = 'Image could not be sent. Check your connection.',
        );
      }
    } finally {
      if (uploadedPath != null) {
        try {
          await Supabase.instance.client.storage
              .from('message-attachments')
              .remove([uploadedPath]);
        } catch (_) {
          // The message may have failed; a later cleanup job can remove this orphan.
        }
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _searchField() => TextField(
    autofocus: true,
    onChanged: (v) => setState(() => _query = v.trim()),
    decoration: const InputDecoration(
      hintText: 'Search in this chat…',
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
    ),
  );

  void _openInfo() {
    if (widget.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupInfoScreen(
            conversationId: widget.conversationId,
            title: widget.title,
            onCall: (video) => _pickMemberToCall(video: video),
          ),
        ),
      );
      return;
    }
    final peer = _peerId;
    if (peer == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContactInfoScreen(
          conversationId: widget.conversationId,
          peerId: peer,
          title: _title,
          onTitleChanged: (name) {
            if (mounted) setState(() => _titleOverride = name);
          },
          onCall: (video) => _startCall(video: video),
          onMute: _muteConversation,
          onBlock: _blockPeer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id;
    return DecoratedBox(
        decoration: _wallpaperDecoration(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            leading: const BackButton(),
            titleSpacing: 0,
            title: _searching ? _searchField() : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _openInfo,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: VioraColors.mauve,
                    backgroundImage: !widget.isGroup && _peerId != null &&
                        _memberInfo[_peerId]?['avatar_url'] != null
                        ? NetworkImage(_memberInfo[_peerId]!['avatar_url'] as String)
                        : null,
                    child: widget.isGroup
                        ? const Icon(Icons.groups_2_rounded, size: 22)
                        : (_memberInfo[_peerId]?['avatar_url'] != null
                        ? null
                        : Text(_title.isEmpty ? 'V' : _title[0].toUpperCase())),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _peerTyping
                              ? 'typing…'
                              : widget.isGroup
                              ? (_memberNames.isEmpty
                              ? '${widget.memberCount} members · tap for info'
                              : _memberNames.values.join(', '))
                              : _presence,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _peerTyping ||
                                (_presence == 'online' && !widget.isGroup)
                                ? const Color(0xFF4ADE80)
                                : VioraColors.silver,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search in chat',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _query = '';
                }),
                icon: Icon(_searching ? Icons.close : Icons.search),
              ),
              if (!_searching)
                IconButton(
                  onPressed: () => _startCall(video: false),
                  tooltip: 'Voice call',
                  icon: const Icon(Icons.call_outlined),
                ),
              if (!_searching)
                IconButton(
                  onPressed: () => _startCall(video: true),
                  tooltip: 'Video call',
                  icon: const Icon(Icons.videocam_outlined),
                ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'block') _blockPeer();
                  if (value == 'mute') _muteConversation();
                  if (value == 'info') _openInfo();
                  if (value == 'wallpaper') _pickWallpaper();
                  if (value == 'media') {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SharedMediaScreen(
                          conversationId: widget.conversationId,
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'info',
                    child: Text(widget.isGroup ? 'Group info' : 'Contact info'),
                  ),
                  const PopupMenuItem(value: 'media', child: Text('Shared Media')),
                  const PopupMenuItem(
                    value: 'wallpaper',
                    child: Text('Chat wallpaper'),
                  ),
                  const PopupMenuItem(
                    value: 'mute',
                    child: Text('Mute message alerts'),
                  ),
                  if (!widget.isGroup)
                    const PopupMenuItem(
                      value: 'block',
                      child: Text('Block this person'),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _messageStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _ChatNotice(
                        icon: Icons.wifi_off_rounded,
                        message:
                        'Messages could not be loaded. Check your connection and Supabase setup.',
                        action: TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _onMessages(snapshot.data!, currentUserId),
                    );
                    final allMessages = newestMessagesFirst([
                      ...snapshot.data!.where((m) => !_hidden.contains(m['id'])),
                      ..._calls,
                    ]);
                    final messages = _query.isEmpty
                        ? allMessages
                        : allMessages
                        .where(
                          (m) =>
                      m['_call'] != true &&
                          ((m['body'] as String?) ?? '')
                              .toLowerCase()
                              .contains(_query.toLowerCase()),
                    )
                        .toList();
                    if (messages.isEmpty && _query.isNotEmpty) {
                      return const _ChatNotice(
                        icon: Icons.search_off_rounded,
                        message: 'No messages found.',
                      );
                    }
                    if (messages.isEmpty) {
                      return const _ChatNotice(
                        icon: Icons.auto_awesome_outlined,
                        message:
                        'This is the beginning of your conversation. Say hello.',
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        // The stream is sorted newest-first; reverse:true places
                        // item zero at the bottom, so messages read top-to-bottom
                        // in chronological order without reversing twice.
                        final message = messages[index];
                        if (message['_call'] == true) {
                          return _CallEvent(
                            label: message['label'] as String,
                            video: message['video'] == true,
                            missed: message['missed'] == true,
                            time: _formatTime(message['created_at'] as String?),
                          );
                        }
                        final mine = message['sender_id'] == currentUserId;
                        final deleted = message['deleted_at'] != null;
                        return _MessageBubble(
                          deleted: deleted,
                          messageId: message['id'] as String,
                          body: message['body'] as String? ?? '',
                          attachmentPath: message['attachment_path'] as String?,
                          mine: mine,
                          sender: _memberNames[message['sender_id']] ??
                              (message['sender_id'] as String? ?? '').substring(
                                0,
                                ((message['sender_id'] as String? ?? '').length > 6)
                                    ? 6
                                    : (message['sender_id'] as String? ?? '').length,
                              ),
                          read: _readIds.contains(message['id']),
                          showSender: widget.isGroup && !mine,
                          time: _formatTime(message['created_at'] as String?),
                          onSave: () => _saveMessage(message['id'] as String),
                          onEdit: mine && !deleted && (message['attachment_path'] == null)
                              ? () => _editMessage(
                            message['id'] as String,
                            message['body'] as String? ?? '',
                          )
                              : null,
                          onDelete: () => _deleteMessage(
                            message['id'] as String,
                            message['attachment_path'] as String?,
                            mine: mine && !deleted,
                          ),
                          onSaveToGallery: (!deleted &&
                              message['attachment_path'] is String &&
                              !GalleryService.isVoice(
                                message['attachment_path'] as String,
                              ))
                              ? () => _saveToGallery(
                            message['attachment_path'] as String,
                          )
                              : null,
                          edited: !deleted && message['edited_at'] != null,
                          currentUserId: currentUserId ?? '',
                          onReact: (emoji) =>
                              _toggleReaction(message['id'] as String, emoji),
                        );
                      },
                    );
                  },
                ),
              ),
              if (_sendError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _sendError!,
                      style: const TextStyle(
                        color: Colors.pinkAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: _recording
                      ? Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancel',
                        onPressed: _cancelRecording,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                      ),
                      const Icon(
                        Icons.fiber_manual_record,
                        color: Colors.redAccent,
                        size: 14,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recording  ${_clock(_recordSeconds)}',
                        style: const TextStyle(fontSize: 15),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Send voice message',
                        onPressed: _finishRecordingAndSend,
                        style: IconButton.styleFrom(
                          backgroundColor: VioraColors.mauve,
                        ),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  )
                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        onPressed: _sending ? null : _pickAttachment,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: _sendOnEnter
                              ? TextInputAction.send
                              : TextInputAction.newline,
                          onSubmitted: (_) {
                            if (_sendOnEnter) _send();
                          },
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            filled: true,
                            fillColor: VioraColors.charcoal,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending
                            ? null
                            : (_hasText ? _send : _startRecording),
                        style: IconButton.styleFrom(
                          backgroundColor: VioraColors.mauve,
                        ),
                        icon: _sending
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                            : Icon(
                          _hasText
                              ? Icons.arrow_upward_rounded
                              : Icons.mic_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  String _formatTime(String? value) {
    if (value == null) return '';
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Centered call entry inside the conversation (like WhatsApp).
class _CallEvent extends StatelessWidget {
  const _CallEvent({
    required this.label,
    required this.video,
    required this.missed,
    required this.time,
  });

  final String label;
  final bool video;
  final bool missed;
  final String time;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF24132F),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            video ? Icons.videocam_outlined : Icons.call_outlined,
            size: 16,
            color: missed ? Colors.redAccent : VioraColors.blush,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: missed ? Colors.redAccent : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            time,
            style: const TextStyle(color: VioraColors.silver, fontSize: 10),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.messageId,
    required this.body,
    this.attachmentPath,
    required this.mine,
    required this.sender,
    this.read = false,
    required this.showSender,
    required this.time,
    required this.onSave,
    this.onEdit,
    this.onDelete,
    this.onSaveToGallery,
    this.edited = false,
    this.deleted = false,
    required this.currentUserId,
    required this.onReact,
  });
  final String messageId;
  final String body;
  final String? attachmentPath;
  final bool mine;
  final String sender;
  final bool read;
  final bool showSender;
  final String time;
  final VoidCallback onSave;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSaveToGallery;
  final bool edited;
  final bool deleted;
  final String currentUserId;
  final ValueChanged<String> onReact;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  late final Stream<List<Map<String, dynamic>>> _reactions = Supabase
      .instance
      .client
      .from('message_reactions')
      .stream(primaryKey: ['message_id', 'user_id'])
      .eq('message_id', widget.messageId);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: _showActions,
    child: Align(
      alignment: widget.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 7),
        decoration: BoxDecoration(
          gradient: widget.mine
              ? const LinearGradient(
            colors: [Color(0xFF8E3A92), Color(0xFF6B2D8F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
              : null,
          color: widget.mine ? null : const Color(0xFF30223F),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(widget.mine ? 18 : 5),
            bottomRight: Radius.circular(widget.mine ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.showSender) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.sender,
                  style: const TextStyle(
                    color: VioraColors.blush,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 3),
            ],
            if (widget.deleted)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 15, color: Colors.white60),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'This message was deleted',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!widget.deleted && widget.body.isNotEmpty)
              Text(widget.body, style: const TextStyle(height: 1.3)),
            if (!widget.deleted && widget.attachmentPath != null) ...[
              if (widget.body.isNotEmpty) const SizedBox(height: 5),
              _PrivateAttachment(path: widget.attachmentPath!),
            ],
            if (!widget.deleted)
              _MessageReactions(
                stream: _reactions,
                currentUserId: widget.currentUserId,
                onReact: widget.onReact,
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.edited ? 'Edited · ' : ''}${widget.time}',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withValues(alpha: .65),
                  ),
                ),
                if (widget.mine && !widget.deleted) ...[
                  const SizedBox(width: 4),
                  Icon(
                    widget.read ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 15,
                    color: widget.read
                        ? const Color(0xFF53BDEB)
                        : Colors.white.withValues(alpha: .65),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Message options',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 27,
                    height: 24,
                  ),
                  onPressed: _showActions,
                  icon: const Icon(Icons.more_horiz, size: 17),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showActions() async {
    final selectedEmoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.deleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in ['❤️', '😂', '😮', '😢', '👏', '🔥'])
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext, emoji),
                        icon: Text(emoji, style: const TextStyle(fontSize: 23)),
                      ),
                  ],
                ),
              ),
            if (widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit message'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onEdit!();
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onDelete!();
                },
              ),
            if (widget.onSaveToGallery != null)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Save to gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSaveToGallery!();
                },
              ),
            if (!widget.deleted)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Save message'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSave();
                },
              ),
          ],
        ),
      ),
    );
    if (selectedEmoji != null) widget.onReact(selectedEmoji);
  }
}

class _MessageReactions extends StatelessWidget {
  const _MessageReactions({
    required this.stream,
    required this.currentUserId,
    required this.onReact,
  });

  final Stream<List<Map<String, dynamic>>> stream;
  final String currentUserId;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) return const SizedBox.shrink();
          final grouped = <String, List<Map<String, dynamic>>>{};
          for (final row in rows) {
            grouped.putIfAbsent(row['emoji'] as String, () => []).add(row);
          }
          return Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final entry in grouped.entries)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    label: Text('${entry.key} ${entry.value.length}'),
                    backgroundColor:
                    entry.value.any(
                          (row) => row['user_id'] == currentUserId,
                    )
                        ? VioraColors.plum
                        : const Color(0xFF24132F),
                    onPressed: () => onReact(entry.key),
                  ),
              ],
            ),
          );
        },
      );
}

class _PrivateAttachment extends StatefulWidget {
  const _PrivateAttachment({required this.path});
  final String path;
  @override
  State<_PrivateAttachment> createState() => _PrivateAttachmentState();
}

class _PrivateAttachmentState extends State<_PrivateAttachment> {
  late Future<String> _url;
  @override
  void initState() {
    super.initState();
    _url = _createUrl();
    // Received (and sent) photos/videos are copied to the phone gallery once.
    if (GalleryService.isImage(widget.path) ||
        GalleryService.isVideo(widget.path)) {
      unawaited(GalleryService.saveAttachment(widget.path));
    }
  }

  Future<String> _createUrl() => Supabase.instance.client.storage
      .from('message-attachments')
      .createSignedUrl(widget.path, 3600);

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 180,
          height: 120,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      if (GalleryService.isVoice(widget.path)) {
        return _VoiceMessage(url: snapshot.data!);
      }
      if (widget.path.toLowerCase().endsWith('.mp4')) {
        return _PrivateVideo(url: snapshot.data!);
      }
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ImageViewer(url: snapshot.data!),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            snapshot.data!,
            width: 220,
            height: 170,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const SizedBox(
              width: 180,
              height: 80,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      );
    },
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
    ),
    body: Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image_outlined, size: 48),
        ),
      ),
    ),
  );
}

class _PrivateVideo extends StatefulWidget {
  const _PrivateVideo({required this.url});
  final String url;

  @override
  State<_PrivateVideo> createState() => _PrivateVideoState();
}

class _PrivateVideoState extends State<_PrivateVideo> {
  late final VideoPlayerController _controller =
  VideoPlayerController.networkUrl(Uri.parse(widget.url))
    ..initialize().then((_) {
      if (mounted) setState(() {});
    });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(
          () => _controller.value.isPlaying
          ? _controller.pause()
          : _controller.play(),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 220,
        height: 170,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_controller.value.isInitialized)
              SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            else
              const ColoredBox(
                color: Color(0xFF1A1022),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            if (!_controller.value.isPlaying)
              const CircleAvatar(
                backgroundColor: Color(0xAA180D20),
                child: Icon(Icons.play_arrow_rounded, size: 30),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ChatNotice extends StatelessWidget {
  const _ChatNotice({required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: VioraColors.blush.withValues(alpha: .8)),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VioraColors.silver),
          ),
          if (action != null) action!,
        ],
      ),
    ),
  );
}

class _VoiceMessage extends StatefulWidget {
  const _VoiceMessage({required this.url});
  final String url;

  @override
  State<_VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<_VoiceMessage> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _state = state);
      }))
      ..add(_player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }))
      ..add(_player.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }))
      ..add(_player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else if (_state == PlayerState.paused) {
      await _player.resume();
    } else {
      await _player.play(UrlSource(widget.url));
      await _player.setPlaybackRate(_speed);
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speed == 1.0 ? 1.5 : (_speed == 1.5 ? 2.0 : 1.0);
    setState(() => _speed = next);
    try {
      await _player.setPlaybackRate(next);
    } catch (_) {}
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final value = (_position.inMilliseconds / total).clamp(0.0, 1.0);
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          IconButton(
            onPressed: _toggle,
            icon: Icon(
              _state == PlayerState.playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              size: 36,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _state == PlayerState.stopped &&
                            _duration == Duration.zero
                            ? 'Voice message'
                            : '${_fmt(_position)} / ${_fmt(_duration)}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cycleSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_speed == _speed.roundToDouble() ? _speed.toInt() : _speed}x',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}