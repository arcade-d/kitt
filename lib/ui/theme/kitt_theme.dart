import 'package:flutter/material.dart';

/// Palette et styles K2000 (Knight Rider, 1982) : rouge balayeur, ambre tableau
/// de bord, noir profond et typo « digitale » monospace. Centralisé ici pour
/// que tout l'app partage la même identité (cf. style de la série).
class KittColors {
  const KittColors._();

  /// Noir du cockpit.
  static const Color black = Color(0xFF050505);
  static const Color panel = Color(0xFF120808);

  /// Rouge signature du scanner K2000.
  static const Color scarlet = Color(0xFFFF1A1A);
  static const Color scarletDim = Color(0xFF7A0E0E);
  static const Color ember = Color(0xFFFF4D2E);

  /// Ambre des afficheurs du tableau de bord.
  static const Color amber = Color(0xFFFFB000);

  /// Gris des libellés secondaires.
  static const Color steel = Color(0xFF8A8A8A);
}

/// Famille monospace : on s'appuie sur la police mono du système (aucun asset à
/// embarquer) pour le rendu « afficheur LED ».
const String kittMono = 'monospace';

/// Styles de texte récurrents (afficheurs, libellés, valeurs).
class KittText {
  const KittText._();

  static const TextStyle display = TextStyle(
    fontFamily: kittMono,
    color: KittColors.scarlet,
    fontSize: 38,
    fontWeight: FontWeight.w700,
    letterSpacing: 12,
  );

  static const TextStyle label = TextStyle(
    fontFamily: kittMono,
    color: KittColors.amber,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 3,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: kittMono,
    color: KittColors.steel,
    fontSize: 12,
    letterSpacing: 1.5,
  );

  static const TextStyle readout = TextStyle(
    fontFamily: kittMono,
    color: KittColors.amber,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 1,
  );
}

/// Thème global de l'application, décliné sur la charte K2000.
class KittTheme {
  const KittTheme._();

  static ThemeData build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: KittColors.scarlet,
      brightness: Brightness.dark,
    ).copyWith(
      primary: KittColors.scarlet,
      secondary: KittColors.amber,
      surface: KittColors.panel,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KittColors.black,
      fontFamily: kittMono,
      textTheme: const TextTheme(
        bodyMedium: KittText.mono,
        titleMedium: KittText.label,
      ),
    );
  }
}
