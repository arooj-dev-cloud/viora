import 'status_hidden_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';
import '../notifications/notifications_screen.dart';
import '../messaging/call_history_screen.dart';
import '../messaging/saved_messages_screen.dart';
import 'chat_preferences_screen.dart';
import 'muted_conversations_screen.dart';
import 'blocked_users_screen.dart';
import 'report_problem_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        const _SectionLabel('ACCOUNT'),
        _SettingsTile(
          icon: Icons.person_outline,
          title: 'Account',
          subtitle: 'Profile and sign-in details',
          onTap: () => _showInfo(
            context,
            'Account settings',
            'Your account details are managed through your Viora profile and Supabase authentication.',
          ),
        ),
        _SettingsTile(
          icon: Icons.shield_outlined,
          title: 'Privacy',
          subtitle: 'Control your visibility and safety',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrivacySafetyScreen()),
          ),
        ),
        _SettingsTile(
          icon: Icons.notifications_none,
          title: 'Notifications',
          subtitle: 'Message and group alerts',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const NotificationPreferencesScreen(),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.call_outlined,
          title: 'Call History',
          subtitle: 'Incoming, outgoing, and missed calls',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
          ),
        ),
        _SettingsTile(
          icon: Icons.bookmark_outline,
          title: 'Saved Messages',
          subtitle: 'Keep messages for later',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SavedMessagesScreen()),
          ),
        ),
        const SizedBox(height: 18),
        const _SectionLabel('PREFERENCES'),
        _SettingsTile(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Midnight theme',
          onTap: () => _showInfo(
            context,
            'Appearance',
            'Viora currently uses its midnight plum theme.',
          ),
        ),
        _SettingsTile(
          icon: Icons.chat_bubble_outline,
          title: 'Chat Settings',
          subtitle: 'Messages and keyboard behavior',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatPreferencesScreen()),
          ),
        ),
        _SettingsTile(
          icon: Icons.language,
          title: 'Language',
          subtitle: 'English',
          onTap: () =>
              _showInfo(context, 'Language', 'English is currently selected.'),
        ),
        const SizedBox(height: 18),
        const _SectionLabel('SUPPORT'),
        _SettingsTile(
          icon: Icons.help_outline,
          title: 'Help & Support',
          onTap: () => _showInfo(
            context,
            'Help & Support',
            'Contact and help-center links will be configured before release.',
          ),
        ),
        _SettingsTile(
          icon: Icons.info_outline,
          title: 'About Viora',
          subtitle: 'Version 1.0.0',
          onTap: () =>
              _showInfo(context, 'About Viora', 'Viora — more than messages.'),
        ),
      ],
    ),
  );
}

