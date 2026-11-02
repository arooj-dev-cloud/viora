import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.signUp = false});
  final bool signUp;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool signingUp = widget.signUp;
  bool obscure = true;
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final fullName = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    fullName.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    if (!AppConfig.supabaseConfigured) {
      _message(
        context,
        'Add your Supabase URL and publishable key to .env, then restart the app.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (signingUp) {
        final response = await Supabase.instance.client.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          data: {'display_name': fullName.text.trim()},
        );
        if (mounted && response.session != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        } else if (mounted) {
          _message(context, 'Check your email to confirm your account.');
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (r) => false,
          );
        }
      }
    } on AuthException catch (e) {
      if (mounted) _message(context, e.message);
    } catch (e) {
      if (mounted) {
        _message(
          context,
          'Could not complete authentication. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _PurpleRibbonPainter()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 36),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(28, 20, 28, 22),
                              decoration: BoxDecoration(
                                color: const Color(0xA51C0A31),
                                borderRadius: BorderRadius.circular(34),
                                border: Border.all(
                                  color: const Color(0xA8E7C4FF),
                                  width: 1.1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x773C0A6D),
                                    blurRadius: 34,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Form(
                                key: formKey,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: IconButton(
                                        onPressed: () => Navigator.pop(context),
                                        icon: const Icon(Icons.arrow_back),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const _VioraMark(),
                                    const SizedBox(height: 25),
                                    Text(
                                      signingUp
                                          ? 'Create Account'
                                          : 'Welcome Back',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        letterSpacing: .4,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    if (signingUp) ...[
                                      _label('Full Name'),
                                      TextFormField(
                                        controller: fullName,
                                        validator: (value) => value == null ||
                                                value.trim().isEmpty
                                            ? 'Enter your name'
                                            : null,
                                        decoration:
                                            _fieldDecoration('Enter your name'),
                                      ),
                                      const SizedBox(height: 17),
                                    ],
                                    _label('Email address'),
                                    TextFormField(
                                      controller: email,
                                      keyboardType: TextInputType.emailAddress,
                                      validator: (value) =>
                                          value == null || !value.contains('@')
                                              ? 'Enter a valid email'
                                              : null,
                                      decoration: _fieldDecoration(''),
                                    ),
                                    const SizedBox(height: 17),
                                    _label('Password'),
                                    TextFormField(
                                      controller: password,
                                      obscureText: obscure,
                                      validator: (value) =>
                                          value == null || value.length < 8
                                              ? 'Use at least 8 characters'
                                              : null,
                                      decoration: _fieldDecoration(
                                        '',
                                        suffix: IconButton(
                                          onPressed: () => setState(
                                              () => obscure = !obscure),
                                          icon: Icon(obscure
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined),
                                        ),
                                      ),
                                    ),
                                    if (signingUp) ...[
                                      const SizedBox(height: 17),
                                      _label('Confirm Password'),
                                      TextFormField(
                                        controller: confirmPassword,
                                        obscureText: obscure,
                                        validator: (value) =>
                                            value != password.text
                                                ? 'Passwords do not match'
                                                : null,
                                        decoration: _fieldDecoration(
                                            'Repeat your password'),
                                      ),
                                    ],
                                    if (!signingUp)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton(
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const ForgotPasswordScreen()),
                                          ),
                                          style: TextButton.styleFrom(
                                              padding: const EdgeInsets.only(
                                                  left: 4)),
                                          child: const Text('Forgot Password?'),
                                        ),
                                      )
                                    else
                                      const SizedBox(height: 16),
                                    const SizedBox(height: 7),
                                    SizedBox(
                                      height: 54,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFB875F2),
                                              Color(0xFF813BDD)
                                            ],
                                          ),
                                          border: Border.all(
                                              color: Colors.white
                                                  .withValues(alpha: .82)),
                                          boxShadow: const [
                                            BoxShadow(
                                                color: Color(0x775A25B5),
                                                blurRadius: 18,
                                                offset: Offset(0, 6)),
                                          ],
                                        ),
                                        child: FilledButton(
                                          onPressed: busy ? null : submit,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            disabledBackgroundColor:
                                                Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14)),
                                          ),
                                          child: busy
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator())
                                              : Text(
                                                  signingUp
                                                      ? 'Sign Up'
                                                      : 'Login',
                                                  style: const TextStyle(
                                                      fontSize: 19,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      letterSpacing: .4)),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    Center(
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(signingUp
                                              ? 'Already have an account? '
                                              : 'Are you new here? '),
                                          TextButton(
                                            onPressed: () => setState(
                                                () => signingUp = !signingUp),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 2),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                                signingUp ? 'Login' : 'Sign Up',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0x30110522),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8D9F7), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xBFE8D9F7), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFF4D7FF), width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Colors.pinkAccent),
        ),
      );
  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, color: Color(0xFFF0E6F8)),
        ),
      );
}

