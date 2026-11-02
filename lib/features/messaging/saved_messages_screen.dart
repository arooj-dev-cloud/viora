import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({super.key});

  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  late Future<List<Map<String, dynamic>>> _saved;

  @override
  void initState() {
    super.initState();
    _saved = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AppConfig.supabaseConfigured) return const [];
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    return client
        .from('saved_messages')
        .select(
          'id,created_at,messages!saved_messages_message_id_fkey(id,conversation_id,sender_id,body,attachment_path,created_at)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _saved = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the connection error.
    }
  }

  Future<void> _remove(String id) async {
    try {
      await Supabase.instance.client
          .from('saved_messages')
          .delete()
          .eq('id', id);
      if (mounted) {
        final next = _load();
        setState(() {
          _saved = next;
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved Messages')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _saved,
      builder: (context, snapshot) {
        if (!AppConfig.supabaseConfigured ||
            Supabase.instance.client.auth.currentUser == null) {
          return const Center(child: Text('Sign in to see saved messages.'));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Saved messages could not load. Apply migration 0011.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'Long-press any chat message to save it.',
              style: TextStyle(color: VioraColors.silver),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
            itemBuilder: (context, index) {
              final saved = snapshot.data![index];
              final message = saved['messages'] as Map<String, dynamic>?;
              final body = (message?['body'] as String? ?? '').trim();
              final attachment = message?['attachment_path'] as String?;
              return ListTile(
                leading: const CircleAvatar(
                  backgroundColor: VioraColors.mauve,
                  child: Icon(Icons.bookmark_outline),
                ),
                title: Text(
                  body.isEmpty
                      ? (attachment == null
                            ? 'Message unavailable'
                            : 'Photo attachment')
                      : body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _time(saved['created_at'] as String?),
                  style: const TextStyle(
                    color: VioraColors.silver,
                    fontSize: 12,
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Remove saved message',
                  onPressed: () => _remove(saved['id'] as String),
                  icon: const Icon(Icons.bookmark_remove_outlined),
                ),
              );
            },
          ),
        );
      },
    ),
  );

  String _time(String? value) {
    final date = DateTime.tryParse(value ?? '')?.toLocal();
    if (date == null) return '';
    return '${date.month}/${date.day}/${date.year}';
  }
}
