import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';
import 'notification_service.dart';
import '../messaging/call_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    if (!AppConfig.supabaseConfigured) return const [];
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const [];
    return Supabase.instance.client
        .from('user_notifications')
        .select('id,notification_type,title,body,entity_id,created_at,read_at')
        .eq('recipient_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
  }

  void _reload() {
    final next = _load();
    setState(() {
      _items = next;
    });
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _items = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder displays the connection error.
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await Supabase.instance.client
          .from('user_notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
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
    appBar: AppBar(title: const Text('Notifications')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snapshot) {
        if (!AppConfig.supabaseConfigured ||
            Supabase.instance.client.auth.currentUser == null) {
          return const Center(child: Text('Sign in to see notifications.'));
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Notifications could not be loaded. Apply the latest Supabase migrations.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'You’re all caught up.',
              style: TextStyle(color: VioraColors.silver),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: snapshot.data!.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final row = snapshot.data![index];
              final unread = row['read_at'] == null;
              final isCall = row['notification_type'] == 'call';
              final missedCall = (row['body'] as String? ?? '').startsWith(
                'Missed',
              );
              final incomingCall =
                  isCall &&
                  (row['body'] as String? ?? '').startsWith('Incoming');
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: unread
                      ? VioraColors.mauve
                      : VioraColors.charcoal,
                  child: Icon(
                    isCall
                        ? (missedCall
                              ? Icons.call_missed_outgoing
                              : Icons.call_made)
                        : Icons.chat_bubble_outline,
                  ),
                ),
                title: Text(
                  row['title'] as String? ?? 'Viora',
                  style: TextStyle(
                    fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  row['body'] as String? ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: unread
                    ? const Icon(
                        Icons.circle,
                        size: 9,
                        color: VioraColors.blush,
                      )
                    : null,
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await _markRead(row['id'] as String);
                  if (incomingCall && mounted && row['entity_id'] is String) {
                    await navigator.push(
                      MaterialPageRoute<void>(
                        builder: (_) => CallScreen(
                          callId: row['entity_id'] as String,
                          incoming: true,
                          participantName: row['title'] as String?,
                        ),
                      ),
                    );
                  }
                },
              );
            },
          ),
        );
      },
    ),
  );
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});
  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AppConfig.supabaseConfigured ||
        Supabase.instance.client.auth.currentUser == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      _enabled = await VioraNotificationService(
        Supabase.instance.client,
      ).localAlertsEnabled();
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _saving = true);
    try {
      final result = await VioraNotificationService(
        Supabase.instance.client,
      ).setLocalAlertsEnabled(value);
      if (!mounted) return;
      if (result) {
        setState(() => _enabled = value);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OS notification permission was not granted.'),
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            children: [
              SwitchListTile(
                value: _enabled,
                onChanged:
                    _saving ||
                        !AppConfig.supabaseConfigured ||
                        kIsWeb ||
                        (defaultTargetPlatform != TargetPlatform.android &&
                            defaultTargetPlatform != TargetPlatform.iOS)
                    ? null
                    : _setEnabled,
                activeThumbColor: VioraColors.blush,
                title: const Text('Local alerts while Viora is open'),
                subtitle: const Text(
                  'Notification history syncs through Supabase. Local alerts work on Android/iOS while the app is active.',
                ),
              ),
              if (!AppConfig.supabaseConfigured)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Add your Supabase credentials and apply migrations 0006 and 0007 first.',
                    style: TextStyle(color: VioraColors.silver),
                  ),
                ),
            ],
          ),
  );
}
