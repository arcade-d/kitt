import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/util/byte_format.dart';

void main() {
  group('formatBytes', () {
    test('octets sans décimale', () {
      expect(formatBytes(512), '512 o');
    });
    test('Ko / Mo / Go', () {
      expect(formatBytes(1024), '1.0 Ko');
      expect(formatBytes(1024 * 1024), '1.0 Mo');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 Go');
    });
    test('zéro ou négatif → 0 o', () {
      expect(formatBytes(0), '0 o');
      expect(formatBytes(-5), '0 o');
    });
  });

  group('formatBytesRatio', () {
    test('reçu et total ramenés à la même unité', () {
      final s = formatBytesRatio(
        (0.5 * 1024 * 1024 * 1024).round(),
        1024 * 1024 * 1024,
      );
      expect(s, '0.5 / 1.0 Go');
    });
    test('total nul → reçu seul', () {
      expect(formatBytesRatio(1024, 0), '1.0 Ko');
    });
  });

  group('formatRate', () {
    test('débit positif', () {
      expect(formatRate(2 * 1024 * 1024), '2.0 Mo/s');
    });
    test('nul → tiret', () {
      expect(formatRate(0), '—');
    });
  });
}
