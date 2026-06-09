import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/memory/in_memory_store.dart';
import '../adapters/mock/mock_audio_in.dart';
import '../adapters/mock/mock_audio_out.dart';
import '../adapters/mock/mock_llm.dart';
import '../adapters/mock/mock_stt.dart';
import '../adapters/mock/mock_tts.dart';
import '../adapters/mock/mock_wake_word.dart';
import '../domain/persona.dart';
import '../ports/audio_in_port.dart';
import '../ports/audio_out_port.dart';
import '../ports/llm_port.dart';
import '../ports/memory_store_port.dart';
import '../ports/stt_port.dart';
import '../ports/tts_port.dart';
import '../ports/wake_word_port.dart';
import 'companion_pipeline.dart';
import 'pipeline_state.dart';

/// Câblage des ports → adapters. Aujourd'hui : adapters MOCK.
/// Remplacer ces providers par les adapters Tachikoma (STT/LLM/TTS réels)
/// branchera tout le pipeline sans toucher au domaine (cf. débrief §6.2).

final wakeWordProvider = Provider<WakeWordPort>((ref) => MockWakeWord());
final sttProvider = Provider<SttPort>((ref) => MockStt());
final llmProvider = Provider<LlmPort>((ref) => MockLlm());
final ttsProvider = Provider<TtsPort>((ref) => MockTts());
final audioOutProvider = Provider<AudioOutPort>((ref) => MockAudioOut());
final audioInProvider = Provider<AudioInPort>((ref) => MockAudioIn());
final memoryProvider = Provider<MemoryStorePort>((ref) => InMemoryStore());

/// Persona chargée depuis les assets, avec repli si l'asset manque.
final personaProvider = FutureProvider<Persona>((ref) async {
  try {
    return await Persona.loadDefault();
  } catch (_) {
    return Persona.fallback;
  }
});

/// Pipeline companion assemblé. Disponible une fois la persona chargée.
final pipelineProvider = FutureProvider<CompanionPipeline>((ref) async {
  final Persona persona = await ref.watch(personaProvider.future);
  final CompanionPipeline pipeline = CompanionPipeline(
    persona: persona,
    stt: ref.watch(sttProvider),
    llm: ref.watch(llmProvider),
    tts: ref.watch(ttsProvider),
    audioOut: ref.watch(audioOutProvider),
    memory: ref.watch(memoryProvider),
  );
  await pipeline.initialize();
  ref.onDispose(pipeline.dispose);
  return pipeline;
});

/// État courant du pipeline pour l'UI.
final pipelineStateProvider = StreamProvider<PipelineState>((ref) async* {
  final CompanionPipeline pipeline = await ref.watch(pipelineProvider.future);
  yield pipeline.state;
  yield* pipeline.states;
});

/// Niveau RMS du micro pour le modulateur vocal.
final audioLevelProvider = StreamProvider<double>((ref) {
  return ref.watch(audioInProvider).audioLevel;
});
