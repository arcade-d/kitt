import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme/kitt_theme.dart';

/// Rituel de boot K2000 : power-up CRT → lignes de check → scanner qui monte en
/// régime → « K.I.T.T. SYSTEMS ONLINE ». Tap = [onSkip]. L'orchestration de la
/// transition est dans [BootstrapGate] ; ici on joue juste l'animation.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key, required this.onSkip});

  final VoidCallback onSkip;

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onSkip,
      child: Scaffold(
        backgroundColor: KittColors.black,
        body: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _BootPainter(_c.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _BootPainter extends CustomPainter {
  _BootPainter(this.t);

  final double t;

  static const List<String> _lines = <String>[
    'SCANNER . . . . . . OK',
    'VOIX . . . . . . . . OK',
    'MÉMOIRE . . . . . . OK',
    'CERVEAU . . . . . .',
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Rect full = Offset.zero & size;
    final double flash = t < 0.15 ? (1 - t / 0.15) : 0.0;

    // Fond CRT : lueur ambre (renforcée par le flash de power-up).
    final Rect glowRect = Rect.fromCenter(
      center: full.center,
      width: w * 1.1,
      height: h * 0.9,
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            KittColors.amber.withValues(alpha: 0.05 + flash * 0.25),
            const Color(0xFF000000),
          ],
          stops: const <double>[0.0, 0.75],
        ).createShader(glowRect),
    );

    // Scanlines.
    final Paint scan = Paint()..color = const Color(0x14000000);
    for (double y = 0; y < h; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 1), scan);
    }

    final double margin = w * 0.1;

    // Lignes de check apparaissant l'une après l'autre.
    final double startY = h * 0.30;
    for (int i = 0; i < _lines.length; i++) {
      final double appear = 0.15 + i * 0.13;
      if (t < appear) continue;
      final double op = ((t - appear) / 0.06).clamp(0.0, 1.0);
      _text(
        canvas,
        _lines[i],
        KittColors.amber.withValues(alpha: op),
        13,
        Offset(margin, startY + i * 24),
      );
    }

    // Scanner Larson qui monte en régime (bas).
    if (t > 0.5) {
      final double p = ((t - 0.5) / 0.3).clamp(0.0, 1.0);
      final double y = h * 0.64;
      final double span = w - margin * 2;
      final double x = margin + (0.5 + 0.5 * math.sin(t * 26)) * span;
      final Rect blob = Rect.fromCenter(
        center: Offset(x, y),
        width: w * 0.12,
        height: 10,
      );
      canvas.drawRect(
        blob,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              KittColors.scarlet.withValues(alpha: p),
              KittColors.scarlet.withValues(alpha: 0),
            ],
          ).createShader(blob)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Titre « K.I.T.T. SYSTEMS ONLINE ».
    if (t > 0.6) {
      final double op = ((t - 0.6) / 0.2).clamp(0.0, 1.0);
      _centerText(
        canvas,
        w,
        'K.I.T.T. SYSTEMS ONLINE',
        KittColors.amber.withValues(alpha: op),
        20,
        h * 0.5,
      );
    }
  }

  void _text(Canvas canvas, String s, Color color, double size, Offset at) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: kittMono,
          color: color,
          fontSize: size,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  void _centerText(
    Canvas canvas,
    double w,
    String s,
    Color color,
    double size,
    double y,
  ) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: kittMono,
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, y));
  }

  @override
  bool shouldRepaint(_BootPainter old) => old.t != t;
}
