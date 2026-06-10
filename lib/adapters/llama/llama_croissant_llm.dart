import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';

import '../../ports/llm_port.dart';
import '../models/model_not_available.dart';

// ── Messages isolate ───────────────────────────────────────────
sealed class _LlmRequest {}

class _InitRequest extends _LlmRequest {
  _InitRequest({required this.modelPath, required this.systemPrompt});

  final String modelPath;
  final String systemPrompt;
}

class _ChatRequest extends _LlmRequest {
  _ChatRequest({
    required this.message,
    required this.params,
    this.useSession = true,
    this.systemPrompt = '',
  });

  final String message;
  final GenerationParams params;
  final bool useSession;
  final String systemPrompt;
}

class _DisposeRequest extends _LlmRequest {}

class _LlmResponse {
  _LlmResponse({this.text = '', this.error});

  final String text;
  final String? error;
}

class _TokenChunk {
  _TokenChunk(this.text);

  final String text;
}

// CroissantLLM : contexte natif 2048.
const ModelParams _modelParams = ModelParams(
  contextSize: 2048,
  gpuLayers: ModelParams.maxGpuLayers,
  numberOfThreads: 4,
  numberOfThreadsBatch: 4,
  batchSize: 512,
  microBatchSize: 256,
);

// ── Worker isolate ─────────────────────────────────────────────
Future<void> _llmWorker(SendPort mainPort) async {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);

  LlamaEngine? engine;
  ChatSession? persistentSession;

  await for (final message in receivePort) {
    final (request, SendPort replyPort) = message as (Object, SendPort);

    if (request is _InitRequest) {
      try {
        engine = LlamaEngine(LlamaBackend());
        await engine.loadModel(request.modelPath, modelParams: _modelParams);
        persistentSession = ChatSession(engine)
          ..systemPrompt = request.systemPrompt;
        replyPort.send(_LlmResponse(text: 'ok'));
      } catch (e) {
        replyPort.send(_LlmResponse(error: e.toString()));
      }
    } else if (request is _ChatRequest) {
      try {
        final ChatSession session;
        if (request.useSession && persistentSession != null) {
          session = persistentSession;
        } else {
          session = ChatSession(engine!)..systemPrompt = request.systemPrompt;
        }
        final buffer = StringBuffer();
        await for (final chunk in session.create(
          [LlamaTextContent(request.message)],
          params: request.params,
        )) {
          final text = chunk.choices.first.delta.content;
          if (text != null && text.isNotEmpty) {
            buffer.write(text);
            replyPort.send(_TokenChunk(text));
          }
        }
        replyPort.send(_LlmResponse(text: buffer.toString()));
      } catch (e) {
        replyPort.send(_LlmResponse(error: e.toString()));
      }
    } else if (request is _DisposeRequest) {
      await engine?.dispose();
      engine = null;
      persistentSession = null;
      replyPort.send(_LlmResponse(text: 'disposed'));
      receivePort.close();
      return;
    }
  }
}

// ── Handle isolate ─────────────────────────────────────────────
class _LlmIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;

  Future<void> start() async {
    final receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_llmWorker, receivePort.sendPort);
    _sendPort = await receivePort.first as SendPort;
  }

  Future<_LlmResponse> send(_LlmRequest request) async {
    final replyPort = ReceivePort();
    _sendPort!.send((request, replyPort.sendPort));
    await for (final msg in replyPort) {
      if (msg is _LlmResponse) {
        replyPort.close();
        return msg;
      }
      // _TokenChunk ignoré pour les appels non-streaming.
    }
    throw StateError('Isolate fermé sans réponse');
  }

  Stream<String> sendStreaming(_LlmRequest request) async* {
    final replyPort = ReceivePort();
    _sendPort!.send((request, replyPort.sendPort));
    await for (final msg in replyPort) {
      if (msg is _TokenChunk) {
        yield msg.text;
      } else if (msg is _LlmResponse) {
        if (msg.error != null) throw StateError(msg.error!);
        replyPort.close();
        return;
      }
    }
  }

  Future<void> dispose() async {
    if (_sendPort != null) {
      await send(_DisposeRequest());
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }
}

// ── Adapter ────────────────────────────────────────────────────
/// LLM réel : CroissantLLM (GGUF) via `llamadart` dans un isolate.
/// Porté de Tachikoma `0840801^:lib/services/llm_service.dart` (partie chat).
/// Le system prompt = persona de KITT (fixée avant [initialize]).
class LlamaCroissantLlm implements LlmPort {
  LlamaCroissantLlm(this.modelPath);

  final String modelPath;
  final _LlmIsolate _isolate = _LlmIsolate();
  bool _initialized = false;
  String _systemPrompt = '';

  static const GenerationParams _chatParams = GenerationParams(
    maxTokens: 150,
    temp: 0.4,
    topK: 30,
    topP: 0.85,
    penalty: 1.5,
  );

  static const GenerationParams _reformulateParams = GenerationParams(
    maxTokens: 80,
    temp: 0.3,
    topK: 10,
    topP: 0.9,
    penalty: 1.0,
  );

  /// À fixer **avant** [initialize] (le pipeline le fait au constructeur).
  @override
  set systemPrompt(String prompt) => _systemPrompt = prompt;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    if (!File(modelPath).existsSync()) {
      throw ModelNotAvailable('Modèle LLM manquant: $modelPath');
    }
    await _isolate.start();
    final res = await _isolate.send(
      _InitRequest(modelPath: modelPath, systemPrompt: _systemPrompt),
    );
    if (res.error != null) {
      await _isolate.dispose();
      throw StateError('Échec init LLM: ${res.error}');
    }
    _initialized = true;
  }

  @override
  Future<String> generateChat(String prompt, {String? toolContext}) async {
    if (toolContext != null) return _reformulate(prompt, toolContext);
    final res = await _isolate.send(
      _ChatRequest(message: prompt, params: _chatParams),
    );
    if (res.error != null) throw StateError(res.error!);
    return res.text.trim();
  }

  @override
  Stream<String> generateChatStream(
    String prompt, {
    String? toolContext,
  }) async* {
    if (toolContext != null) {
      yield await _reformulate(prompt, toolContext);
      return;
    }
    yield* _isolate.sendStreaming(
      _ChatRequest(message: prompt, params: _chatParams),
    );
  }

  Future<String> _reformulate(String prompt, String toolContext) async {
    const reformulatePrompt =
        'Reformule le résultat de l\'outil en réponse française courte et '
        'utile. Tutoie l\'utilisateur. Ne pose pas de question. '
        'Maximum 2 phrases.';
    final message =
        'Question: "$prompt"\nResultat: $toolContext\nReponds en francais:';
    final res = await _isolate.send(
      _ChatRequest(
        message: message,
        params: _reformulateParams,
        useSession: false,
        systemPrompt: reformulatePrompt,
      ),
    );
    if (res.error != null) throw StateError(res.error!);
    return res.text.trim();
  }

  /// Ferme l'isolate et libère le moteur. (Hors interface LlmPort ; à appeler
  /// par le propriétaire du cycle de vie si besoin.)
  Future<void> dispose() async {
    await _isolate.dispose();
    _initialized = false;
  }
}
