import 'dart:typed_data';

import '../../ports/tts_port.dart';
import 'kitt_filter.dart';

/// Décore un [TtsPort] en appliquant le filtre vocal KITT au PCM synthétisé.
class KittFilteredTts implements TtsPort {
  KittFilteredTts(this._inner);

  final TtsPort _inner;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<Float32List?> synthesize(
    String text, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    final pcm = await _inner.synthesize(
      text,
      speakerId: speakerId,
      speed: speed,
    );
    if (pcm == null) return null;
    return applyKittFilter(pcm, _inner.sampleRate);
  }

  @override
  int get sampleRate => _inner.sampleRate;

  @override
  Future<void> dispose() => _inner.dispose();
}
