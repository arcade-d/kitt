import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/application/pipeline_state.dart';

void main() {
  group('ConversationStateMachine', () {
    test('parcours nominal idle→listening→thinking→responding→idle', () {
      final m = ConversationStateMachine();
      expect(m.fire(PipelineEvent.wake), PipelineState.listening);
      expect(m.fire(PipelineEvent.speechEnd), PipelineState.thinking);
      expect(m.fire(PipelineEvent.firstToken), PipelineState.responding);
      expect(m.fire(PipelineEvent.responseEnd), PipelineState.idle);
    });

    test('boucle de clarification', () {
      final m = ConversationStateMachine();
      m.fire(PipelineEvent.wake);
      expect(m.fire(PipelineEvent.lowConfidence), PipelineState.clarifying);
      expect(m.fire(PipelineEvent.clarified), PipelineState.listening);
    });

    test('barge-in pendant responding repasse en écoute', () {
      final m = ConversationStateMachine();
      m
        ..fire(PipelineEvent.wake)
        ..fire(PipelineEvent.speechEnd)
        ..fire(PipelineEvent.firstToken);
      expect(m.fire(PipelineEvent.bargeIn), PipelineState.listening);
    });

    test('transition invalide lève StateError', () {
      final m = ConversationStateMachine();
      expect(() => m.fire(PipelineEvent.firstToken), throwsStateError);
    });

    test('reset ramène toujours à idle', () {
      final m = ConversationStateMachine();
      m.fire(PipelineEvent.wake);
      expect(m.fire(PipelineEvent.reset), PipelineState.idle);
    });
  });
}
