import 'dart:async';

import '../domain/context_builder.dart';
import '../domain/conversation_manager.dart';
import '../domain/dialogue_policy.dart';
import '../domain/persona.dart';
import '../ports/audio_out_port.dart';
import '../ports/llm_port.dart';
import '../ports/memory_store_port.dart';
import '../ports/stt_port.dart';
import '../ports/tts_port.dart';
import 'pipeline_state.dart';

/// Orchestration bout-en-bout du tour de parole (cf. débrief §4, §5.7).
///
/// Enchaîne wake → STT → ContextBuilder → LLM → TTS → AudioOut en pilotant la
/// [ConversationStateMachine] et en publiant l'état + les tokens en streaming.
///
/// Le wake-word lui-même est branché en amont (cf. providers) ; ici un tour
/// démarre par [runTurn], déclenché par une détection ou le bouton.
class CompanionPipeline {
  CompanionPipeline({
    required this.persona,
    required SttPort stt,
    required LlmPort llm,
    required TtsPort tts,
    required AudioOutPort audioOut,
    required MemoryStorePort memory,
    ConversationManager? conversation,
    ContextBuilder? contextBuilder,
    DialoguePolicy? policy,
  }) : _stt = stt,
       _llm = llm,
       _tts = tts,
       _audioOut = audioOut,
       _memory = memory,
       conversation = conversation ?? ConversationManager(),
       contextBuilder = contextBuilder ?? const ContextBuilder(),
       policy = policy ?? const DialoguePolicy() {
    _llm.systemPrompt = persona.systemPrompt;
  }

  final Persona persona;
  final SttPort _stt;
  final LlmPort _llm;
  final TtsPort _tts;
  final AudioOutPort _audioOut;
  final MemoryStorePort _memory;
  final ConversationManager conversation;
  final ContextBuilder contextBuilder;
  final DialoguePolicy policy;

  final ConversationStateMachine _machine = ConversationStateMachine();

  final StreamController<PipelineState> _states =
      StreamController<PipelineState>.broadcast();
  final StreamController<String> _partial =
      StreamController<String>.broadcast();

  /// Flux des états du pipeline (pour l'UI).
  Stream<PipelineState> get states => _states.stream;

  /// Flux des tokens de la réponse en cours (pour l'affichage live).
  Stream<String> get partialResponse => _partial.stream;

  PipelineState get state => _machine.state;

  bool _busy = false;

  void _transition(PipelineEvent event) {
    _machine.fire(event);
    _states.add(_machine.state);
  }

  Future<void> initialize() async {
    await _stt.initialize();
    await _tts.initialize();
  }

  /// Exécute un tour complet à partir des échantillons audio capturés.
  ///
  /// [samples]/[sampleRate] alimentent le STT. Retourne la réponse de KITT,
  /// ou `null` si une clarification a été demandée (énoncé inexploitable).
  Future<String?> runTurn(List<double> samples, int sampleRate) async {
    if (_busy) return null;
    _busy = true;
    try {
      // idle → listening
      _transition(PipelineEvent.wake);
      _stt.reset();
      _stt.acceptWaveform(samples, sampleRate);

      // listening → (endpoint)
      final SttResult heard = _stt.getResult();

      if (!policy.isUsable(heard) || policy.shouldClarify(heard)) {
        _transition(PipelineEvent.lowConfidence); // → clarifying
        _transition(PipelineEvent.clarified); // → listening
        _transition(
          PipelineEvent.reset,
        ); // → idle (le repli relancera l'écoute)
        return null;
      }

      conversation.addUser(heard.text, sttConfidence: heard.confidence);

      // listening → thinking
      _transition(PipelineEvent.speechEnd);

      final String memoryContext = await _memory.toPromptContext();
      final BuiltContext ctx = contextBuilder.build(
        persona: persona,
        history: conversation.turns
            .where((t) => t != conversation.last)
            .toList(growable: false),
        currentUtterance: heard.text,
        memoryContext: memoryContext,
      );

      final StringBuffer response = StringBuffer();
      bool firstToken = true;
      await for (final String token in _llm.generateChatStream(ctx.prompt)) {
        if (firstToken) {
          firstToken = false;
          _transition(PipelineEvent.firstToken); // thinking → responding
        }
        response.write(token);
        _partial.add(token);
      }
      if (firstToken) {
        // Réponse vide : on bascule quand même pour clore proprement.
        _transition(PipelineEvent.firstToken);
      }

      final String text = response.toString().trim();
      conversation.addAssistant(text);

      // Synthèse + lecture (TTS non streaming côté Tachikoma).
      final audio = await _tts.synthesize(text);
      if (audio != null) {
        await _audioOut.playPcm(audio, _tts.sampleRate);
      }

      // responding → idle
      _transition(PipelineEvent.responseEnd);
      return text;
    } finally {
      _busy = false;
    }
  }

  /// Interrompt la réponse en cours (barge-in) : coupe l'audio et repasse en
  /// écoute. À compléter par une vraie écoute micro pendant `responding`.
  Future<void> bargeIn() async {
    if (!policy.allowsBargeIn(_machine.state)) return;
    await _audioOut.stop();
    _transition(PipelineEvent.bargeIn);
  }

  Future<void> dispose() async {
    await _states.close();
    await _partial.close();
  }
}
