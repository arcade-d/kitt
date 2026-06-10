import 'package:ulid/ulid.dart';

import 'role.dart';

/// Un tour de conversation typé par rôle (cf. débrief §5.1).
///
/// `sttConfidence` reste `null` tant qu'un STT exposant un score n'est pas
/// branché — le zipformer de Tachikoma n'expose pas de confiance.
class Turn {
  Turn({
    required this.role,
    required this.content,
    String? id,
    DateTime? at,
    this.sttConfidence,
  }) : id = id ?? Ulid().toString(),
       at = at ?? DateTime.now();

  /// Identifiant ULID (triable lexicographiquement par date de création).
  final String id;
  final Role role;
  final String content;
  final DateTime at;

  /// Score de confiance du STT, dans [0, 1]. `null` si non disponible.
  final double? sttConfidence;

  Turn copyWith({String? content, double? sttConfidence}) => Turn(
    id: id,
    role: role,
    content: content ?? this.content,
    at: at,
    sttConfidence: sttConfidence ?? this.sttConfidence,
  );

  @override
  String toString() => 'Turn(${role.name}, "$content")';
}
