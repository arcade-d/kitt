# Adapter LLM CroissantLLM (llamadart) — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brancher CroissantLLM (GGUF) via `llamadart` dans un isolate derrière le `LlmPort` de KITT, persona injectée en system prompt ; périmètre chat seul ; modèle fourni par le `ModelManager`.

**Architecture:** Adapter hexagonal `LlamaCroissantLlm` (glue isolate + natif, dans `lib/adapters/llama/`), porté du wrapper de référence Tachikoma (`0840801^`). Le `LlmPort` gagne `initialize()` (répercuté sur `MockLlm` + pipeline). Le `ModelManager` gagne le catalogue + le téléchargement du GGUF. La logique pure (catalogue/chemins/download) est testée ; l'adapter llamadart est validé par `analyze` + device/CI (natif non exécutable sur l'hôte).

**Tech Stack:** Flutter/Dart 3.12, Riverpod, `llamadart` (isolate, llama.cpp), `http` (+ `package:http/testing.dart`), `dart:isolate`.

**Référence spec:** `docs/superpowers/specs/2026-06-10-adapter-llm-croissant-design.md`

---

## Structure des fichiers

Modifiés :
- `pubspec.yaml` — ajout `llamadart: ^0.6.9`.
- `lib/ports/llm_port.dart` — ajout `Future<void> initialize();`.
- `lib/adapters/mock/mock_llm.dart` — `initialize()` no-op.
- `lib/application/companion_pipeline.dart` — `await _llm.initialize()` dans `initialize()`.
- `lib/adapters/models/model_catalog.dart` — consts LLM + `ModelStatus.llmReady`.
- `lib/adapters/models/model_manager.dart` — `llmModelPath`, `isLlmModelAvailable`, `getStatus().llmReady`, `downloadLlmModel`.
- `lib/application/providers.dart` — mode `real` : `llm: LlamaCroissantLlm(mm.llmModelPath)`.
- `test/adapters/models/model_manager_test.dart` — MAJ test `ModelStatus.allReady` (3 champs) + tests LLM.

Créés :
- `lib/adapters/llama/llama_croissant_llm.dart` — adapter isolate (glue).
- `test/application/pipeline_llm_init_test.dart` — vérifie que `pipeline.initialize()` initialise le LLM.

---

## Task 1: Dépendance llamadart

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Ajouter la dépendance**

Dans `pubspec.yaml`, dans le bloc `dependencies`, juste après la ligne `http: ^1.6.0`, ajouter :

```yaml
  # LLM local (CroissantLLM GGUF via llama.cpp, en isolate)
  llamadart: ^0.6.9
```

- [ ] **Step 2: Résoudre**

Run: `flutter pub get`
Expected: `Got dependencies!`. Si la résolution échoue (conflit de contraintes avec une dépendance existante), reporter BLOCKED avec l'erreur exacte du résolveur — ne pas changer arbitrairement les versions.

- [ ] **Step 3: Analyse (base inchangée)**

