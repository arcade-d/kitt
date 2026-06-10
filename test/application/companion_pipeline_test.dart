import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/memory/in_memory_store.dart';
import 'package:kitt/adapters/mock/mock_audio_out.dart';
import 'package:kitt/adapters/mock/mock_llm.dart';
import 'package:kitt/adapters/mock/mock_stt.dart';
import 'package:kitt/adapters/mock/mock_tts.dart';
import 'package:kitt/application/companion_pipeline.dart';
import 'package:kitt/application/pipeline_state.dart';
import 'package:kitt/domain/persona.dart';

CompanionPipeline buildPipeline({MockStt? stt, MockLlm? llm}) {
  return CompanionPipeline(
    persona: Persona.fallback,
    stt: stt ?? MockStt(cannedText: 'Bonjour KITT'),
    llm: llm ?? MockLlm(reply: 'Tout est sous contrôle.'),
    tts: MockTts(),
    audioOut: MockAudioOut(),
    memory: InMemoryStore(),
  );
}

void main() {
  group('CompanionPipeline', () {
    test(
      'un tour nominal traverse listening→thinking→responding→idle',
      () async {
        final pipeline = buildPipeline();
        final states = <PipelineState>[];
        final sub = pipeline.states.listen(states.add);

        final reply = await pipeline.runTurn(
          List<double>.filled(160, 0),
          16000,
        );

        expect(reply, 'Tout est sous contrôle.');
        expect(
          states,
          containsAllInOrder(<PipelineState>[
            PipelineState.listening,
            PipelineState.thinking,
            PipelineState.responding,
            PipelineState.idle,
          ]),
        );
        expect(pipeline.state, PipelineState.idle);
        expect(pipeline.conversation.length, 2); // user + assistant
        await sub.cancel();
        await pipeline.dispose();
      },
    );

    test(
      'énoncé inexploitable déclenche la clarification et ne répond pas',
      () async {
        final pipeline = buildPipeline(stt: MockStt(cannedText: ''));
        final states = <PipelineState>[];
        final sub = pipeline.states.listen(states.add);

        final reply = await pipeline.runTurn(
          List<double>.filled(160, 0),
          16000,
        );

        expect(reply, isNull);
        expect(states, contains(PipelineState.clarifying));
        expect(pipeline.state, PipelineState.idle);
        expect(pipeline.conversation.isEmpty, isTrue);
        await sub.cancel();
        await pipeline.dispose();
      },
    );

    test('faible confiance STT déclenche aussi la clarification', () async {
      final pipeline = buildPipeline(
        stt: MockStt(cannedText: 'peut-être', confidence: 0.2),
      );
      final reply = await pipeline.runTurn(List<double>.filled(160, 0), 16000);
      expect(reply, isNull);
      await pipeline.dispose();
    });
  });
}
