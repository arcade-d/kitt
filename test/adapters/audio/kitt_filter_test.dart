import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/audio/kitt_filter.dart';

void main() {
  test('vide -> vide ; longueur préservée', () {
    expect(applyKittFilter(Float32List(0), 22050), isEmpty);
    expect(
      applyKittFilter(Float32List.fromList([0.1, -0.2, 0.3]), 22050).length,
      3,
    );
  });

  test('silence -> silence', () {
    final out = applyKittFilter(Float32List(64), 22050);
    expect(out.every((double v) => v == 0.0), isTrue);
  });

  test('sortie bornée dans [-1, 1]', () {
    final input = Float32List.fromList(
      List<double>.generate(256, (int i) => i.isEven ? 1.0 : -1.0),
    );
    final out = applyKittFilter(input, 22050);
    expect(out.every((double v) => v.abs() <= 1.0 + 1e-6), isTrue);
  });

  test('déterministe', () {
    final input = Float32List.fromList(
      List<double>.generate(128, (int i) => math.sin(i * 0.3)),
    );
    expect(
      applyKittFilter(input, 22050),
      equals(applyKittFilter(input, 22050)),
    );
  });

  test('signal non nul -> sortie non nulle', () {
    final input = Float32List.fromList(
      List<double>.generate(128, (int i) => math.sin(i * 0.3)),
    );
    expect(
      applyKittFilter(input, 22050).any((double v) => v.abs() > 1e-4),
      isTrue,
    );
  });
}