Run: `flutter analyze`
Expected: `No issues found!` (aucune utilisation encore).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "build(deps): llamadart (CroissantLLM GGUF en isolate)"
```

---

## Task 2: `LlmPort.initialize()` + MockLlm + pipeline

**Files:**
- Create: `test/application/pipeline_llm_init_test.dart`
- Modify: `lib/ports/llm_port.dart`
- Modify: `lib/adapters/mock/mock_llm.dart`
- Modify: `lib/application/companion_pipeline.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/application/pipeline_llm_init_test.dart` :

```dart
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
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/application/pipeline_llm_init_test.dart`
Expected: FAIL à la compilation — `_SpyLlm` ne peut pas `@override Future<void> initialize()` car `LlmPort` ne le déclare pas (et le pipeline ne l'appelle pas).

- [ ] **Step 3: Ajouter `initialize()` au `LlmPort`**

Dans `lib/ports/llm_port.dart`, ajouter cette méthode **en première position** dans le corps de `abstract class LlmPort {` (juste avant `set systemPrompt`) :

```dart
  /// Charge le modèle / prépare le moteur. Idempotent. À appeler avant
  /// [generateChat] / [generateChatStream] (le system prompt doit être fixé
  /// avant cet appel).
  Future<void> initialize();
```

- [ ] **Step 4: Implémenter `initialize()` dans `MockLlm`**

Dans `lib/adapters/mock/mock_llm.dart`, ajouter cette méthode juste après la ligne `String get systemPrompt => _systemPrompt;` :

```dart
  @override
  Future<void> initialize() async {}
```

- [ ] **Step 5: Appeler `_llm.initialize()` dans le pipeline**

Dans `lib/application/companion_pipeline.dart`, dans la méthode `initialize()`, ajouter l'init du LLM. Remplacer :

```dart
  Future<void> initialize() async {
    await _stt.initialize();
    await _tts.initialize();
  }
```
par :
```dart
  Future<void> initialize() async {
    await _stt.initialize();
    await _tts.initialize();
    await _llm.initialize();
  }
```

- [ ] **Step 6: Lancer le test (doit passer) + non-régression**

Run: `flutter test test/application/pipeline_llm_init_test.dart`
Expected: PASS (1 test).
Run: `flutter test`
Expected: PASS — toute la suite (les tests existants n'appellent pas `pipeline.initialize()`, et `MockLlm.initialize()` est un no-op).

- [ ] **Step 7: Analyse + commit**

Run: `flutter analyze`
Expected: `No issues found!`
```bash
git add lib/ports/llm_port.dart lib/adapters/mock/mock_llm.dart lib/application/companion_pipeline.dart test/application/pipeline_llm_init_test.dart
git commit -m "feat(llm): LlmPort.initialize() + répercussion MockLlm/pipeline + test"
```

---

## Task 3: ModelManager — catalogue LLM + chemins + statut

**Files:**
- Modify: `lib/adapters/models/model_catalog.dart`
- Modify: `lib/adapters/models/model_manager.dart`
- Modify: `test/adapters/models/model_manager_test.dart`

- [ ] **Step 1: Mettre à jour les tests (échouent)**

Dans `test/adapters/models/model_manager_test.dart` :

(a) Remplacer le test existant `ModelStatus.allReady` (groupe `catalogue`) par :

```dart
    test('ModelStatus.allReady', () {
      expect(
        const ModelStatus(
          sttReady: true,
          ttsReady: true,
          llmReady: true,
        ).allReady,
        isTrue,
      );
      expect(
        const ModelStatus(
          sttReady: true,
          ttsReady: true,
          llmReady: false,
        ).allReady,
        isFalse,
      );
    });
```

(b) Ajouter, **dans le groupe `ModelManager`** (après le dernier test), ce test :

```dart
    test('llmModelPath + isLlmModelAvailable + getStatus.llmReady', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.llmModelPath, '${tmp.path}/models/$llmFileName');
      expect(mm.isLlmModelAvailable, isFalse);
      expect(mm.getStatus().llmReady, isFalse);
      File(mm.llmModelPath).writeAsStringSync('gguf');
      expect(mm.isLlmModelAvailable, isTrue);
      expect(mm.getStatus().llmReady, isTrue);
    });
```

- [ ] **Step 2: Lancer (doit échouer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: FAIL — `ModelStatus` n'a pas `llmReady`, `ModelManager` n'a pas `llmModelPath`/`isLlmModelAvailable`, `llmFileName` indéfini.

- [ ] **Step 3: Catalogue LLM + ModelStatus (`model_catalog.dart`)**

Dans `lib/adapters/models/model_catalog.dart` :

(a) Après la ligne `const String ttsDirName = 'tts';`, ajouter :

```dart
const String llmFileName = 'croissantllmchat-v0.1.Q4_K_M.gguf';
const String llmUrl =
    'https://huggingface.co/croissantllm/CroissantLLMChat-v0.1-GGUF/resolve/main/croissantllmchat-v0.1.Q4_K_M.gguf';
```

(b) Remplacer la classe `ModelStatus` par :

```dart
class ModelStatus {
  const ModelStatus({
    required this.sttReady,
    required this.ttsReady,
    required this.llmReady,
  });

  final bool sttReady;
  final bool ttsReady;
  final bool llmReady;

  bool get allReady => sttReady && ttsReady && llmReady;
}
```

- [ ] **Step 4: Chemins + dispo + statut (`model_manager.dart`)**

Dans `lib/adapters/models/model_manager.dart` :

(a) Juste après le getter `String get ttsModelDir => '$_modelsDir/$ttsDirName';`, ajouter :

```dart
  String get llmModelPath => '$_modelsDir/$llmFileName';
```

(b) Juste après le getter `isTtsModelAvailable` (le bloc se terminant par `File('$ttsModelDir/espeak-ng-data/phontab').existsSync();`), ajouter :

```dart

  bool get isLlmModelAvailable => File(llmModelPath).existsSync();
