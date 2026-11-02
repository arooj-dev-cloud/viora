import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/viora_theme.dart';
import '../auth/auth_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _slides = [
    _OnboardingSlide(
      title: 'More than\nmessages',
      subtitle: 'A space for real connections.',
    ),
    _OnboardingSlide(
      title: 'Your people,\nyour space',
      subtitle: 'Chat, share and be yourself without limits.',
    ),
    _OnboardingSlide(
      title: 'Same vibes,\nalways',
      subtitle: 'Meaningful conversations for brighter days.',
    ),
  ];

  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _getStarted() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AuthScreen(signUp: true)),
  );

  void _login() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const AuthScreen(signUp: false)),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        const CustomPaint(painter: _OnboardingBackgroundPainter()),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;
              return Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 3 : 10),
                    child: Column(
                      children: [
                        Text(
                          'VIORA',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: compact ? 32 : 37,
                            letterSpacing: 5,
                            color: VioraColors.blush,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'M O R E   T H A N   M E S S A G E S',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.8,
                            color: VioraColors.blush.withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _slides.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) => _SlidePage(
                        slide: _slides[index],
                        mascotStyle: index,
                        compact: compact,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, 4, 28, compact ? 6 : 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _slides.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              width: index == _page ? 18 : 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: index == _page
                                    ? VioraColors.blush
                                    : VioraColors.lavender.withValues(
                                        alpha: .7,
                                      ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: compact ? 13 : 20),
                        _GradientButton(onPressed: _getStarted),
                        SizedBox(height: compact ? 5 : 10),
                        TextButton(
                          onPressed: _login,
                          style: TextButton.styleFrom(
                            foregroundColor: VioraColors.blush,
                            minimumSize: const Size(48, 42),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Already have an account? '),
                                TextSpan(
                                  text: 'Log In',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _SlidePage extends StatelessWidget {
  const _SlidePage({
    required this.slide,
    required this.mascotStyle,
    required this.compact,
  });

  final _OnboardingSlide slide;
  final int mascotStyle;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mascotSize = math.min(
        constraints.maxWidth * .84,
        constraints.maxHeight * (compact ? .56 : .63),
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(26, 2, 26, 6),
        child: Column(
          children: [
            Expanded(
              flex: 7,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  child: _ChatMascot(
                    key: ValueKey(mascotStyle),
                    size: mascotSize,
                    style: mascotStyle,
                  ),
                ),
              ),
            ),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: compact ? 27 : 31,
                height: 1.07,
                color: VioraColors.blush,
              ),
            ),
            SizedBox(height: compact ? 6 : 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: Text(
                slide.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 13 : 15,
                  height: 1.35,
                  color: VioraColors.blush.withValues(alpha: .86),
                ),
              ),
            ),
            SizedBox(height: compact ? 6 : 12),
          ],
        ),
      );
    },
  );
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFFF7BDD7), Color(0xFFB45BE0)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB45BE0).withValues(alpha: .28),
            blurRadius: 22,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: VioraColors.midnight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Get Started',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x66FFFFFF),
                ),
                child: const Icon(Icons.arrow_forward_rounded, size: 21),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChatMascot extends StatelessWidget {
  const _ChatMascot({super.key, required this.size, required this.style});
  final double size;
  final int style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: [
      'Friendly chat bubble wearing headphones and holding a heart',
      'Smiling chat bubble among stars and clouds',
      'Happy chat bubble sending a glowing message',
    ][style],
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MascotPainter(style)),
    ),
  );
}

class _MascotPainter extends CustomPainter {
  const _MascotPainter(this.style);
  final int style;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 300;
    canvas.save();
    canvas.scale(scale);

