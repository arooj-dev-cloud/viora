import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';
import '../../data/repositories/messaging_repository.dart';
import 'call_screen.dart';

/// WhatsApp-style call log: who called, incoming / outgoing / missed, when,
/// and a button to call the person back.
class CallsTab extends StatefulWidget {
  const CallsTab({super.key, this.active = true});

  /// Set to true while the tab is visible so the log refreshes when opened.
  final bool active;

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallEntry {
  const _CallEntry({
    required this.id,
    required this.peerId,
    required this.name,
    required this.avatarUrl,
    required this.video,
    required this.outgoing,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String peerId;
  final String name;
  final String? avatarUrl;
  final bool video;
  final bool outgoing;
  final String status;
  final DateTime? createdAt;

  bool get _stale =>
      status == 'ringing' &&
          createdAt != null &&
          DateTime.now().difference(createdAt!.toLocal()).inMinutes >= 2;

  bool get missed => status == 'missed' || _stale;
  bool get declined => status == 'rejected';

  /// Red, like WhatsApp, only for calls the signed-in person did not answer.
  bool get missedIncoming => !outgoing && missed;

  String get label {
    if (declined) return 'Declined';
    if (missed) return outgoing ? 'No answer' : 'Missed';
    return outgoing ? 'Outgoing' : 'Incoming';
  }
}

class _CallsTabState extends State<CallsTab> {
  late Future<List<_CallEntry>> _calls;
  RealtimeChannel? _channel;
  Timer? _debounce;
  final Set<String> _calling = <String>{};
  final Set<String> _selected = <String>{};
  List<_CallEntry> _current = const [];
  bool _onlyMissed = false;

  bool get _selecting => _selected.isNotEmpty;

  Future<void> _deleteIds(Set<String> ids, {bool all = false}) async {
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(all ? 'Clear call history?' : 'Delete ${ids.length} call(s)?'),
        content: const Text('This only removes them from your call log.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final client = Supabase.instance.client;
    final me = client.auth.currentUser?.id;
    if (me == null) return;
    try {
      await client.from('call_log_hidden').upsert(
        [for (final id in ids) {'call_id': id, 'user_id': me}],
        onConflict: 'call_id,user_id',
        ignoreDuplicates: true,
      );
      if (!mounted) return;
      setState(_selected.clear);
      _reload();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete. Run sql/viora_v3.sql in Supabase SQL Editor.'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _calls = _load();
    _subscribe();
  }

  @override
  void didUpdateWidget(CallsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
  }

  void _subscribe() {
    if (!AppConfig.supabaseConfigured) return;
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    _channel = Supabase.instance.client
        .channel('viora-call-log-$me')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'call_sessions',
      callback: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _reload();
        });
      },
    )
        .subscribe();
  }

  Future<List<_CallEntry>> _load() async {
    if (!AppConfig.supabaseConfigured) return const [];
    final client = Supabase.instance.client;
    final me = client.auth.currentUser?.id;
    if (me == null) return const [];
    final fetched = await client
        .from('call_sessions')
        .select('id,caller_id,callee_id,media_type,status,created_at')
        .or('caller_id.eq.$me,callee_id.eq.$me')
        .order('created_at', ascending: false)
        .limit(100);
    final rows = List<Map<String, dynamic>>.from(fetched);

    var hidden = <String>{};
    try {
      final h = await client
          .from('call_log_hidden')
          .select('call_id')
          .eq('user_id', me);
      hidden = h.map((r) => r['call_id'] as String).toSet();
    } catch (_) {
      // Run sql/viora_v3.sql to enable deleting call logs.
    }
    rows.removeWhere((r) => hidden.contains(r['id'] as String));

    final peerIds = <String>{};
    for (final row in rows) {
      final peer =
      (row['caller_id'] == me ? row['callee_id'] : row['caller_id'])
      as String?;
      if (peer != null) peerIds.add(peer);
    }

    final profiles = <String, Map<String, dynamic>>{};
    if (peerIds.isNotEmpty) {
      try {
        final people = await client
            .from('discoverable_profiles')
            .select('id,display_name,username,avatar_path')
            .inFilter('id', peerIds.toList());
        for (final person in people) {
          profiles[person['id'] as String] = Map<String, dynamic>.from(person);
        }
        await Future.wait(
          profiles.values.map((profile) async {
            final path = profile['avatar_path'] as String?;
            if (path == null || path.isEmpty) return;
            try {
              profile['avatar_url'] = await client.storage
                  .from('profile-media')
                  .createSignedUrl(path, 3600);
            } on StorageException {
              // The initials avatar is used when private media is unavailable.
            }
          }),
        );
      } on Object {
        // Names fall back to "Viora user" if profiles cannot be read.
      }
    }

    final entries = <_CallEntry>[];
    for (final row in rows) {
      final outgoing = row['caller_id'] == me;
      final peer = (outgoing ? row['callee_id'] : row['caller_id']) as String?;
      if (peer == null) continue;
      final profile = profiles[peer];
      var name = (profile?['display_name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        final username = profile?['username'] as String?;
        name = username == null || username.isEmpty
            ? 'Viora user'
            : '@$username';
      }
      entries.add(
        _CallEntry(
          id: row['id'] as String,
          peerId: peer,
          name: name,
          avatarUrl: profile?['avatar_url'] as String?,
          video: row['media_type'] == 'video',
          outgoing: outgoing,
          status: row['status'] as String? ?? 'ended',
          createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
        ),
      );
    }
    return entries;
  }

  void _reload() {
    final next = _load();
    setState(() {
      _calls = next;
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _calls = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the error state.
    }
  }

  Future<void> _callBack(_CallEntry entry) async {
    if (CallScreen.isCallActive || !_calling.add(entry.peerId)) return;
    try {
      final conversationId = await MessagingRepository(
        Supabase.instance.client,
      ).openDirectConversation(entry.peerId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            incoming: false,
            participantName: entry.name,
            avatarUrl: entry.avatarUrl,
            conversationId: conversationId,
            calleeId: entry.peerId,
            mediaType: entry.video ? 'video' : 'audio',
          ),
        ),
      );
      if (mounted) _reload();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start call: $error')));
      }
    } finally {
      _calling.remove(entry.peerId);
    }
  }

