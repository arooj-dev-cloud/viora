import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late Future<List<Map<String, dynamic>>> _users;

  @override
  void initState() {
    super.initState();
    _users = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AppConfig.supabaseConfigured) return const [];
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    final blocks = await client
        .from('blocked_users')
        .select('blocked_id,created_at')
        .eq('blocker_id', userId)
        .order('created_at', ascending: false);
    if (blocks.isEmpty) return const [];
    final ids = blocks.map((row) => row['blocked_id'] as String).toList();
    final profiles = await client
        .from('profiles')
        .select('id,display_name,username')
        .inFilter('id', ids);
    final byId = {for (final profile in profiles) profile['id']: profile};
    return blocks.map((row) {
      final profile = byId[row['blocked_id']];
      return {
        ...row,
        'display_name': profile?['display_name'] as String? ?? 'Viora user',
        'username': profile?['username'] as String?,
      };
    }).toList();
  }

  void _reload() {
    final next = _load();
    setState(() {
      _users = next;
    });
  }

  Future<void> _unblock(String id) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('blocked_users')
          .delete()
          .eq('blocker_id', userId)
          .eq('blocked_id', id);
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
    appBar: AppBar(title: const Text('Blocked Users')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _users,
      builder: (context, snapshot) {
        if (!AppConfig.supabaseConfigured ||
            Supabase.instance.client.auth.currentUser == null) {
          return const Center(child: Text('Sign in to manage blocked users.'));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text('Could not load blocked users. Apply migration 0010.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'You have not blocked anyone.',
              style: TextStyle(color: VioraColors.silver),
            ),
          );
        }
        return ListView.separated(
          itemCount: snapshot.data!.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) {
            final row = snapshot.data![index];
            final name = row['display_name'] as String;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: VioraColors.mauve,
                child: Text(name.isEmpty ? 'V' : name[0].toUpperCase()),
              ),
              title: Text(name),
              subtitle: row['username'] == null
                  ? null
                  : Text('@${row['username']}'),
              trailing: TextButton(
                onPressed: () => _unblock(row['blocked_id'] as String),
                child: const Text('Unblock'),
              ),
            );
          },
        );
      },
    ),
  );
}
