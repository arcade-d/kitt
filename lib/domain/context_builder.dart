import 'persona.dart';
import 'turn.dart';

/// Estimation grossière du nombre de tokens (≈ 4 caractères / token).
/// Suffisant pour piloter l'éviction sans tokenizer embarqué.
int estimateTokens(String text) => (text.length / 4).ceil();

/// Résultat de l'assemblage de contexte : le prompt prêt à envoyer au LLM,
/// plus des métadonnées utiles aux tests et au debug.
class BuiltContext {
  const BuiltContext({
    required this.systemPrompt,
    required this.prompt,
    required this.includedTurns,
    required this.droppedTurns,
    required this.estimatedTokens,
  });

  final String systemPrompt;
  final String prompt;
  final List<Turn> includedTurns;
  final List<Turn> droppedTurns;
  final int estimatedTokens;
}

/// Assemble le prompt à chaque tour (cf. débrief §5.2).
///
/// Structure produite :
/// ```
/// [system]   persona + règles
/// [memory]   faits persistants (UserMemory) — optionnel
/// [summary]  résumé glissant des tours anciens — optionnel
/// [history]  les N derniers tours verbatim
/// [user]     l'énoncé courant
/// ```
///
/// Tachikoma ne fournit qu'un `_historyContext()` brut (5 derniers tours) ; le
/// budget de tokens et le résumé glissant sont à écrire ici (côté KITT).
class ContextBuilder {
  const ContextBuilder({this.tokenBudget = 1800, this.maxHistoryTurns = 8});

  /// Budget cible pour history+summary (laisse de la marge sous `contextSize: 2048`).
  final int tokenBudget;

  /// Nombre maximum de tours verbatim conservés avant éviction.
  final int maxHistoryTurns;

  BuiltContext build({
    required Persona persona,
    required List<Turn> history,
    required String currentUtterance,
    String? rollingSummary,
    String? memoryContext,
  }) {
    final String systemPrompt =
        persona.isValid ? persona.systemPrompt : Persona.fallback.systemPrompt;

    // Fenêtre courte : on part des plus récents et on remonte tant qu'on tient
    // dans le budget (et la limite de tours).
    final List<Turn> candidates = history.length > maxHistoryTurns
        ? history.sublist(history.length - maxHistoryTurns)
        : List<Turn>.of(history);

    final int fixedCost = estimateTokens(systemPrompt) +
        estimateTokens(currentUtterance) +
        estimateTokens(rollingSummary ?? '') +
        estimateTokens(memoryContext ?? '');

    final List<Turn> included = <Turn>[];
    int running = fixedCost;
    for (final Turn turn in candidates.reversed) {
      final int cost = estimateTokens('${turn.role.name}: ${turn.content}\n');
      if (running + cost > tokenBudget && included.isNotEmpty) break;
      running += cost;
      included.insert(0, turn);
    }

    final List<Turn> dropped = history
        .where((Turn t) => !included.contains(t))
        .toList(growable: false);

    final StringBuffer buffer = StringBuffer();
    if (memoryContext != null && memoryContext.trim().isNotEmpty) {
      buffer.writeln('[mémoire]\n${memoryContext.trim()}\n');
    }
    if (rollingSummary != null && rollingSummary.trim().isNotEmpty) {
      buffer.writeln('[résumé]\n${rollingSummary.trim()}\n');
    }
    if (included.isNotEmpty) {
      buffer.writeln('[historique]');
      for (final Turn t in included) {
        buffer.writeln('${t.role.name}: ${t.content}');
      }
      buffer.writeln();
    }
    buffer.write('user: $currentUtterance');

    final String prompt = buffer.toString();
    return BuiltContext(
      systemPrompt: systemPrompt,
      prompt: prompt,
      includedTurns: included,
      droppedTurns: dropped,
      estimatedTokens: estimateTokens(systemPrompt) + estimateTokens(prompt),
    );
  }
}