```

(c) Remplacer la méthode `getStatus()` par :

```dart
  ModelStatus getStatus() => ModelStatus(
        sttReady: isSttModelAvailable,
        ttsReady: isTtsModelAvailable,
        llmReady: isLlmModelAvailable,
      );
```

- [ ] **Step 5: Lancer (doit passer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: PASS (catalogue + ModelManager, dont le nouveau test LLM).

- [ ] **Step 6: Analyse + commit**

Run: `flutter analyze`
Expected: `No issues found!`
```bash
git add lib/adapters/models/model_catalog.dart lib/adapters/models/model_manager.dart test/adapters/models/model_manager_test.dart
git commit -m "feat(models): catalogue CroissantLLM + chemins/dispo/statut LLM + tests"
```

---

## Task 4: ModelManager — `downloadLlmModel` (chunks + reprise + fallback)

**Files:**
- Modify: `lib/adapters/models/model_manager.dart`
- Modify: `test/adapters/models/model_manager_test.dart`

- [ ] **Step 1: Écrire les tests qui échouent**

Dans `test/adapters/models/model_manager_test.dart`, ajouter dans le groupe `ModelManager` (après le test de la Task 3) :

```dart
    test('downloadLlmModel : saute si déjà présent (aucun réseau)', () async {
      final mm = make(
        client: MockClient(
          (_) async => throw StateError('ne doit pas télécharger'),
        ),
      );
      await mm.initialize();
      File(mm.llmModelPath).writeAsStringSync('present');
      final progress = <double>[];
      await mm.downloadLlmModel(onProgress: progress.add);
      expect(progress.last, 1.0);
    });

    test('downloadLlmModel : fallback mono-flux écrit le GGUF', () async {
      // Le serveur répond 200 (pas 206) au probe Range → pas de chunks → mono-flux.
      final mm = make(
        client: MockClient((_) async => http.Response('GGUF', 200)),
      );
      await mm.initialize();
      await mm.downloadLlmModel(onProgress: (_) {});
      expect(File(mm.llmModelPath).readAsStringSync(), 'GGUF');
    });
```

- [ ] **Step 2: Lancer (doit échouer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: FAIL — `downloadLlmModel` indéfini.

- [ ] **Step 3: Implémenter `downloadLlmModel` + `_downloadSingleStream`**

Dans `lib/adapters/models/model_manager.dart`, ajouter ces membres juste **avant** la méthode `void dispose() => _client.close();` (et ajouter la constante de classe en tête, après les champs `_baseDirProvider`/`_client`). 

(a) Ajouter la constante de classe (près des autres `static const` ou en haut de la classe) :

```dart
  static const _parallelChunks = 2;
