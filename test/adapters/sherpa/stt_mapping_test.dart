import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/sherpa/stt_mapping.dart';

void main() {
  test('trim du texte, confidence null, isFinal transmis', () {
    final r = mapSttResult('  salut KITT  ', isFinal: true);
    expect(r.text, 'salut KITT');
    expect(r.confidence, isNull);
    expect(r.isFinal, isTrue);
    expect(mapSttResult('x', isFinal: false).isFinal, isFalse);
  });
}
