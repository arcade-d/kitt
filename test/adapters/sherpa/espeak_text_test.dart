import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/sherpa/espeak_text.dart';

void main() {
  test('retire les emojis, conserve les accents français', () {
    expect(
      sanitizeForEspeak('Bonjour 😀 ça va à Noël'),
      'Bonjour  ça va à Noël',
    );
  });

  test('texte 100% emoji -> vide après trim', () {
    expect(sanitizeForEspeak('😀🚗').trim(), '');
  });
}
