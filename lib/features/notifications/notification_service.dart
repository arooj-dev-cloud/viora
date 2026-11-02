import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VioraNotificationService {
  VioraNotificationService(this._client);
  final SupabaseClient _client;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  RealtimeChannel? _channel;
  String? _activeUserId;
  bool _initialized = false;

  bool get _supportsLocalAlerts =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    if (_activeUserId == userId && _channel != null) return;
    await stop();
    _activeUserId = userId;

    if (_supportsLocalAlerts) {
      await _initializeLocalNotifications();
    }
    _channel = _client
        .channel('viora-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (payload) =>
              unawaited(_handleNotification(payload.newRecord)),
        )
        .subscribe();
  }

  Future<void> _initializeLocalNotifications() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(settings);
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } catch (_) {
      // Permission prompt is best effort; in-app notifications still work.
    }
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'viora_messages',
        'Viora messages',
        description: 'New message and call alerts while Viora is open',
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  Future<void> _handleNotification(Map<String, dynamic> row) async {
    if (!_supportsLocalAlerts || !_initialized) return;
    final userId = _activeUserId;
    if (userId == null) return;
    try {
      final preference = await _client
          .from('notification_preferences')
          .select('local_alerts_enabled')
          .eq('user_id', userId)
          .maybeSingle();
      if (preference?['local_alerts_enabled'] == false) return;
      await _local.show(
        (row['id'] as String).hashCode & 0x7fffffff,
        row['title'] as String? ?? 'Viora',
        row['body'] as String? ?? 'You have a new notification.',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'viora_messages',
            'Viora messages',
            channelDescription:
                'New message and call alerts while Viora is open',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: row['entity_id'] as String?,
      );
    } catch (_) {
      // The in-app notification remains available even if the OS alert is unavailable.
    }
  }

  Future<bool> setLocalAlertsEnabled(bool enabled) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    if (enabled) {
      if (!_supportsLocalAlerts) return false;
      await _initializeLocalNotifications();
      final granted = await _requestOsPermission();
      if (!granted) return false;
    }
    await _client.from('notification_preferences').upsert({
      'user_id': userId,
      'local_alerts_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  Future<bool> _requestOsPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final result = await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return result == true;
    }
    final result = await _local
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    return result == true;
  }

  Future<bool> localAlertsEnabled() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await _client
        .from('notification_preferences')
        .select('local_alerts_enabled')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['local_alerts_enabled'] != false;
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _activeUserId = null;
    if (channel != null) await _client.removeChannel(channel);
  }
}
