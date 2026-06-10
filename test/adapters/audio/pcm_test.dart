import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/audio/pcm.dart';

void main() {
  group('int16BytesToFloat32', () {
    test('bytes vides -> liste vide', () {
      expect(int16BytesToFloat32(Uint8List(0)), isEmpty);
    });

    test('longueur impaire : le dernier octet est ignoré', () {
      // 0x4000 (LE) = 16384 ; 3e octet ignoré.
      final out = int16BytesToFloat32(
        Uint8List.fromList([0x00, 0x40, 0x7F]),
      );
      expect(out.length, 1);
      expect(out.first, closeTo(16384 / 32768.0, 1e-9));
    });

    test('max positif ~ +1', () {
      final out = int16BytesToFloat32(Uint8List.fromList([0xFF, 0x7F]));
      expect(out.first, closeTo(32767 / 32768.0, 1e-9));
    });

    test('min négatif == -1', () {
      final out = int16BytesToFloat32(Uint8List.fromList([0x00, 0x80]));
      expect(out.first, closeTo(-1.0, 1e-9));
    });
  });

  group('calculateAudioLevel', () {
    test('vide et silence -> 0', () {
      expect(calculateAudioLevel(const []), 0.0);
      expect(calculateAudioLevel(const [0.0, 0.0]), 0.0);
    });

    test('signal fort -> borné à 1', () {
      expect(calculateAudioLevel(const [1.0, 1.0]), 1.0);
    });
  });
}