```

(b) Ajouter les deux méthodes :

```dart
  /// Télécharge le GGUF LLM (gros fichier) en chunks parallèles avec reprise.
  /// Repli mono-flux si le serveur ne supporte pas les requêtes Range.
  /// Porté de Tachikoma `model_manager.dart` (sans wakelock, via _client injecté).
  Future<void> downloadLlmModel({
    required void Function(double progress) onProgress,
  }) async {
    final targetPath = llmModelPath;
    final targetFile = File(targetPath);
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      onProgress(1.0);
      return;
    }

    int? totalBytes;
    var acceptsRange = false;
    try {
      final probe = http.Request('GET', Uri.parse(llmUrl));
      probe.headers['Range'] = 'bytes=0-0';
      final probeResponse = await _client.send(probe);
      await probeResponse.stream.drain<void>();
      if (probeResponse.statusCode == 206) {
        acceptsRange = true;
        final contentRange = probeResponse.headers['content-range'] ?? '';
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        if (match != null) {
          totalBytes = int.tryParse(match.group(1)!);
        }
      }
    } catch (_) {}

    if (totalBytes == null || totalBytes == 0 || !acceptsRange) {
      await _downloadSingleStream(llmUrl, targetPath, onProgress);
      return;
    }

    final fileSize = totalBytes;
    final chunkSize = (fileSize / _parallelChunks).ceil();
    final chunkFiles = <File>[];
    final received = List<int>.filled(_parallelChunks, 0);

    void reportProgress() {
      final total = received.fold<int>(0, (a, b) => a + b);
      onProgress(total / fileSize);
    }

    final futures = <Future<void>>[];
    for (var i = 0; i < _parallelChunks; i++) {
      final start = i * chunkSize;
      final end = (i + 1) * chunkSize - 1;
      final rangeEnd = end >= fileSize ? fileSize - 1 : end;
      final chunkFile = File('$targetPath.part$i');
      chunkFiles.add(chunkFile);

      final expectedSize = rangeEnd - start + 1;
      if (chunkFile.existsSync() && chunkFile.lengthSync() >= expectedSize) {
        received[i] = expectedSize;
        reportProgress();
        continue;
      }

      futures.add(() async {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final chunkExisting =
                chunkFile.existsSync() ? chunkFile.lengthSync() : 0;
            if (chunkExisting >= expectedSize) {
              received[i] = expectedSize;
              reportProgress();
              return;
            }
            final request = http.Request('GET', Uri.parse(llmUrl));
            request.headers['Range'] = 'bytes=${start + chunkExisting}-$rangeEnd';
            final response = await _client.send(request);
            if (response.statusCode != 206 && response.statusCode != 200) {
              throw Exception('HTTP ${response.statusCode}');
            }
            final sink = chunkFile.openWrite(mode: FileMode.append);
            received[i] = chunkExisting;
            await for (final data in response.stream) {
              sink.add(data);
              received[i] += data.length;
              reportProgress();
            }
            await sink.close();
            return;
          } catch (e) {
            if (attempt == 2) rethrow;
          }
        }
      }());
    }

    await Future.wait(futures);

    final tmpFile = File('$targetPath.tmp');
    final sink = tmpFile.openWrite();
    for (final chunkFile in chunkFiles) {
      await sink.addStream(chunkFile.openRead());
    }
    await sink.close();

    if (tmpFile.lengthSync() != fileSize) {
      await tmpFile.delete();
      for (final f in chunkFiles) {
        if (f.existsSync()) await f.delete();
      }
      throw Exception(
        'Taille téléchargée incohérente: ${tmpFile.lengthSync()} != $fileSize',
      );
    }

    for (final f in chunkFiles) {
      if (f.existsSync()) await f.delete();
    }
    await tmpFile.rename(targetPath);
    onProgress(1.0);
  }

  Future<void> _downloadSingleStream(
    String url,
    String targetPath,
    void Function(double) onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Téléchargement échoué: HTTP ${response.statusCode}');
    }
    final totalBytes = response.contentLength ?? -1;
    final tmpFile = File('$targetPath.tmp');
    final sink = tmpFile.openWrite();
    var receivedBytes = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0) onProgress(receivedBytes / totalBytes);
    }
    await sink.close();
    await tmpFile.rename(targetPath);
    onProgress(1.0);
  }
```

> Note : le chemin **chunks-parallèles/Range** (HTTP 206 + `content-range`) n'est pas couvert par les tests unitaires (difficile à simuler proprement avec MockClient) — il est validé en device/CI. Les tests couvrent *skip-si-présent* et *fallback mono-flux*.

- [ ] **Step 4: Lancer (doit passer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: PASS (les 2 nouveaux tests `downloadLlmModel` inclus).

- [ ] **Step 5: Analyse + commit**

Run: `flutter analyze`
Expected: `No issues found!`
```bash
git add lib/adapters/models/model_manager.dart test/adapters/models/model_manager_test.dart
git commit -m "feat(models): downloadLlmModel (chunks parallèles + reprise + fallback) + tests"
```

---

## Task 5: Adapter `LlamaCroissantLlm` (glue isolate — analyze only)

> Glue sur `llamadart` (isolate + natif llama.cpp) : non testable sur l'hôte.
> Vérifié par `flutter analyze` (compile + implémente `LlmPort`) ; inférence réelle
> validée device / build APK CI.

**Files:**
- Create: `lib/adapters/llama/llama_croissant_llm.dart`

- [ ] **Step 1: Implémenter l'adapter**

`lib/adapters/llama/llama_croissant_llm.dart` :

```dart
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
```

- [ ] **Step 2: Vérifier l'analyse (avec alignement d'API si besoin)**

Run: `flutter analyze`
Expected: `No issues found!`

Si l'analyse remonte des symboles `llamadart` renommés/différents (`LlamaEngine`, `LlamaBackend`, `ChatSession`, `ModelParams`, `ModelParams.maxGpuLayers`, `GenerationParams`, `LlamaTextContent`, `session.create(...)`, `chunk.choices.first.delta.content`), inspecter le package résolu sous `~/.pub-cache/hosted/pub.dev/llamadart-*/lib` (ex. `grep -rn "class LlamaEngine\|class ChatSession\|class GenerationParams\|class ModelParams\|maxGpuLayers\|class LlamaTextContent" <pkg>/lib`) et **aligner uniquement les noms/signatures d'API** à la version résolue, en gardant le comportement (chat persistant + streaming par tokens, init avec system prompt, dispose). Reporter toute déviation (ancien → nouveau). Ne pas changer l'interface `LlmPort`.

- [ ] **Step 3: Non-régression + commit**

Run: `flutter test`
Expected: PASS (suite complète ; l'adapter n'est pas encore câblé, mais compile).
```bash
git add lib/adapters/llama/llama_croissant_llm.dart
git commit -m "feat(llm): adapter LlamaCroissantLlm (llamadart isolate) implements LlmPort"
```

---

## Task 6: Câblage providers (mode réel)

**Files:**
- Modify: `lib/application/providers.dart`

- [ ] **Step 1: Brancher l'adapter réel**

Dans `lib/application/providers.dart` :

(a) Ajouter l'import (avec les autres imports d'adapters, ordre alphabétique — juste après l'import `record_audio_in.dart`/avant `memory/`... place-le près des autres adapters, ex. après la ligne important `just_audio_out.dart`) :

```dart
import '../adapters/llama/llama_croissant_llm.dart';
```

(b) Dans `adaptersProvider`, branche `if (_useRealAdapters)`, remplacer `llm: MockLlm(),` par :

```dart
      llm: LlamaCroissantLlm(mm.llmModelPath),
