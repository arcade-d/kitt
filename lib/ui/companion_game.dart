import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../application/pipeline_state.dart';
import 'theme/kitt_theme.dart';
import 'visual_mapping.dart';

/// Jeu Flame du companion : moniteur CRT bi-chrome K2000 (cf. spec écran CRT).
/// Empile : fond CRT, Larson rouge segmenté (bandeau), voicebox (oscilloscope
/// ambre), transcript téléscripteur, puis l'overlay CRT (scanlines + vignette).
class KittGame extends FlameGame {
  KittGame({
    required this.stateListenable,
    required this.levelListenable,
    required this.userTextListenable,
    required this.responseTextListenable,
  });

  final ValueListenable<PipelineState> stateListenable;
  final ValueListenable<double> levelListenable;
  final ValueListenable<String> userTextListenable;
  final ValueListenable<String> responseTextListenable;

  @override
  Color backgroundColor() => KittColors.black;

  @override
  Future<void> onLoad() async {
    await addAll(<Component>[
      CrtBackgroundComponent(),
      LarsonScannerComponent(stateListenable: stateListenable),
      VoiceboxComponent(
        stateListenable: stateListenable,
        levelListenable: levelListenable,
      ),
      TranscriptComponent(
        userTextListenable: userTextListenable,
        responseTextListenable: responseTextListenable,
      ),
      CrtOverlayComponent(),
    ]);
  }
}

/// Fond de l'écran cathodique : lueur radiale ambre + grille phosphore.
class CrtBackgroundComponent extends PositionComponent
    with HasGameReference<KittGame> {
  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final Rect full = Offset.zero & s;

    final Rect glow = Rect.fromCenter(
      center: full.center,
      width: s.width * 1.1,
      height: s.height * 0.9,
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            KittColors.amber.withValues(alpha: 0.06),
            const Color(0xFF000000),
          ],
          stops: const <double>[0.0, 0.75],
        ).createShader(glow),
    );

    final Paint grid = Paint()
      ..color = KittColors.amber.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const double step = 22;
    for (double x = 0; x <= s.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (double y = 0; y <= s.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
  }
}

/// Le balayage Larson : bandeau de cellules rouges avec traînée qui s'estompe.
class LarsonScannerComponent extends PositionComponent
    with HasGameReference<KittGame> {
  LarsonScannerComponent({required this.stateListenable});

  final ValueListenable<PipelineState> stateListenable;

  static const int _cells = 8;
  double _t = 0;

  @override
  void update(double dt) {
    _t += dt * scannerSpeed(stateListenable.value);
  }

  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final double y = s.height * 0.12;
    final double margin = s.width * 0.08;
    final double span = s.width - margin * 2;
    final double cellW = span / _cells;

    final double pos = (0.5 + 0.5 * math.sin(_t)) * (_cells - 1);

    for (int i = 0; i < _cells; i++) {
      final double dist = (i - pos).abs();
      final double intensity = (1.0 - dist / 2.0).clamp(0.0, 1.0);
      final Rect cell = Rect.fromLTWH(
        margin + i * cellW + cellW * 0.12,
        y - 4,
        cellW * 0.76,
        8,
      );
      final Paint p = Paint()
        ..color = Color.lerp(
          KittColors.scarletDim.withValues(alpha: 0.25),
          KittColors.scarlet,
          intensity,
        )!;
      if (intensity > 0.05) {
        p.maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * intensity);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, const Radius.circular(2)),
        p,
      );
    }
  }
}

