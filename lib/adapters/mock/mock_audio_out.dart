import 'dart:typed_data';

import '../../ports/audio_out_port.dart';

/// Sortie audio factice : « joue » en attendant une durée proportionnelle au
/// nombre d'échantillons. Pas de Bluetooth/ducking (cf. débrief §4.5).
class MockAudioOut implements AudioOutPort {
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> playPcm(Float32List samples, int sampleRate) async {
    _playing = true;
    final Duration d = Duration(
      milliseconds: (samples.length / sampleRate * 1000).round(),
    );
    await Future<void>.delayed(d);
    _playing = false;
  }

  @override
  Future<void> stop() async => _playing = false;
}
