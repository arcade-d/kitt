/// Retire les caractères qu'espeak-ng ne sait pas prononcer (emojis, scripts
/// non latins), en conservant l'ASCII, le Latin-1 accentué (À-ÿ) et la
/// ponctuation usuelle. Porté de Tachikoma `tts_service.dart`.
String sanitizeForEspeak(String text) {
  return text.replaceAll(
    RegExp(r'[^\x00-\x7FÀ-ÿ.,!?;: \-]+'),
    '',
  );
}
