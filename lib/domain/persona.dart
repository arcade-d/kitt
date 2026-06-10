import 'package:flutter/services.dart' show rootBundle;

/// La persona de KITT : system prompt + règles, externalisés (cf. débrief §9.1).
///
/// Chez Tachikoma la persona était une constante codée en dur
/// (`_croissantSystemPrompt`). Ici on la charge depuis `assets/persona/` pour
/// pouvoir l'itérer sans toucher au code.
class Persona {
  const Persona({
    required this.name,
    required this.systemPrompt,
    this.locale = 'fr',
  });

  final String name;
  final String systemPrompt;
  final String locale;

  bool get isValid => systemPrompt.trim().isNotEmpty;

  /// Charge la persona par défaut (KITT, FR) depuis les assets.
  static Future<Persona> loadDefault() async {
    final String prompt = await rootBundle.loadString(
      'assets/persona/kitt_fr.md',
    );
    return Persona(name: 'KITT', systemPrompt: prompt.trim());
  }

  /// Persona de repli, utile en test ou si l'asset est introuvable.
  static const Persona fallback = Persona(
    name: 'KITT',
    systemPrompt:
        'Tu es KITT, un compagnon de bord à la voix posée et compétente. '
        'Tu réponds en français, de façon concise et utile. '
        'Si tu ne sais pas, tu le dis simplement.',
  );
}
