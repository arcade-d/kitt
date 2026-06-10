---
title: Adapter LLM — CroissantLLM via llamadart (chat seul)
status: approved
created_at: 2026-06-10
références: docs/DEBRIEF.md (§4.3, §5), docs/superpowers/specs/2026-06-10-adapters-reels-sherpa-audio-design.md
---

# Spec — Adapter LLM CroissantLLM (llamadart, chat seul)

> Brancher le **cerveau réel** de KITT derrière le `LlmPort` : **CroissantLLM**
> (FR natif, GGUF) via **`llamadart`** dans un isolate, injectant la **persona**
> de KITT comme system prompt. Périmètre **chat seul** — pas de tool calling,
> pas de classification. Complète la couche d'adapters réels (STT/TTS/audio
> livrés au lot précédent ; le LLM y était resté mocké).

## 1. Contexte & objectif

Au lot précédent, KITT a reçu ses adapters réels STT/TTS/audio + un `ModelManager`
injectable, le **LLM restant volontairement mock**. Ce lot remplace `MockLlm` par
un adapter **CroissantLLM via `llamadart`**, conformément à la décision KITT de
garder CroissantLLM (FR natif, 100 % offline GGUF) en divergence assumée de la
migration Gemma 4 de Tachikoma.

**Intention produit** : sur ce projet, KITT est **un chat à la voix de KITT** — un
compagnon de bord qui répond **dans le personnage** (ton posé, compétent, loyal,
pince-sans-rire), pas un assistant à outils. Le caractère vit dans la **persona**
(`assets/persona/kitt_fr.md`), déjà externalisée et chargée ; l'adapter se contente
de l'injecter comme system prompt. (Le tuning du texte de la persona — y compris le
curseur « plus in-série » dans les garde-fous IP de la décision D4 — est une
itération d'asset **hors périmètre** de ce lot.)

**Objectif** : à l'issue, en mode `KITT_ADAPTERS=real` sur device avec le modèle
présent, le pipeline bout-en-bout (STT → contexte → **CroissantLLM(persona)** → TTS)
tient une conversation en français dans le personnage. La logique pure
(catalogue/chemins/download du modèle) est testée ; l'adapter llamadart est du glue
validé par `analyze` + build APK CI + device.

## 2. Décisions actées (ce lot)

| # | Décision | Raison |
|---|----------|--------|
| L1 | **Chat seul** : porter `initialize` + `generateChat` + `generateChatStream` (avec leur branche `toolContext`/reformulation) + `systemPrompt`. **classify / generateToolCall / optimizeSearchQuery / historique reportés.** | Le `LlmPort` de KITT n'expose que le chat ; le domaine n'a ni graphe d'agents ni outils. YAGNI. |
| L2 | **Modèle = CroissantLLM base GGUF** : `croissantllmchat-v0.1.Q4_K_M.gguf` (~872 Mo, HF `croissantllm/CroissantLLMChat-v0.1-GGUF`), **téléchargeable**. | FR natif (★★★★★), offline. La variante `croissant-1.3b-tools.gguf` (locale, sans URL) est écartée : pas pratique pour dev/CI, et le tool calling est hors périmètre. |
| L3 | **Moteur = `llamadart`** dans un **isolate**, porté du wrapper de référence Tachikoma au commit `0840801^` (`lib/services/llm_service.dart`, mono-isolate). | Code de référence éprouvé. L'inférence lourde tourne hors du thread UI. |
| L4 | **`llamadart` pincé `^0.6.9`** (résout la dernière 0.6.x, proche de la réf ; dernière absolue = 0.7.2). | Minimiser la dérive d'API vis-à-vis du code de référence. L'API réelle est vérifiée/alignée à l'implémentation (comme sherpa au lot précédent). |
| L5 | **Ajout de `Future<void> initialize()` au `LlmPort`** + répercussion sur `MockLlm` (no-op) et `CompanionPipeline.initialize()`. | Le chargement du modèle GGUF est lourd ; il faut un point d'init explicite (les ports STT/TTS en ont déjà un). |
| L6 | **Persona injectée telle quelle** depuis `assets/persona/kitt_fr.md` via `ChatSession.systemPrompt`. | La persona est déjà externalisée et chargée par `personaProvider` ; l'adapter ne la réécrit pas. |

## 3. Architecture — port → adapter

Le `LlmPort` gagne un `initialize()` ; sinon le domaine et les autres ports sont
inchangés. Câblage cible (mode `real`) :

```
ports/                      adapters/                                paquet
  LlmPort (+ initialize)  ──► llama/llama_croissant_llm.dart    ──► llamadart (isolate)
                              models/model_manager.dart (LLM)   ──► http (download GGUF)
                              ↑ persona system prompt depuis assets/persona/kitt_fr.md
```

