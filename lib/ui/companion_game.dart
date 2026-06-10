import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../application/pipeline_state.dart';

/// Jeu Flame du companion : scanner K2000 + modulateur vocal (cf. débrief §4.1, §5.8).
///
/// MVP visuel (D7) : modulateur + scanner rouge d'abord, cockpit/CRT plus tard.
class KittGame extends FlameGame {
  KittGame({required this.stateListenable, required this.levelListenable});

  final ValueListenable<PipelineState> stateListenable;
  final ValueListenable<double> levelListenable;

  late final ScannerComponent _scanner;
  late final ModulatorComponent _modulator;

  @override
  Color backgroundColor() => const Color(0xFF000000);

  @override
  Future<void> onLoad() async {
    _scanner = ScannerComponent(stateListenable: stateListenable);
    _modulator = ModulatorComponent(
      stateListenable: stateListenable,
      levelListenable: levelListenable,
    );
    await addAll(<Component>[_scanner, _modulator]);
  }
}

/// Le scanner rouge balayant horizontalement (signature K2000).
class ScannerComponent extends PositionComponent
    with HasGameReference<KittGame> {
  ScannerComponent({required this.stateListenable});

  final ValueListenable<PipelineState> stateListenable;

  static const Color _red = Color(0xFFFF1A1A);
  double _t = 0;

  double get _speed => switch (stateListenable.value) {
        PipelineState.idle => 0.6, // veille : balayage lent
        PipelineState.listening || PipelineState.clarifying => 2.4, // attentif
        PipelineState.thinking => 3.6, // réflexion : rapide
        PipelineState.responding => 1.8,
      };

  @override
  void update(double dt) {
    _t += dt * _speed;
  }

  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final double y = s.height * 0.18;
    final double margin = s.width * 0.08;
    final double span = s.width - margin * 2;
    // Mouvement ping-pong via sinus.
    final double x = margin + (0.5 + 0.5 * math.sin(_t)) * span;

    final double blobW = s.width * 0.10;
    final Rect glow = Rect.fromCenter(
      center: Offset(x, y),
      width: blobW,
      height: s.height * 0.05,
    );
    final Paint paint = Paint()
      ..shader = RadialGradient(
        colors: <Color>[_red, _red.withValues(alpha: 0)],
      ).createShader(glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRect(glow, paint);
  }
}

/// Le modulateur vocal : barres réagissant au niveau micro / à l'état.
class ModulatorComponent extends PositionComponent
    with HasGameReference<KittGame> {
  ModulatorComponent({
    required this.stateListenable,
    required this.levelListenable,
  });

  final ValueListenable<PipelineState> stateListenable;
  final ValueListenable<double> levelListenable;

  static const int _bars = 24;
  static const Color _amber = Color(0xFFFFB000);
  final List<double> _heights = List<double>.filled(_bars, 0.05);
  double _phase = 0;

  @override
  void update(double dt) {
    _phase += dt * 6;
    final double level = levelListenable.value.clamp(0.0, 1.0);
    final bool active = stateListenable.value == PipelineState.listening ||
        stateListenable.value == PipelineState.responding;
    for (int i = 0; i < _bars; i++) {
      final double target = active
          ? (0.1 + level * (0.4 + 0.6 * (0.5 + 0.5 * math.sin(_phase + i))))
          : 0.05;
      _heights[i] += (target - _heights[i]) * math.min(1.0, dt * 10);
    }
  }

  @override
  void render(Canvas canvas) {
    final Size s = game.size.toSize();
    final double areaTop = s.height * 0.45;
    final double areaH = s.height * 0.35;
    final double margin = s.width * 0.08;
    final double w = (s.width - margin * 2) / _bars;
    final Paint paint = Paint()..color = _amber;
    for (int i = 0; i < _bars; i++) {
      final double h = _heights[i] * areaH;
      final Rect bar = Rect.fromLTWH(
        margin + i * w + w * 0.15,
        areaTop + (areaH - h),
        w * 0.7,
        h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, const Radius.circular(2)),
        paint,
      );
    }
  }
}
