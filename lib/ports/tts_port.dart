import 'dart:typed_data';

/// Text-To-Speech — la voix de KITT (cf. débrief §4.4).
///
/// API alignée sur `TtsService` de Tachikoma (`sherpa_onnx` OfflineTts,
/// VITS/Piper). Non streaming côté Tachikoma : `synthesize` rend tout l'audio
/// d'un bloc. Le découpage par phrase (« parler dès la 1re phrase ») est à
/// écrire au-dessus de ce port, côté KITT.
abstract class TtsPort {
  Future<void> initialize();

  /// Synthétise [text] en PCM float. `null` si la synthèse échoue.
  Future<Float32List?> synthesize(
    String text, {
    int speakerId = 0,
    double speed = 1.0,
  });

  int get sampleRate;

  Future<void> dispose();
}
