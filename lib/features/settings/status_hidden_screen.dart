import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/viora_theme.dart';
import '../../data/repositories/messaging_repository.dart';

/// Choose people who must not see your status (Vibes).
class StatusHiddenFromScreen extends StatefulWidget {
  const StatusHiddenFromScreen({super.key});

  @override
  State<StatusHiddenFromScreen> createState() => _StatusHiddenFromScreenState();
}

class _StatusHiddenFromScreenState extends State<StatusHiddenFromScreen> {
  final _client = Supabase.instance.client;
  final Map<String, String> _people = {};
  final Set<String> _hidden = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final me = _client.auth.currentUser?.id;
    if (me == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final chats = await MessagingRepository(_client).myConversations();
      for (final c in chats) {
        if (!c.isGroup && c.peerUserId != null) {
          _people[c.peerUserId!] = c.title;
        }
      }
      final rows = await _client
          .from('status_hidden_from')
          .select('hidden_user_id')
          .eq('owner_id', me);
      _hidden.addAll(rows.map((r) => r['hidden_user_id'] as String));
    } catch (_) {
      _error = 'Could not load. Run sql/viora_v4.sql in Supabase.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String userId, bool hide) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      if (hide) {
        await _client.from('status_hidden_from').upsert({
          'owner_id': me,
          'hidden_user_id': userId,
        });
        _hidden.add(userId);
      } else {
        await _client
            .from('status_hidden_from')
            .delete()
            .eq('owner_id', me)
            .eq('hidden_user_id', userId);
        _hidden.remove(userId);
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Run sql/viora_v4.sql.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hide my status from')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
        : _people.isEmpty
        ? const Center(
            child: Text(
              'Start a chat first, then you can hide your status from people.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VioraColors.silver),
            ),
          )
        : ListView(
            children: [
              for (final entry in _people.entries)
                CheckboxListTile(
                  value: _hidden.contains(entry.key),
                  title: Text(entry.value),
                  secondary: CircleAvatar(
                    backgroundColor: VioraColors.mauve,
                    child: Text(entry.value.characters.first.toUpperCase()),
                  ),
                  onChanged: (v) => _toggle(entry.key, v ?? false),
                ),
            ],
          ),
  );
}
