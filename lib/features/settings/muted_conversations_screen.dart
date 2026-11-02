import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class MutedConversationsScreen extends StatefulWidget {
  const MutedConversationsScreen({super.key});

  @override
  State<MutedConversationsScreen> createState() =>
      _MutedConversationsScreenState();
}

class _MutedConversationsScreenState extends State<MutedConversationsScreen> {
  late Future<List<Map<String, dynamic>>> _muted;

  @override
  void initState() {
    super.initState();
    _muted = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AppConfig.supabaseConfigured) return const [];
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    final mutedRows = await client
        .from('muted_conversations')
        .select('conversation_id,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    if (mutedRows.isEmpty) return const [];
    final previews = await client.rpc('list_my_conversations');
    final names = <String, String>{
      for (final row in previews)
        row['conversation_id'] as String:
            row['display_title'] as String? ?? 'Chat',
    };
    return mutedRows
        .map(
          (row) => {
            ...row,
            'title': names[row['conversation_id']] ?? 'Viora conversation',
          },
        )
        .toList();
  }

  void _reload() {
    final next = _load();
    setState(() {
      _muted = next;
    });
  }

  Future<void> _unmute(String conversationId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('muted_conversations')
          .delete()
          .eq('user_id', userId)
          .eq('conversation_id', conversationId);
      if (mounted) _reload();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Muted Chats')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _muted,
      builder: (context, snapshot) {
        if (!AppConfig.supabaseConfigured ||
            Supabase.instance.client.auth.currentUser == null) {
          return const Center(child: Text('Sign in to manage muted chats.'));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load muted chats. Apply migration 0014.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'You have no muted chats.',
              style: TextStyle(color: VioraColors.silver),
            ),
          );
        }
        return ListView.separated(
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final row = snapshot.data![index];
            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: VioraColors.charcoal,
                child: Icon(Icons.volume_off_outlined),
              ),
              title: Text(row['title'] as String),
              trailing: TextButton(
                onPressed: () => _unmute(row['conversation_id'] as String),
                child: const Text('Unmute'),
              ),
            );
          },
        );
      },
    ),
  );
}
