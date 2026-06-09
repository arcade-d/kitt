import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/application/pipeline_state.dart';
import 'package:kitt/domain/dialogue_policy.dart';
import 'package:kitt/ports/stt_port.dart';

void main() {
  group('DialoguePolicy', () {
    const policy = DialoguePolicy();

    test('pas d\'abstention quand la confiance est absente', () {
      expect(policy.shouldClarify(const SttResult(text: 'bonjour')), isFalse);
    });

    test('clarifie sous le seuil de confiance', () {
      expect(
        policy.shouldClarify(const SttResult(text: 'bonjour', confidence: 0.2)),
        isTrue,
      );
      expect(
        policy.shouldClarify(const SttResult(text: 'bonjour', confidence: 0.9)),
        isFalse,
      );
    });

    test('détecte un énoncé inexploitable', () {
      expect(policy.isUsable(const SttResult(text: '')), isFalse);
      expect(policy.isUsable(const SttResult(text: 'ok')), isTrue);
    });

    test('barge-in seulement pendant responding', () {
      expect(policy.allowsBargeIn(PipelineState.responding), isTrue);
      expect(policy.allowsBargeIn(PipelineState.listening), isFalse);
    });
  });
}
