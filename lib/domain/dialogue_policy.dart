import '../application/pipeline_state.dart';
import '../ports/stt_port.dart';

/// Décisions de dialogue : abstention, demande de répétition, barge-in
/// (cf. débrief §5.5, §5.6).
///
/// ABSENT de Tachikoma : pas d'abstention par score (le STT n'expose pas de
/// confiance), pas d'écoute pendant la lecture. Tout est à écrire ici.
class DialoguePolicy {
  const DialoguePolicy({
    this.minSttConfidence = 0.5,
    this.minUtteranceChars = 2,
  });

  /// Seuil sous lequel on demande de répéter. Sans donnée de confiance
  /// (`null`), on NE déclenche PAS de clarification fondée sur le score.
  final double minSttConfidence;

  /// En-deçà, on considère l'énoncé vide/inexploitable.
  final int minUtteranceChars;

  /// `true` si la transcription est trop incertaine et nécessite une
  /// clarification (« tu peux répéter ? »).
  bool shouldClarify(SttResult result) {
    final double? c = result.confidence;
    if (c == null) return false; // pas de donnée → pas d'abstention par score
    return c < minSttConfidence;
  }

  /// `true` si l'énoncé est exploitable (non vide).
  bool isUsable(SttResult result) =>
      result.text.trim().length >= minUtteranceChars;

  /// Le barge-in n'est autorisé que lorsque KITT parle.
  bool allowsBargeIn(PipelineState state) => state == PipelineState.responding;
}