  String _when(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final now = DateTime.now();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final clock =
        '$hour:${local.minute.toString().padLeft(2, '0')} ${local.hour >= 12 ? 'PM' : 'AM'}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today, $clock';
    if (diff == 1) return 'Yesterday, $clock';
    return '${local.day}/${local.month}/${local.year}, $clock';
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      return const Center(child: Text('Sign in to see your calls.'));
    }
    return FutureBuilder<List<_CallEntry>>(
      future: _calls,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_outlined,
                  size: 40,
                  color: VioraColors.silver,
                ),
                const SizedBox(height: 12),
                const Text('Calls could not load.'),
                TextButton(onPressed: _reload, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allEntries = snapshot.data!;
        _current = allEntries;
        final entries = _onlyMissed
            ? [for (final e in allEntries) if (e.missedIncoming) e]
            : allEntries;
        if (allEntries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.call_outlined,
                    size: 44,
                    color: VioraColors.silver,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'No calls yet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Voice and video calls you make or receive will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VioraColors.silver),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 8, 0),
              child: Row(
                children: [
                  if (_selecting)
                    Text(
                      '${_selected.length} selected',
                      style: const TextStyle(
                        color: VioraColors.silver,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else ...[
                    ChoiceChip(
                      label: const Text('All'),
                      selected: !_onlyMissed,
                      onSelected: (_) => setState(() => _onlyMissed = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Missed'),
                      selected: _onlyMissed,
                      onSelected: (_) => setState(() => _onlyMissed = true),
                    ),
                  ],
                  const Spacer(),
                  if (_selecting) ...[
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: () => setState(_selected.clear),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton(
                      tooltip: 'Delete selected',
                      onPressed: () => _deleteIds(Set.of(_selected)),
                      icon: const Icon(Icons.delete_outline, color: Colors.pinkAccent),
                    ),
                  ] else
                    TextButton.icon(
                      onPressed: () => _deleteIds(_current.map((e) => e.id).toSet(), all: true),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            if (entries.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No missed calls',
                    style: TextStyle(color: VioraColors.silver),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 2, bottom: 24),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final red = entry.missedIncoming;
                      final picked = _selected.contains(entry.id);
                      return Dismissible(
                        key: ValueKey(entry.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red.withValues(alpha: .7),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline),
                        ),
                        confirmDismiss: (_) async {
                          await _deleteIds({entry.id});
                          return false;
                        },
                        child: ListTile(
                          selected: picked,
                          selectedTileColor: Colors.white.withValues(alpha: .08),
                          onLongPress: () => setState(() => _selected.add(entry.id)),
                          onTap: _selecting
                              ? () => setState(() {
                            if (!_selected.remove(entry.id)) _selected.add(entry.id);
                          })
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 3,
                          ),
                          leading: CircleAvatar(
                            radius: 25,
                            backgroundColor: VioraColors.mauve,
                            backgroundImage: entry.avatarUrl == null
                                ? null
                                : NetworkImage(entry.avatarUrl!),
                            child: entry.avatarUrl == null
                                ? Text(entry.name.characters.first.toUpperCase())
                                : null,
                          ),
                          title: Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: red ? Colors.redAccent : null,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                entry.outgoing
                                    ? Icons.call_made_rounded
                                    : Icons.call_received_rounded,
                                size: 15,
                                color: red || entry.missed || entry.declined
                                    ? Colors.redAccent
                                    : const Color(0xFF4ADE80),
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  '${entry.label} · ${_when(entry.createdAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: VioraColors.silver,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: picked
                              ? const Icon(Icons.check_circle, color: Color(0xFF4ADE80))
                              : IconButton(
                            tooltip: entry.video ? 'Video call' : 'Voice call',
                            onPressed: () => _callBack(entry),
                            icon: Icon(
                              entry.video
                                  ? Icons.videocam_outlined
                                  : Icons.call_outlined,
                              color: VioraColors.blush,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}