    final glow = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0xAAE77BFA), Color(0x005F1A9A)],
          ).createShader(
            Rect.fromCircle(center: const Offset(150, 140), radius: 145),
          );
    canvas.drawCircle(const Offset(150, 140), 145, glow);

    final cloud = Path()
      ..moveTo(54, 160)
      ..cubicTo(37, 143, 43, 116, 65, 105)
      ..cubicTo(69, 75, 96, 58, 124, 69)
      ..cubicTo(143, 42, 185, 48, 198, 78)
      ..cubicTo(231, 70, 256, 94, 248, 124)
      ..cubicTo(271, 143, 260, 177, 232, 184)
      ..lineTo(209, 184)
      ..cubicTo(216, 200, 230, 209, 225, 220)
      ..cubicTo(210, 218, 193, 203, 187, 188)
      ..lineTo(81, 188)
      ..cubicTo(55, 190, 39, 177, 54, 160)
      ..close();

    final shadow = Paint()
      ..color = const Color(0xA9000417)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 17);
    canvas.save();
    canvas.translate(0, 12);
    canvas.drawPath(cloud, shadow);
    canvas.restore();

    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFC9F2), Color(0xFFCB8BF9), Color(0xFF8050D0)],
        stops: [0, .48, 1],
      ).createShader(const Rect.fromLTWH(42, 48, 220, 175));
    canvas.drawPath(cloud, bodyPaint);
    canvas.drawPath(
      cloud,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD9FF).withValues(alpha: .72),
    );

    canvas.drawOval(
      const Rect.fromLTWH(79, 73, 77, 36),
      Paint()
        ..color = Colors.white.withValues(alpha: .20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );

    if (style == 0) _drawHeadphones(canvas);

    final eyePaint = Paint()..color = const Color(0xFF341451);
    if (style == 1) {
      final closedEyes = Paint()
        ..color = const Color(0xFF341451)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        const Rect.fromLTWH(96, 111, 27, 15),
        math.pi,
        math.pi,
        false,
        closedEyes,
      );
      canvas.drawArc(
        const Rect.fromLTWH(177, 111, 27, 15),
        math.pi,
        math.pi,
        false,
        closedEyes,
      );
    } else {
      canvas.drawOval(const Rect.fromLTWH(99, 107, 22, 31), eyePaint);
      canvas.drawOval(const Rect.fromLTWH(180, 107, 22, 31), eyePaint);
      final eyeShine = Paint()..color = Colors.white.withValues(alpha: .94);
      canvas.drawCircle(const Offset(106, 115), 4, eyeShine);
      canvas.drawCircle(const Offset(187, 115), 4, eyeShine);
      canvas.drawCircle(
        const Offset(114, 131),
        2,
        Paint()..color = const Color(0xFFFFB9E7),
      );
      canvas.drawCircle(
        const Offset(195, 131),
        2,
        Paint()..color = const Color(0xFFFFB9E7),
      );
    }

    final smile = Paint()
      ..color = const Color(0xFF5A226D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mouth = Path()
      ..moveTo(137, 139)
      ..quadraticBezierTo(150, style == 1 ? 153 : 161, 164, 139);
    canvas.drawPath(mouth, smile);

    final blush = Paint()
      ..color = const Color(0xFFFF83C6).withValues(alpha: .48);
    canvas.drawOval(const Rect.fromLTWH(78, 137, 25, 10), blush);
    canvas.drawOval(const Rect.fromLTWH(198, 137, 25, 10), blush);

    if (style == 1) {
      _drawChatPill(canvas);
    } else if (style == 0) {
      _drawHeart(canvas, const Offset(202, 182), 28);
      _drawHeart(canvas, const Offset(63, 94), 10);
      _drawHeart(canvas, const Offset(238, 89), 9);
    } else {
      _drawPlane(canvas);
      _drawHeart(canvas, const Offset(66, 109), 9);
      _drawHeart(canvas, const Offset(237, 102), 10);
    }

    if (style != 1) {
      final pill = RRect.fromRectAndRadius(
        const Rect.fromLTWH(116, 163, 68, 27),
        const Radius.circular(15),
      );
      canvas.drawRRect(
        pill,
        Paint()..color = const Color(0xFF6934B6).withValues(alpha: .88),
      );
      for (final x in [134.0, 150.0, 166.0]) {
        canvas.drawCircle(
          Offset(x, 176.5),
          4,
          Paint()
            ..color = const Color(0xFFFFD8FC)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
        );
      }
    }

    _drawSparkle(canvas, const Offset(52, 63), 7);
    _drawSparkle(canvas, const Offset(246, 61), 5);
    _drawSparkle(canvas, const Offset(55, 207), 4);
    _drawSparkle(canvas, const Offset(244, 207), 6);
    canvas.restore();
  }

  void _drawHeadphones(Canvas canvas) {
    final headset = Paint()
      ..color = const Color(0xFF873FE0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(66, 48, 168, 127),
      math.pi,
      math.pi,
      false,
      headset,
    );
    final cup = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF5A7FF), Color(0xFF843EDD)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(57, 91, 40, 62));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(59, 97, 33, 56),
        const Radius.circular(15),
      ),
      cup,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(208, 97, 33, 56),
        const Radius.circular(15),
      ),
      cup,
    );
  }

  void _drawChatPill(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(87, 157, 126, 43),
      const Radius.circular(22),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB75CF0), Color(0xFF7337CF)],
        ).createShader(const Rect.fromLTWH(87, 157, 126, 43)),
    );
    for (final x in [122.0, 150.0, 178.0]) {
      canvas.drawCircle(
        Offset(x, 178),
        6,
        Paint()
          ..color = const Color(0xFFFFC5FB)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _drawPlane(Canvas canvas) {
    final plane = Path()
      ..moveTo(203, 139)
      ..lineTo(250, 119)
      ..lineTo(226, 166)
      ..lineTo(215, 151)
      ..close();
    canvas.drawPath(
      plane,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFD9FF), Color(0xFFB991FF)],
        ).createShader(const Rect.fromLTWH(203, 119, 47, 47)),
    );
    final fold = Paint()
      ..color = const Color(0xFF9C56DD)
      ..strokeWidth = 1.5;
    canvas.drawLine(const Offset(203, 139), const Offset(225, 145), fold);
    canvas.drawLine(const Offset(225, 145), const Offset(226, 166), fold);
  }

  void _drawHeart(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy + radius * .55)
      ..cubicTo(
        center.dx - radius * 1.5,
        center.dy - radius * .3,
        center.dx - radius * .65,
        center.dy - radius * 1.2,
        center.dx,
        center.dy - radius * .55,
      )
      ..cubicTo(
        center.dx + radius * .65,
        center.dy - radius * 1.2,
        center.dx + radius * 1.5,
        center.dy - radius * .3,
        center.dx,
        center.dy + radius * .55,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFE0F2), Color(0xFFFF64C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..quadraticBezierTo(
        center.dx + radius * .16,
        center.dy - radius * .16,
        center.dx + radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx + radius * .16,
        center.dy + radius * .16,
        center.dx,
        center.dy + radius,
      )
      ..quadraticBezierTo(
        center.dx - radius * .16,
        center.dy + radius * .16,
        center.dx - radius,
        center.dy,
      )
      ..quadraticBezierTo(
        center.dx - radius * .16,
        center.dy - radius * .16,
        center.dx,
        center.dy - radius,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFC8FA).withValues(alpha: .82),
    );
  }

  @override
  bool shouldRepaint(covariant _MascotPainter oldDelegate) =>
      oldDelegate.style != style;
}

