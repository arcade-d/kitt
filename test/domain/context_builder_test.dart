import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/domain/context_builder.dart';
import 'package:kitt/domain/persona.dart';
import 'package:kitt/domain/role.dart';
import 'package:kitt/domain/turn.dart';

void main() {
  group('ContextBuilder', () {
    final persona = Persona.fallback;

    test('assemble system + historique + énoncé courant', () {
      const builder = ContextBuilder();
      final history = <Turn>[
        Turn(role: Role.user, content: 'salut'),
        Turn(role: Role.assistant, content: 'bonjour'),
      ];
      final ctx = builder.build(
        persona: persona,
        history: history,
        currentUtterance: 'quelle heure est-il',
      );
      expect(ctx.systemPrompt, persona.systemPrompt);
      expect(ctx.prompt, contains('[historique]'));
      expect(ctx.prompt, contains('user: quelle heure est-il'));
      expect(ctx.includedTurns.length, 2);
      expect(ctx.droppedTurns, isEmpty);
    });

    test('évince les tours anciens quand le budget est dépassé', () {
      const builder = ContextBuilder(tokenBudget: 60, maxHistoryTurns: 100);
      final history = List<Turn>.generate(
        40,
        (i) => Turn(role: Role.user, content: 'message numéro $i assez long'),
      );
      final ctx = builder.build(
        persona: persona,
        history: history,
        currentUtterance: 'et maintenant',
      );
      expect(ctx.includedTurns.length, lessThan(history.length));
      expect(ctx.droppedTurns, isNotEmpty);
      // On garde toujours les plus récents.
      expect(ctx.includedTurns.last.content, contains('numéro 39'));
    });

    test('injecte mémoire et résumé quand fournis', () {
      const builder = ContextBuilder();
      final ctx = builder.build(
        persona: persona,
        history: const <Turn>[],
        currentUtterance: 'go',
        memoryContext: '- prénom: Levi',
        rollingSummary: 'On parlait de la route.',
      );
      expect(ctx.prompt, contains('[mémoire]'));
      expect(ctx.prompt, contains('[résumé]'));
    });
  });

  test('estimateTokens approxime ~4 caractères/token', () {
    expect(estimateTokens('abcd'), 1);
    expect(estimateTokens('abcdefgh'), 2);
  });
}
