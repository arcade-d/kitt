/// Résultat de transcription. `confidence` est `null` si le moteur ne l'expose
/// pas — c'est le cas du zipformer FR de Tachikoma (cf. débrief §4.2, §5.5).
class SttResult {
  const SttResult({required this.text, this.confidence, this.isFinal = false});
  final String text;
  final double? confidence;
  final bool isFinal;
}

/// Speech-To-Text streaming (cf. débrief §4.2).
///
/// API alignée sur `SttService` de Tachikoma (`sherpa_onnx` OnlineRecognizer
/// zipformer) pour que l'adapter réel mappe 1:1. L'endpointing est géré par les
/// règles sherpa via [isEndpoint].
abstract class SttPort {
  Future<void> initialize();

  /// Pousse un buffer d'échantillons audio normalisés (float) au reconnaisseur.
  void acceptWaveform(List<double> samples, int sampleRate);

  /// Transcription courante (texte seul côté Tachikoma).
  SttResult getResult();

  /// `true` quand l'endpointing détecte une fin d'énoncé.
  bool isEndpoint();

  void reset();
  Future<void> dispose();
}