`LlamaCroissantLlm` reçoit le **chemin du GGUF** résolu par le `ModelManager` (comme
les adapters sherpa reçoivent leur `modelDir`). Il n'est **pas** un port : c'est un
adapter d'infrastructure derrière `LlmPort`.

## 4. Composants

### 4.1 Changement de port — `LlmPort.initialize()`

`lib/ports/llm_port.dart` : ajouter en tête de l'interface

```dart
/// Charge le modèle / prépare le moteur. Idempotent. À appeler avant
/// generateChat / generateChatStream.
Future<void> initialize();
```

Répercussions :
- `lib/adapters/mock/mock_llm.dart` : `@override Future<void> initialize() async {}` (no-op).
- `lib/application/companion_pipeline.dart` : dans `initialize()`, ajouter
  `await _llm.initialize();` (après `_stt`/`_tts`). Le system prompt est déjà fixé
  dans le constructeur (`_llm.systemPrompt = persona.systemPrompt;`) **avant**
  l'appel à `initialize()`, donc l'adapter charge le modèle avec la persona en place.

### 4.2 `LlamaCroissantLlm` (`lib/adapters/llama/llama_croissant_llm.dart`)

`implements LlmPort`. Porté de `0840801^:lib/services/llm_service.dart` (partie chat
uniquement). Structure :

- **Constructeur** : `LlamaCroissantLlm(this.modelPath)` (chemin absolu du `.gguf`).
- **Harness isolate** (porté) : types de messages `_InitRequest` / `_ChatRequest` /
  `_DisposeRequest` / `_LlmResponse` / `_TokenChunk`, worker `_llmWorker`, handle
  `_LlmIsolate` (`start` / `send` / `sendStreaming` / `dispose`). Le worker détient
  un `LlamaEngine(LlamaBackend())` et une `ChatSession` persistante.
- **`set systemPrompt`** : mémorise la persona dans un champ. Appliquée comme
  `sessionSystemPrompt` à la création de la session persistante dans `initialize()`.
  (Si `systemPrompt` change après init : re-création de session — cas marginal,
  KITT le fixe une fois au constructeur.)
- **`initialize()`** : idempotent (`if (_initialized) return`). Vérifie l'existence
  du fichier `modelPath` → `ModelNotAvailable` sinon. Spawn isolate, `loadModel`
  avec `ModelParams(contextSize: 4096, gpuLayers: maxGpuLayers, numberOfThreads: 4,
  numberOfThreadsBatch: 4, batchSize: 512, microBatchSize: 256)`, crée la session
  persistante avec la persona. Erreur d'init isolate → propagée (`StateError`).
- **`generateChat(prompt, {toolContext})`** : si `toolContext != null` →
  reformulation one-shot (prompt « reformule le résultat… », session éphémère) ;
  sinon → session persistante. Retourne le texte complet (trim).
- **`generateChatStream(prompt, {toolContext})`** : si `toolContext != null` → yield
  la reformulation puis return ; sinon → stream des tokens via `_TokenChunk` de la
  session persistante.
- **`GenerationParams` chat** (de la réf) : `maxTokens: 150, temp: 0.4, topK: 30,
  topP: 0.85, penalty: 1.5`. Reformulation : `maxTokens: 80, temp: 0.3`. Ajustables.
- **`dispose()`** : `_isolate.dispose()` (envoie `_DisposeRequest`, kill isolate).

> Note API : les symboles llamadart (`LlamaEngine`, `LlamaBackend`, `ChatSession`,
> `ModelParams`, `GenerationParams`, `LlamaTextContent`, `session.create(...)` →
> `chunk.choices.first.delta.content`) viennent de la réf (~0.6.9). À vérifier/aligner
> sur la version résolue lors de l'implémentation. Pas de `UserMemory`, pas de
> `tool_definitions`, pas de `ConversationTurn`/historique (hors périmètre).

### 4.3 ModelManager — support LLM (`model_catalog.dart` + `model_manager.dart`)

`model_catalog.dart` : ajouter
```dart
const String llmDirName = 'llm';
const String llmFileName = 'croissantllmchat-v0.1.Q4_K_M.gguf';
const String llmUrl =
    'https://huggingface.co/croissantllm/CroissantLLMChat-v0.1-GGUF/resolve/main/croissantllmchat-v0.1.Q4_K_M.gguf';
```
(et étendre `ModelStatus` avec un champ **requis** `llmReady`, `allReady` incluant
le LLM. ⚠️ Cela touche le code existant : `getStatus()` doit fournir `llmReady`, et
le test existant `ModelStatus.allReady` de `model_manager_test.dart` — qui construit
`const ModelStatus(sttReady: true, ttsReady: true)` — est mis à jour pour passer les
trois champs.)

