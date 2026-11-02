import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push notifications for when Viora is closed or in the background.
/// If Firebase is not configured yet, everything here quietly does nothing
/// and the app keeps working (alerts then only arrive while the app is open).
class PushService {
  PushService._();
  static bool _ready = false;
  static bool _listening = false;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> register(SupabaseClient client) async {
    if (!_ready) return;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      final token = await messaging.getToken();
      if (token != null) await _save(client, userId, token);
      if (!_listening) {
        _listening = true;
        messaging.onTokenRefresh.listen((fresh) {
          final id = client.auth.currentUser?.id;
          if (id != null) _save(client, id, fresh);
        });
      }
    } catch (_) {
      // Push is optional; never block the app.
    }
  }

  static Future<void> _save(
    SupabaseClient client,
    String userId,
    String token,
  ) async {
    try {
      await client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (_) {
      // Run sql/viora_push.sql to create the device_tokens table.
    }
  }
}