```

(La branche mock reste `llm: MockLlm()`.)

- [ ] **Step 2: Analyse (compile mock ET réel)**

Run: `flutter analyze`
Expected: `No issues found!` (l'analyse couvre les deux branches à la compilation).

- [ ] **Step 3: Tests (mode mock par défaut)**

Run: `flutter test`
Expected: PASS — `providers_test` (mode mock → `MockStt/MockTts/MockAudioIn`, et le LLM reste `MockLlm` en mock) et toute la suite restent verts.

- [ ] **Step 4: Commit**

```bash
git add lib/application/providers.dart
git commit -m "feat(app): câble LlamaCroissantLlm en mode KITT_ADAPTERS=real"
```

---

## Task 7: Vérification finale

**Files:** aucun (vérification)

- [ ] **Step 1: Format**

Run: `dart format .`
Then: `dart format --output=none --set-exit-if-changed .`
Expected: `0 changed`. (Si `dart format` reformate des fichiers de ce lot, voir la note ci-dessous puis re-vérifier.)

> Note (leçon du lot précédent) : le formateur Dart 3.12 peut reflower un appel multi-lignes en forme compacte **sans** virgule finale, ce que le lint `require_trailing_commas` refuse alors. Si `flutter analyze` (Step 2) signale `require_trailing_commas` après le format, ajouter la virgule finale au point indiqué (le formateur conserve la forme éclatée avec virgule) puis relancer `dart format .` + analyze : les deux passent.

- [ ] **Step 2: Analyse complète**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Suite complète**

Run: `flutter test`
Expected: PASS — dont `pipeline_llm_init_test`, les tests ModelManager-LLM (catalogue/chemins/download), et toute la suite existante.

- [ ] **Step 4: Vérifier que le mode réel compile**

Run: `flutter analyze` (déjà fait au Step 2 — couvre la branche `real` de `adaptersProvider`). L'inférence réelle (isolate llamadart + GGUF) n'est PAS exécutable ici ; elle est validée device / build APK CI.

- [ ] **Step 5: Commit éventuel de format**

```bash
git add -A
git diff --cached --quiet || git commit -m "chore(format): dart format"
```

---

## Critères d'acceptation (rappel du spec §9)

1. `flutter pub get` résout `llamadart ^0.6.9`. *(Task 1)*
2. `flutter analyze` : 0 issue (adapter llamadart compile + implémente `LlmPort`). *(Task 5, 7)*
3. `flutter test` : tout vert, dont les nouveaux tests ModelManager-LLM + le test d'appel de `llm.initialize()` par le pipeline, sans device/natif/modèle. *(Task 2, 3, 4, 7)*
4. `KITT_ADAPTERS=mock` (défaut) : comportement inchangé (MockLlm a un `initialize()` no-op). *(Task 2, 6)*
5. `KITT_ADAPTERS=real` : compile ; le faisceau câble `LlamaCroissantLlm(mm.llmModelPath)`. *(Task 6)*
6. Aucun poids `*.gguf` committé (`.gitignore` exclut déjà `*.gguf`). *(par construction)*
7. `LlmPort.initialize()` ajouté et répercuté (MockLlm + pipeline) sans régression. *(Task 2)*
```