`model_manager.dart` : ajouter
- `String get llmModelPath => '$_modelsDir/$llmFileName';`
- `bool get isLlmModelAvailable => File(llmModelPath).existsSync();`
- `getStatus()` renvoie aussi `llmReady`.
- `Future<void> downloadLlmModel({required void Function(double) onProgress})` :
  porté de Tachikoma — **chunks parallèles + reprise** (probe `Range`, `.partN`,
  assemblage `.tmp` → `rename`, vérif de taille) avec **repli mono-flux** si le
  serveur ne supporte pas `Range`. Skip si déjà présent et non vide. Utilise le
  `_client` injecté.

### 4.4 Providers (`lib/application/providers.dart`)

En mode `real`, le faisceau `adaptersProvider` (qui attend déjà
`modelManagerProvider`) construit `llm: LlamaCroissantLlm(mm.llmModelPath)` au lieu
de `MockLlm()`. Mode `mock` inchangé.

## 5. Flux de données (mode `real`)

```
mic ─►RecordAudioIn─►SherpaStt─►ContextBuilder(persona+historique)
        ─► LlamaCroissantLlm.generateChatStream(prompt)  [persona = system]
        ─tokens─► SherpaTts.synthesize ─► JustAudioOut ─► audio
```
Le LLM est désormais réel ; tout le pipeline bout-en-bout est non-mock (sauf
wake-word/BT, hors périmètre).

## 6. Gestion d'erreurs

- **GGUF absent** : `initialize()` lève `ModelNotAvailable(modelPath)` — pas de
  fallback silencieux. `isLlmModelAvailable` permet de gater avant de construire le
  pipeline réel.
- **Échec d'init/inférence isolate** : `_LlmResponse.error` → `StateError` remonté
  (pas avalé). L'isolate est tué proprement à `dispose()`.
- **Réponse vide** : `CompanionPipeline` bascule déjà `firstToken` pour clore le tour.
- **Téléchargement** : retries + `.tmp`/`.partN` → `rename` atomique + vérif de taille
  (échec final remonté).

## 7. Tests (logique pure ; llamadart natif non exécutable sur l'hôte)

`flutter test` doit passer sans device/natif/modèle. Cibles :
- **`ModelManager` LLM** : `llmModelPath`, `isLlmModelAvailable` (fichier présent/absent
  dans un dossier temp), `getStatus().llmReady`. `downloadLlmModel` : chemin
  **skip-si-présent** (MockClient qui throw si appelé) et **fallback mono-flux**
  (MockClient renvoie 200 sans `Range` → écrit le fichier). Le chemin
  **chunks-parallèles/Range** (206 + `content-range`) est **non testé unitairement**
  (dur à mocker) → validé device/CI ; ce périmètre est **journalisé** dans le spec.
- **`MockLlm.initialize()`** no-op → la suite existante (`companion_pipeline_test`,
  `providers_test`, etc.) reste verte.
- **Pipeline** : un test que `CompanionPipeline.initialize()` appelle bien
  `llm.initialize()` (mock-espion comptant l'appel), pour verrouiller la répercussion L5.
- **Adapter `LlamaCroissantLlm`** = glue analyze-only (isolate + natif) ; pas de test
  unitaire. Compile + conforme `LlmPort` via `flutter analyze`. Inférence réelle :
  device + build APK CI.

## 8. Hors périmètre (reportés)

- **Tool calling / classification / optimisation de requête** (classify,
  generateToolCall, optimizeSearchQuery) + graphe d'agents (`dart_agent_graph`).
- **Historique multi-tours côté adapter** (le `ContextBuilder`/`ConversationManager`
  du domaine gère déjà la fenêtre ; l'adapter s'appuie sur la session persistante
  llamadart + le prompt assemblé).
- **Mémoire utilisateur** (`UserMemory`/SQLite), **résumé glissant**, **abstention**.
- **Tuning de la persona** (texte de `kitt_fr.md`, curseur « in-série » / D4) — lot
  d'asset séparé.
- **Wake-word**, **TTS streaming par phrase**, **routage Bluetooth/ducking**.

## 9. Critères d'acceptation

1. `flutter pub get` résout `llamadart` (`^0.6.9`).
2. `flutter analyze` : 0 issue (adapter llamadart compile et implémente `LlmPort`).
3. `flutter test` : tout vert, dont les nouveaux tests ModelManager-LLM + le test
   d'appel de `llm.initialize()` par le pipeline, **sans** device/natif/modèle.
4. `KITT_ADAPTERS=mock` (défaut) : comportement inchangé (MockLlm a un `initialize()`
   no-op ; suite existante verte).
5. `KITT_ADAPTERS=real` : compile ; le faisceau câble `LlamaCroissantLlm(mm.llmModelPath)`
   ; sur device avec le GGUF présent, conversation FR dans le personnage (validé
   device/CI, hors test unitaire).
6. Aucun poids de modèle (`*.gguf`) committé.
7. `LlmPort.initialize()` ajouté et répercuté (MockLlm + pipeline) sans régression.
