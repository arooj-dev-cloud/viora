import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

class ChatPreferencesScreen extends StatefulWidget {
  const ChatPreferencesScreen({super.key});

  @override
  State<ChatPreferencesScreen> createState() => _ChatPreferencesScreenState();
}

class _ChatPreferencesScreenState extends State<ChatPreferencesScreen> {
  bool _sendOnEnter = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (!AppConfig.supabaseConfigured || userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await client
          .from('chat_preferences')
          .select('send_on_enter')
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted && row != null) {
        setState(() => _sendOnEnter = row['send_on_enter'] as bool? ?? true);
      }
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setSendOnEnter(bool value) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (!AppConfig.supabaseConfigured || userId == null) {
      _message('Sign in to save chat preferences.');
      return;
    }
    setState(() => _saving = true);
    try {
      await client.from('chat_preferences').upsert({
        'user_id': userId,
        'send_on_enter': value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) setState(() => _sendOnEnter = value);
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Chat Settings')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  SwitchListTile(
                    value: _sendOnEnter,
                    onChanged: _saving || !AppConfig.supabaseConfigured
                        ? null
                        : _setSendOnEnter,
                    activeThumbColor: VioraColors.blush,
                    title: const Text('Enter key sends message'),
                    subtitle: const Text(
                      'Turn this off to use Enter for a new line in chat.',
                    ),
                  ),
                  if (!AppConfig.supabaseConfigured)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Configure Supabase and apply migration 0012 to save this preference.',
                        style: TextStyle(color: VioraColors.silver),
                      ),
                    ),
                ],
              ),
      );
}
