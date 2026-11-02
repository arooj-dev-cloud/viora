import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/theme/viora_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/notifications/push_service.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/welcome_screen.dart';

class VioraApp extends StatefulWidget {
  const VioraApp({super.key});

  @override
  State<VioraApp> createState() => _VioraAppState();
}

class _VioraAppState extends State<VioraApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;
  bool _recoveryRouteOpen = false;

  @override
  void initState() {
    super.initState();
    if (AppConfig.supabaseConfigured) {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen(
        (state) {
          if (state.session != null) {
            unawaited(PushService.register(Supabase.instance.client));
          }
          if (state.event == AuthChangeEvent.passwordRecovery &&
              !_recoveryRouteOpen) {
            _recoveryRouteOpen = true;
            _navigatorKey.currentState
                ?.push<void>(MaterialPageRoute<void>(
                  builder: (_) => const ResetPasswordScreen(),
                ))
                .whenComplete(() => _recoveryRouteOpen = false);
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Viora',
        debugShowCheckedModeBanner: false,
        theme: VioraTheme.dark,
        home: AppConfig.supabaseConfigured &&
                Supabase.instance.client.auth.currentSession != null
            ? const HomeScreen()
            : const WelcomeScreen(),
      );
}
