/// Événement de détection du mot-clé.
class WakeWordEvent {
  const WakeWordEvent({required this.keyword, this.score});
  final String keyword;
  final double? score;
}

/// Détection continue du wake-word « KITT » (cf. débrief §4.1).
///
/// ABSENT de Tachikoma : aucun moteur KWS. À implémenter côté KITT
/// (Porcupine, openWakeWord, ou `sherpa_onnx KeywordSpotter`).
abstract class WakeWordPort {
  Future<void> start();
  Future<void> stop();

  /// Flux des détections du mot-clé.
  Stream<WakeWordEvent> get detections;
}