/// La voicebox : oscilloscope ambre. Amplitude selon le mode (cf. visual_mapping).
class VoiceboxComponent extends PositionComponent
    with HasGameReference<KittGame> {
  VoiceboxComponent({
    required this.stateListenable,
    required this.levelListenable,
  });

  final ValueListenable<PipelineState> stateListenable;
  final ValueListenable<double> levelListenable;

  static const int _points = 64;
  double _phase = 0;

  @override
  void update(double dt) {
    _phase += dt * 6;
  }

  double _amplitudeFor(VoiceboxMode mode) {
    switch (mode) {
      case VoiceboxMode.flat:
        return 0.04;
      case VoiceboxMode.mic:
        return 0.1 + levelListenable.value.clamp(0.0, 1.0) * 0.8;
      case VoiceboxMode.noise:
        return 0.5;
      case VoiceboxMode.speaking:
        return 0.6;
      case VoiceboxMode.pulse:
        return 0.3 + 0.3 * (0.5 + 0.5 * math.sin(_phase * 1.5));
    }
  }

  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final double midY = s.height * 0.5;
    final double margin = s.width * 0.08;
    final double span = s.width - margin * 2;
    final double maxAmp = s.height * 0.16;

    final VoiceboxMode mode = voiceboxMode(stateListenable.value);
    final double amp = _amplitudeFor(mode) * maxAmp;

    final Path path = Path();
    for (int i = 0; i <= _points; i++) {
      final double fx = i / _points;
      final double x = margin + fx * span;
      final double env = math.sin(fx * math.pi);
      final double wave = math.sin(fx * math.pi * 6 + _phase) * 0.6 +
          math.sin(fx * math.pi * 13 - _phase * 1.3) * 0.4;
      final double y = midY + wave * amp * env;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = KittColors.amber
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    TextPaint(style: KittText.label).render(
      canvas,
      _stateLabel(stateListenable.value),
      Vector2(margin, s.height * 0.66),
    );
  }

  String _stateLabel(PipelineState state) {
    switch (state) {
      case PipelineState.idle:
        return 'EN VEILLE';
      case PipelineState.listening:
        return 'À L\'ÉCOUTE';
      case PipelineState.thinking:
        return 'RÉFLEXION';
      case PipelineState.responding:
        return 'KITT RÉPOND';
      case PipelineState.clarifying:
        return 'PARDON ?';
    }
  }
}

/// Transcript téléscripteur : utterance reconnue + réponse de KITT (ambre).
class TranscriptComponent extends PositionComponent
    with HasGameReference<KittGame> {
  TranscriptComponent({
    required this.userTextListenable,
    required this.responseTextListenable,
  });

  final ValueListenable<String> userTextListenable;
  final ValueListenable<String> responseTextListenable;

  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final double margin = s.width * 0.08;
    final double maxWidth = s.width - margin * 2;
    double y = s.height * 0.72;

    final String user = userTextListenable.value;
    if (user.isNotEmpty) {
      y = _line(canvas, '> $user', KittColors.steel, margin, y, maxWidth);
    }
    final String resp = responseTextListenable.value;
    if (resp.isNotEmpty) {
      _line(canvas, 'KITT: $resp', KittColors.amber, margin, y, maxWidth);
    }
  }

  /// Rend une ligne (avec wrap simple) ; renvoie le y suivant.
  double _line(
    Canvas canvas,
    String text,
    Color color,
    double x,
    double y,
    double maxWidth,
  ) {
    final TextPaint tp = TextPaint(
      style: KittText.mono.copyWith(color: color),
    );
    for (final line in _wrap(text, tp, maxWidth)) {
      tp.render(canvas, line, Vector2(x, y));
      y += 16;
    }
    return y + 4;
  }

  List<String> _wrap(String text, TextPaint tp, double maxWidth) {
    final words = text.split(' ');
    final out = <String>[];
    var current = '';
    for (final w in words) {
      final attempt = current.isEmpty ? w : '$current $w';
      if (tp.getLineMetrics(attempt).width > maxWidth && current.isNotEmpty) {
        out.add(current);
        current = w;
      } else {
        current = attempt;
      }
    }
    if (current.isNotEmpty) out.add(current);
    return out.take(4).toList(growable: false);
  }
}

/// Overlay CRT : scanlines + vignette, rendu par-dessus tout.
class CrtOverlayComponent extends PositionComponent
    with HasGameReference<KittGame> {
  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final Rect full = Offset.zero & s;

    final Paint scan = Paint()..color = const Color(0x10000000);
    for (double y = 0; y < s.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, s.width, 1), scan);
    }

    canvas.drawRect(
      full,
      Paint()
        ..shader = RadialGradient(
          colors: const <Color>[Color(0x00000000), Color(0xCC000000)],
          stops: const <double>[0.65, 1.0],
        ).createShader(full),
    );
  }
}
