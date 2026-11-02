import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'features/notifications/push_service.dart';

/// Runs when a push arrives while the app is closed or in the background.
/// Messages that carry a `notification` block are shown by Android itself.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  final inviteUrl = dotenv.env['VIORA_INVITE_URL']?.trim();
  if (inviteUrl != null && inviteUrl.isNotEmpty) {
    AppConfig.inviteUrl = inviteUrl;
  }
  final url = dotenv.env['SUPABASE_URL'] ?? '';
  final key = dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ?? '';
  if (url.startsWith('https://') &&
      key.isNotEmpty &&
      !key.startsWith('YOUR_')) {
    await Supabase.initialize(url: url, publishableKey: key);
    AppConfig.supabaseConfigured = true;
  }
  await PushService.init();
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  } catch (_) {}
  runApp(const VioraApp());
}
