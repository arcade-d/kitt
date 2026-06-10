import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/memory/in_memory_store.dart';
import 'package:kitt/adapters/mock/mock_audio_out.dart';
import 'package:kitt/adapters/mock/mock_stt.dart';
import 'package:kitt/adapters/mock/mock_tts.dart';
import 'package:kitt/application/companion_pipeline.dart';
import 'package:kitt/domain/persona.dart';
import 'package:kitt/ports/llm_port.dart';

/// Espion : compte les appels à initialize().
class _SpyLlm implements LlmPort {
  bool initialized = false;

  @override
  set systemPrompt(String prompt) {}

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<String> generateChat(String prompt, {String? toolContext}) async => '';

  @override
  Stream<String> generateChatStream(
    String prompt, {
    String? toolContext,
  }) async* {}
}

void main() {
  test('CompanionPipeline.initialize() initialise le LLM', () async {
    final spy = _SpyLlm();
    final pipeline = CompanionPipeline(
      persona: Persona.fallback,
      stt: MockStt(cannedText: 'x'),
      llm: spy,
      tts: MockTts(),
      audioOut: MockAudioOut(),
      memory: InMemoryStore(),
    );
    await pipeline.initialize();
    expect(spy.initialized, isTrue);
    await pipeline.dispose();
  });
}