class _VioraMark extends StatelessWidget {
  const _VioraMark();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          SizedBox(
            width: 58,
            height: 66,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -.78,
                  child: Container(
                    width: 22,
                    height: 51,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFDAA4FF), Color(0xFF6730B3)],
                      ),
                      border: Border.all(color: const Color(0xFFCFAEFF)),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, 13),
                  child: Transform.rotate(
                    angle: -.78,
                    child: Container(
                      width: 22,
                      height: 43,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: const Color(0xFF34205F),
                        border: Border.all(color: const Color(0xFF9D75E0)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'VIORA',
            style: TextStyle(
              fontSize: 19,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w300,
              color: Color(0xFFE9D8F4),
            ),
          ),
        ],
      );
}

class _PurpleRibbonPainter extends CustomPainter {
  const _PurpleRibbonPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.6, 0.2),
          radius: 1.2,
          colors: [Color(0xFF351052), Color(0xFF160322), Color(0xFF0D0018)],
          stops: [0, .55, 1],
        ).createShader(rect),
    );

    final sweep = Path()
      ..moveTo(size.width * .88, -size.height * .08)
      ..cubicTo(size.width * .24, size.height * .08, size.width * .96,
          size.height * .31, size.width * .22, size.height * .52)
      ..cubicTo(-size.width * .24, size.height * .68, size.width * .74,
          size.height * .80, size.width * .18, size.height * 1.08);
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * .24
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25)
      ..shader = const LinearGradient(
        colors: [Color(0x558F43E7), Color(0x886021AE), Color(0x558C4BDD)],
      ).createShader(rect);
    canvas.drawPath(sweep, basePaint);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * .085
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x00E8BFFF), Color(0xAAAD72FF), Color(0x44E6C3FF)],
      ).createShader(rect);
    canvas.drawPath(sweep, highlight);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..color = const Color(0x669D69EA);
    canvas.drawPath(sweep, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final controller = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!controller.text.contains('@')) {
      _message(context, 'Enter a valid email address.');
      return;
    }
    if (!AppConfig.supabaseConfigured) {
      _message(context, 'Configure Supabase in .env to send a recovery email.');
      return;
    }
    setState(() => busy = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        controller.text.trim(),
        redirectTo: kIsWeb ? null : 'viora://auth-callback/reset-password',
      );
      if (mounted) {
        _message(
          context,
          'If the account exists, a recovery link will arrive by email.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) _message(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reset password')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              const Text(
                'Find your way back.',
                style: TextStyle(fontFamily: 'serif', fontSize: 28),
              ),
              const SizedBox(height: 10),
              const Text(
                'Enter your account email and we’ll send a recovery link.',
              ),
              const SizedBox(height: 25),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : send,
                child: Text(busy ? 'Sending…' : 'Send recovery link'),
              ),
            ],
          ),
        ),
      );
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, color: Color(0xFFF0E6F8)),
        ),
      );

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0x30110522),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8D9F7), width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xBFE8D9F7), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFF4D7FF), width: 1.8),
        ),
      );

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Password updated'),
          content: const Text('Your new password is ready to use.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } on AuthException catch (error) {
      if (mounted) _message(context, error.message);
    } catch (_) {
      if (mounted) {
        _message(context,
            'Could not update the password. The recovery link may have expired; request a new one.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _PurpleRibbonPainter()),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xA51C0A31),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: const Color(0xA8E7C4FF)),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _VioraMark(),
                                const SizedBox(height: 28),
                                const Text(
                                  'Choose a new password',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 23),
                                ),
                                const SizedBox(height: 28),
                                _label('New Password'),
                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  validator: (value) =>
                                      value == null || value.length < 8
                                          ? 'Use at least 8 characters'
                                          : null,
                                  decoration: _fieldDecoration(
                                    'Enter a new password',
                                    suffix: IconButton(
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(_obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                _label('Confirm Password'),
                                TextFormField(
                                  controller: _confirmation,
                                  obscureText: _obscure,
                                  validator: (value) => value != _password.text
                                      ? 'Passwords do not match'
                                      : null,
                                  decoration:
                                      _fieldDecoration('Confirm your password'),
                                ),
                                const SizedBox(height: 26),
                                FilledButton(
                                  onPressed: _saving ? null : _updatePassword,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                    backgroundColor: const Color(0xFF964FE1),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator())
                                      : const Text('Update Password'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
