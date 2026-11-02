import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/viora_theme.dart';
import '../../data/repositories/messaging_repository.dart';
import 'shared_media_screen.dart';

/// WhatsApp-style contact details: photo, name, about, shared media, actions.
class ContactInfoScreen extends StatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.conversationId,
    required this.peerId,
    required this.title,
    required this.onCall,
    required this.onMute,
    required this.onBlock,
    this.onTitleChanged,
  });
  final String conversationId;
  final String peerId;
  final String title;
  final void Function(bool video) onCall;
  final VoidCallback onMute;
  final VoidCallback onBlock;
  final void Function(String? name)? onTitleChanged;

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  String? _name;
  String? _nickname;
  String? _username;
  String? _about;
  String? _avatarUrl;
  int _mediaCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    try {
      final rows = await client.rpc(
        'get_contact_info',
        params: {'p_user_id': widget.peerId},
      );
      final list = rows as List;
      if (list.isNotEmpty) {
        final row = Map<String, dynamic>.from(list.first as Map);
        _name = (row['display_name'] as String?)?.trim();
        _username = row['username'] as String?;
        _about = (row['bio'] as String?)?.trim();
        final path = row['avatar_path'] as String?;
        if (path != null && path.isNotEmpty) {
          try {
            _avatarUrl = await client.storage
                .from('profile-media')
                .createSignedUrl(path, 3600);
          } on StorageException {
            // initials avatar
          }
        }
      }
    } catch (_) {
      // Run sql/viora_v4.sql for the full details; the title still shows.
    }
    try {
      _nickname = await MessagingRepository(client).nicknameFor(widget.peerId);
    } catch (_) {}
    try {
      final media = await client
          .from('messages')
          .select('id')
          .eq('conversation_id', widget.conversationId)
          .not('attachment_path', 'is', null)
          .not('attachment_path', 'like', '%.m4a');
      _mediaCount = (media as List).length;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String get _realName =>
      (_name?.isNotEmpty == true) ? _name! : widget.title;

  Future<void> _editName() async {
    final controller = TextEditingController(text: _nickname ?? _realName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Name only you can see',
          ),
        ),
        actions: [
          if (_nickname != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, ''),
              child: const Text('Reset'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Not disposed here: the dialog is still animating closed and a
    // disposed controller would crash (_dependents.isEmpty assertion).
    if (result == null) return;
    try {
      await MessagingRepository(
        Supabase.instance.client,
      ).setNickname(widget.peerId, result);
      final clean = result.trim();
      if (!mounted) return;
      setState(() => _nickname = clean.isEmpty ? null : clean);
      widget.onTitleChanged?.call(clean.isEmpty ? _realName : clean);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save. Run sql/viora_v5_nicknames.sql.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _nickname ?? _realName;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact info'),
        actions: [
          IconButton(
            tooltip: 'Edit name',
            onPressed: _editName,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          const SizedBox(height: 24),
          Center(
            child: CircleAvatar(
              radius: 58,
              backgroundColor: VioraColors.mauve,
              backgroundImage:
                  _avatarUrl == null ? null : NetworkImage(_avatarUrl!),
              child: _avatarUrl == null
                  ? Text(
                      name.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 44),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          if (_nickname != null && _nickname != _realName)
            Center(
              child: Text(
                'Viora name: $_realName',
                style: const TextStyle(color: VioraColors.silver, fontSize: 12),
              ),
            ),
          if (_username != null)
            Center(
              child: Text(
                '@$_username',
                style: const TextStyle(color: VioraColors.silver),
              ),
            ),
          Center(
            child: TextButton.icon(
              onPressed: _editName,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit name'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Action(
                icon: Icons.call_rounded,
                label: 'Voice',
                onTap: () {
                  Navigator.pop(context);
                  widget.onCall(false);
                },
              ),
              const SizedBox(width: 12),
              _Action(
                icon: Icons.videocam_rounded,
                label: 'Video',
                onTap: () {
                  Navigator.pop(context);
                  widget.onCall(true);
                },
              ),
              const SizedBox(width: 12),
              _Action(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Message',
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const _Label('ABOUT'),
            ListTile(
              title: Text(
                (_about?.isNotEmpty == true) ? _about! : 'Hey there! I am using Viora.',
              ),
            ),
          ],
          const _Label('MEDIA, LINKS AND DOCS'),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Media, files and links'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_mediaCount',
                  style: const TextStyle(color: VioraColors.silver),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SharedMediaScreen(
                  conversationId: widget.conversationId,
                ),
              ),
            ),
          ),
          const _Label('PRIVACY'),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Mute notifications'),
            onTap: widget.onMute,
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.redAccent),
            title: Text(
              'Block $name',
              style: const TextStyle(color: Colors.redAccent),
            ),
            onTap: widget.onBlock,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
    child: Text(
      text,
      style: const TextStyle(
        color: VioraColors.silver,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    ),
  );
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
      width: 92,
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
