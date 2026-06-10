import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/mock/mock_audio_in.dart';
import 'package:kitt/adapters/mock/mock_stt.dart';
import 'package:kitt/adapters/mock/mock_tts.dart';
import 'package:kitt/application/providers.dart';

void main() {
  test('mode mock (défaut) : le faisceau câble les adapters mock', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final adapters = await container.read(adaptersProvider.future);
    expect(adapters.stt, isA<MockStt>());
    expect(adapters.tts, isA<MockTts>());
    expect(adapters.audioIn, isA<MockAudioIn>());
  });
}
