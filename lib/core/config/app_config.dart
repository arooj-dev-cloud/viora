import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class AppConfig {
  static bool supabaseConfigured = false;
  static String inviteUrl = 'https://example.com/viora-download';

  /// True when TURN_URL / TURN_USERNAME / TURN_CREDENTIAL are all set in .env.
  static bool get hasTurn =>
      (dotenv.env['TURN_URL']?.trim() ?? '').isNotEmpty &&
          (dotenv.env['TURN_USERNAME']?.trim() ?? '').isNotEmpty &&
          (dotenv.env['TURN_CREDENTIAL']?.trim() ?? '').isNotEmpty;

  /// STUN always; plus a TURN relay when TURN_URL / TURN_USERNAME /
  /// TURN_CREDENTIAL are set in .env (needed when phones are on different
  /// networks, e.g. Wi-Fi to mobile data).
  static List<Map<String, dynamic>> get stunIceServers {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    final turnUrl = dotenv.env['TURN_URL']?.trim() ?? '';
    final user = dotenv.env['TURN_USERNAME']?.trim() ?? '';
    final cred = dotenv.env['TURN_CREDENTIAL']?.trim() ?? '';
    if (turnUrl.isNotEmpty && user.isNotEmpty && cred.isNotEmpty) {
      servers.add({
        'urls': turnUrl.split(',').map((u) => u.trim()).toList(),
        'username': user,
        'credential': cred,
      });
    } else {
      // Best-effort public relay so calls can work out of the box. It is
      // shared and may be slow or unavailable: add your own TURN_* values in
      // .env for reliable calls across different networks.
      servers.add({
        'urls': [
          'turn:openrelay.metered.ca:80',
          'turn:openrelay.metered.ca:443',
          'turns:openrelay.metered.ca:443?transport=tcp',
        ],
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      });
    }
    return servers;
  }
}