class PrivacySafetyScreen extends StatefulWidget {
  const PrivacySafetyScreen({super.key});
  @override
  State<PrivacySafetyScreen> createState() => _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends State<PrivacySafetyScreen> {
  String _lastSeen = 'Everyone';
  String _photo = 'Everyone';
  String _about = 'Everyone';
  String _status = 'Everyone';
  bool _readReceipts = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final row = await Supabase.instance.client
          .from('privacy_settings')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted && row != null) {
        setState(() {
          _lastSeen = row['last_seen_visibility'] as String? ?? 'Everyone';
          _photo = row['profile_photo_visibility'] as String? ?? 'Everyone';
          _about = row['about_visibility'] as String? ?? 'Everyone';
          _status = row['status_visibility'] as String? ?? 'Everyone';
          _readReceipts = row['read_receipts'] as bool? ?? true;
        });
      }
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Privacy settings could not be loaded.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings({
    String? lastSeen,
    String? photo,
    String? about,
    String? status,
    bool? readReceipts,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (!AppConfig.supabaseConfigured || userId == null) {
      _showMessage('Sign in to save privacy settings.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('privacy_settings').upsert({
        'user_id': userId,
        'last_seen_visibility': lastSeen ?? _lastSeen,
        'profile_photo_visibility': photo ?? _photo,
        'about_visibility': about ?? _about,
        'status_visibility': status ?? _status,
        'read_receipts': readReceipts ?? _readReceipts,
      });
      if (!mounted) return;
      setState(() {
        if (lastSeen != null) _lastSeen = lastSeen;
        if (photo != null) _photo = photo;
        if (about != null) _about = about;
        if (status != null) _status = status;
        if (readReceipts != null) _readReceipts = readReceipts;
      });
    } on PostgrestException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Privacy settings could not be saved.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _choose(
    String title,
    String value,
    ValueChanged<String> onChanged,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF24132F),
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: value,
          onChanged: (next) => Navigator.pop(context, next),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(title, style: const TextStyle(fontSize: 18)),
              ),
              for (final option in ['Everyone', 'My Contacts', 'Nobody'])
                RadioListTile<String>(value: option, title: Text(option)),
            ],
          ),
        ),
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & Safety')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const _SectionLabel('WHO CAN SEE'),
              if (!AppConfig.supabaseConfigured ||
                  Supabase.instance.client.auth.currentUser == null)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Sign in to persist privacy settings.',
                    style: TextStyle(color: VioraColors.silver),
                  ),
                ),
              _PrivacyChoice(
                title: 'Last Seen & Online',
                value: _lastSeen,
                onTap: _saving
                    ? () {}
                    : () => _choose(
                        'Last Seen & Online',
                        _lastSeen,
                        (value) => _saveSettings(lastSeen: value),
                      ),
              ),
              _PrivacyChoice(
                title: 'Profile Photo',
                value: _photo,
                onTap: _saving
                    ? () {}
                    : () => _choose(
                        'Profile Photo',
                        _photo,
                        (value) => _saveSettings(photo: value),
                      ),
              ),
              _PrivacyChoice(
                title: 'About',
                value: _about,
                onTap: _saving
                    ? () {}
                    : () => _choose(
                        'About',
                        _about,
                        (value) => _saveSettings(about: value),
                      ),
              ),
              _PrivacyChoice(
                title: 'Status (Vibes)',
                value: _status,
                onTap: _saving
                    ? () {}
                    : () => _choose(
                        'Who can see my status',
                        _status,
                        (value) => _saveSettings(status: value),
                      ),
              ),
              _SettingsTile(
                icon: Icons.visibility_off_outlined,
                title: 'Hide my status from…',
                subtitle: 'Choose people who can not see your status',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StatusHiddenFromScreen(),
                  ),
                ),
              ),
              SwitchListTile(
                value: _readReceipts,
                activeThumbColor: VioraColors.blush,
                title: const Text('Read Receipts'),
                subtitle: const Text(
                  'Let people know when you have read messages',
                ),
                onChanged: _saving
                    ? null
                    : (value) => _saveSettings(readReceipts: value),
              ),
              const SizedBox(height: 18),
              const _SectionLabel('SAFETY'),
              _SettingsTile(
                icon: Icons.block_outlined,
                title: 'Blocked Users',
                subtitle: 'Manage blocked accounts',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                ),
              ),
              _SettingsTile(
                icon: Icons.volume_off_outlined,
                title: 'Muted Chats',
                subtitle: 'Manage muted conversations',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MutedConversationsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.report_gmailerrorred_outlined,
                title: 'Report a Problem',
                subtitle: 'Send feedback to Viora support',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportProblemScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms & Policies',
                onTap: () => _showInfo(
                  context,
                  'Terms & Policies',
                  'Add the published Viora policy links before release.',
                ),
              ),
            ],
          ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    leading: Icon(icon, color: VioraColors.blush),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: const TextStyle(color: VioraColors.silver, fontSize: 12),
          ),
    trailing: const Icon(Icons.chevron_right, color: VioraColors.silver),
    onTap: onTap,
  );
}

class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({
    required this.title,
    required this.value,
    required this.onTap,
  });
  final String title;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(
      value,
      style: const TextStyle(color: VioraColors.silver, fontSize: 12),
    ),
    trailing: const Icon(Icons.chevron_right, color: VioraColors.silver),
    onTap: onTap,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
    child: Text(
      title,
      style: const TextStyle(
        color: VioraColors.blush,
        fontSize: 11,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

void _showInfo(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
