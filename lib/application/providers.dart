import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/audio/just_audio_out.dart';
import '../adapters/audio/record_audio_in.dart';
import '../adapters/memory/in_memory_store.dart';
import '../adapters/mock/mock_audio_in.dart';
import '../adapters/mock/mock_audio_out.dart';
import '../adapters/mock/mock_llm.dart';
import '../adapters/mock/mock_stt.dart';
import '../adapters/mock/mock_tts.dart';
import '../adapters/mock/mock_wake_word.dart';
import '../adapters/models/model_manager.dart';
import '../adapters/llama/llama_croissant_llm.dart';
import '../adapters/sherpa/sherpa_stt.dart';
import '../adapters/sherpa/sherpa_tts.dart';
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

/// Mode des adapters, fixé au build : `--dart-define=KITT_ADAPTERS=real|mock`.
/// Défaut : `mock` (tests et CI tournent sans natif ni modèles).
const bool _useRealAdapters =
    String.fromEnvironment('KITT_ADAPTERS', defaultValue: 'mock') == 'real';

/// Faisceau des adapters vocaux résolus (mock ou réels) pour un build donné.
/// En mode réel : sherpa (STT/TTS), record/just_audio (audio) et CroissantLLM
/// (llamadart) ; en mode mock, des doubles déterministes.
class VoiceAdapters {
  const VoiceAdapters({
    required this.stt,
    required this.llm,
    required this.tts,
    required this.audioIn,
    required this.audioOut,
    required this.memory,
  });

  final SttPort stt;
  final LlmPort llm;
  final TtsPort tts;
  final AudioInPort audioIn;
  final AudioOutPort audioOut;
  final MemoryStorePort memory;
}

final wakeWordProvider = Provider<WakeWordPort>((ref) => MockWakeWord());

/// `ModelManager` initialisé (résout les dossiers de modèles). Watché seulement
/// en mode réel.
final modelManagerProvider = FutureProvider<ModelManager>((ref) async {
  final mm = ModelManager();
  await mm.initialize();
  ref.onDispose(mm.dispose);
  return mm;
});

/// Sélectionne mock ou réel. En mode réel, attend le `ModelManager` pour les
/// chemins STT/TTS.
final adaptersProvider = FutureProvider<VoiceAdapters>((ref) async {
  if (_useRealAdapters) {
    final mm = await ref.watch(modelManagerProvider.future);
    return VoiceAdapters(
      stt: SherpaStt(mm.sttModelDir),
      llm: LlamaCroissantLlm(mm.llmModelPath),
      tts: SherpaTts(mm.ttsModelDir),
      audioIn: RecordAudioIn(),
      audioOut: JustAudioOut(),
      memory: InMemoryStore(),
    );
  }
  return VoiceAdapters(
    stt: MockStt(),
    llm: MockLlm(),
    tts: MockTts(),
    audioIn: MockAudioIn(),
    audioOut: MockAudioOut(),
    memory: InMemoryStore(),
  );
});

/// Persona chargée depuis les assets, avec repli si l'asset manque.
final personaProvider = FutureProvider<Persona>((ref) async {
  try {
    return await Persona.loadDefault();
  } catch (_) {
    return Persona.fallback;
  }
});

/// Pipeline companion assemblé. Disponible une fois persona + adapters prêts.
final pipelineProvider = FutureProvider<CompanionPipeline>((ref) async {
  final persona = await ref.watch(personaProvider.future);
  final adapters = await ref.watch(adaptersProvider.future);
  final pipeline = CompanionPipeline(
    persona: persona,
    stt: adapters.stt,
    llm: adapters.llm,
    tts: adapters.tts,
    audioOut: adapters.audioOut,
    memory: adapters.memory,
  );
  await pipeline.initialize();
  ref.onDispose(pipeline.dispose);
  return pipeline;
});

/// État courant du pipeline pour l'UI.
final pipelineStateProvider = StreamProvider<PipelineState>((ref) async* {
  final pipeline = await ref.watch(pipelineProvider.future);
  yield pipeline.state;
  yield* pipeline.states;
});

/// Niveau RMS du micro pour le modulateur vocal.
final audioLevelProvider = StreamProvider<double>((ref) async* {
  final adapters = await ref.watch(adaptersProvider.future);
  yield* adapters.audioIn.audioLevel;
});
