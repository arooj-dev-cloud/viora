import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/viora_theme.dart';
import '../../data/repositories/messaging_repository.dart';

/// Group details: who is in the group, plus call buttons.
class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    required this.title,
    required this.onCall,
  });
  final String conversationId;
  final String title;
  final void Function(bool video) onCall;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final Future<List<Map<String, dynamic>>> _members =
      MessagingRepository(Supabase.instance.client).members(widget.conversationId);

  Future<void> _leaveOrDelete({required bool delete}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(delete ? 'Delete group?' : 'Exit group?'),
        content: Text(
          delete
              ? 'This deletes the group and all its messages for everyone.'
              : 'You will no longer receive messages from this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(delete ? 'Delete' : 'Exit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        delete ? 'delete_group' : 'leave_group',
        params: {'p_conversation_id': widget.conversationId},
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not complete that. Run sql/viora_v4.sql.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _members,
        builder: (context, snap) {
          final members = snap.data ?? const <Map<String, dynamic>>[];
          return ListView(
            padding: const EdgeInsets.only(bottom: 30),
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFB04AB5), Color(0xFF5B2A8C)],
                    ),
                  ),
                  child: const Icon(Icons.groups_2_rounded, size: 54),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Group · ${members.length} members',
                  style: const TextStyle(color: VioraColors.silver),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Action(
                    icon: Icons.call_rounded,
                    label: 'Voice',
                    onTap: () => widget.onCall(false),
                  ),
                  const SizedBox(width: 16),
                  _Action(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    onTap: () => widget.onCall(true),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 26, 20, 6),
                child: Text(
                  'MEMBERS',
                  style: TextStyle(
                    color: VioraColors.silver,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (snap.hasError)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Members could not load. Run sql/viora_v3.sql in Supabase.',
                    style: TextStyle(color: Colors.pinkAccent),
                  ),
                ),
              for (final m in members)
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
                  title: Text(m['user_id'] == me ? 'You' : m['name'] as String),
                  subtitle: m['username'] == null
                      ? null
                      : Text(
                          '@${m['username']}',
                          style: const TextStyle(color: VioraColors.silver),
                        ),
                ),
              const SizedBox(height: 18),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                title: const Text(
                  'Exit group',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => _leaveOrDelete(delete: false),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete group',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => _leaveOrDelete(delete: true),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Container(
      width: 96,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: VioraColors.blush),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );
}
