import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/ui/boot_gate_logic.dart';

void main() {
  group('shouldShowBoot', () {
    test('init non résolue → toujours le boot', () {
      expect(
        shouldShowBoot(
          minElapsed: true,
          skipRequested: true,
          initResolved: false,
        ),
        isTrue,
      );
    });

    test('init résolue + durée mini écoulée → quitte le boot', () {
      expect(
        shouldShowBoot(
          minElapsed: true,
          skipRequested: false,
          initResolved: true,
        ),
        isFalse,
      );
    });

    test('init résolue + skip → quitte le boot', () {
      expect(
        shouldShowBoot(
          minElapsed: false,
          skipRequested: true,
          initResolved: true,
        ),
        isFalse,
      );
    });

    test('init résolue mais ni mini ni skip → reste au boot', () {
      expect(
        shouldShowBoot(
          minElapsed: false,
          skipRequested: false,
          initResolved: true,
        ),
        isTrue,
      );
    });
  });
}
