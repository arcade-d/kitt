import 'role.dart';
import 'turn.dart';

/// Journal de tours de la conversation en cours.
///
/// Source de vérité de l'historique. Le [ContextBuilder] consomme cet
/// historique pour assembler le prompt ; ce manager ne décide PAS du budget
/// de tokens ni de l'éviction — il ne fait que tenir le journal.
class ConversationManager {
  ConversationManager({this.maxRetainedTurns = 200});

  /// Plafond dur de tours conservés en mémoire (garde-fou anti-fuite).
  /// L'éviction « intelligente » (résumé glissant) vit dans le ContextBuilder.
  final int maxRetainedTurns;

  final List<Turn> _turns = <Turn>[];

  /// Vue immuable de l'historique, du plus ancien au plus récent.
  List<Turn> get turns => List<Turn>.unmodifiable(_turns);

  bool get isEmpty => _turns.isEmpty;
  int get length => _turns.length;

  Turn? get last => _turns.isEmpty ? null : _turns.last;

  Turn add(Turn turn) {
    _turns.add(turn);
    if (_turns.length > maxRetainedTurns) {
      _turns.removeRange(0, _turns.length - maxRetainedTurns);
    }
    return turn;
  }

  Turn addUser(String content, {double? sttConfidence}) =>
      add(Turn(role: Role.user, content: content, sttConfidence: sttConfidence));

  Turn addAssistant(String content) =>
      add(Turn(role: Role.assistant, content: content));

  /// Les [n] derniers tours (hors `system`), du plus ancien au plus récent.
  List<Turn> recent(int n) {
    final List<Turn> dialogue =
        _turns.where((Turn t) => t.role != Role.system).toList();
    if (dialogue.length <= n) return dialogue;
    return dialogue.sublist(dialogue.length - n);
  }

  void clear() => _turns.clear();
}
