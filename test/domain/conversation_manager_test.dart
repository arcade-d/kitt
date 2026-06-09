import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/domain/conversation_manager.dart';
import 'package:kitt/domain/role.dart';
import 'package:kitt/domain/turn.dart';

void main() {
  group('ConversationManager', () {
    test('ajoute et expose les tours dans l\'ordre', () {
      final cm = ConversationManager();
      cm.addUser('bonjour');
      cm.addAssistant('bonsoir');
      expect(cm.length, 2);
      expect(cm.turns.first.role, Role.user);
      expect(cm.turns.last.content, 'bonsoir');
    });

    test('recent(n) ignore les tours system et plafonne', () {
      final cm = ConversationManager();
      cm.add(Turn(role: Role.system, content: 'persona'));
      for (var i = 0; i < 5; i++) {
        cm.addUser('u$i');
      }
      final recent = cm.recent(3);
      expect(recent.length, 3);
      expect(recent.every((t) => t.role != Role.system), isTrue);
      expect(recent.last.content, 'u4');
    });

    test('respecte maxRetainedTurns', () {
      final cm = ConversationManager(maxRetainedTurns: 3);
      for (var i = 0; i < 10; i++) {
        cm.addUser('u$i');
      }
      expect(cm.length, 3);
      expect(cm.turns.first.content, 'u7');
    });
  });
}
