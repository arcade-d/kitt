import '../../ports/stt_port.dart';

/// Mappe le texte brut du zipformer vers un [SttResult]. Le zipformer FR
/// n'expose pas de score → `confidence` est toujours `null` (cf. débrief §4.2).
SttResult mapSttResult(String rawText, {required bool isFinal}) {
  return SttResult(text: rawText.trim(), isFinal: isFinal);
}
