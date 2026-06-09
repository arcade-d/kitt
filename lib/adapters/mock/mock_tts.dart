import 'dart:typed_data';

import '../../ports/tts_port.dart';

/// TTS factice : renvoie un buffer de silence proportionnel à la longueur du
/// texte (≈ durée de parole), sans vraie synthèse.
class MockTts implements TtsPort {
  @override
  int get sampleRate => 22050;

  @override
  Future<void> initialize() async {}

  @override
  Future<Float32List?> synthesize(
    String text, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    // ~60 ms d'audio par mot, juste pour donner une durée plausible.
    final int words = text.trim().isEmpty ? 0 : text.trim().split(' ').length;
    final int frames = (sampleRate * 0.06 * words / speed).round();
    return Float32List(frames);
  }

  @override
  Future<void> dispose() async {}
}