class _OnboardingBackgroundPainter extends CustomPainter {
  const _OnboardingBackgroundPainter();

  static const _stars = <Offset>[
    Offset(.12, .10),
    Offset(.78, .08),
    Offset(.88, .20),
    Offset(.08, .30),
    Offset(.92, .38),
    Offset(.18, .46),
    Offset(.82, .55),
    Offset(.10, .67),
    Offset(.90, .75),
    Offset(.25, .84),
    Offset(.74, .92),
    Offset(.54, .14),
    Offset(.42, .26),
    Offset(.64, .34),
    Offset(.36, .61),
    Offset(.68, .68),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF170323), Color(0xFF26063F), Color(0xFF12021F)],
        ).createShader(rect),
    );
    for (final glow in [
      (Offset(size.width * .18, size.height * .30), size.width * .56),
      (Offset(size.width * .88, size.height * .66), size.width * .54),
    ]) {
      canvas.drawCircle(
        glow.$1,
        glow.$2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF9D38BF).withValues(alpha: .22),
              const Color(0x001B0428),
            ],
          ).createShader(Rect.fromCircle(center: glow.$1, radius: glow.$2)),
      );
    }
    for (var i = 0; i < _stars.length; i++) {
      final point = Offset(
        _stars[i].dx * size.width,
        _stars[i].dy * size.height,
      );
      final radius = i % 4 == 0 ? 2.0 : 1.2;
      canvas.drawCircle(
        point,
        radius,
        Paint()
          ..color = VioraColors.blush.withValues(alpha: i % 3 == 0 ? .8 : .42),
      );
      if (i % 4 == 0) {
        final shine = Paint()..color = VioraColors.blush.withValues(alpha: .35);
        canvas.drawLine(
          point - const Offset(0, 6),
          point + const Offset(0, 6),
          shine,
        );
        canvas.drawLine(
          point - const Offset(6, 0),
          point + const Offset(6, 0),
          shine,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OnboardingBackgroundPainter oldDelegate) =>
      false;
}

class _OnboardingSlide {
  const _OnboardingSlide({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}
