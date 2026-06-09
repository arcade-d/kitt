---
id: 01ktpzay9jv23bt10axzd86h5s
title: Kitt
status: draft
created_at: 2026-06-09T19:56:46.258760Z
---

# Projet KITT — Debrief technique & handoff

> Compagnon vocal local inspiré de K2000, app téléphone (Flutter), réutilisant le pipeline vocal de **Tachikoma**.
> Document de référence pour les sessions Claude Code. Dernière mise à jour : 2026-06-09.

---

## 0. Statut des sources

Le dépôt `delfour-co/tachikoma` a été **lu** (branche `claude/kitt-tachikoma-integration-damjnt`). Les marqueurs `‹À CONFIRMER›` de la §6 ont été remplacés par les vrais noms/API/chemins, ou marqués **« absent du repo »** quand la brique n'existe pas. Toute affirmation technique de ce document est ancrée à un fichier réel de Tachikoma (chemin + ligne). Voir l'inventaire détaillé `TACHIKOMA-INVENTORY.md`.

**Verdict de nature** : Tachikoma est une **app Flutter/Dart mono-package, ciblée Android**. Pas de Rust, pas de `Cargo.toml`, pas de FFI maison. Le code réutilisable vit dans `lib/services/**`. Les briques lourdes (LLM, STT/TTS) sont des packages pub.dev embarquant leurs binaires natifs.

---

## 1. Vision

Un compagnon vocal embarqué, à la personnalité de KITT, qui tourne **entièrement en local** sur le téléphone et dialogue à la voix. Pas un assistant transactionnel : un **co-pilote qui a un avis**, anticipe, commente, et tient une vraie conversation suivie. Le son sort vers les enceintes de la voiture en Bluetooth ; le téléphone est posé sur un support.

Différenciateur produit : la **persona** (ton posé, compétent, légèrement supérieur, loyal, humour pince-sans-rire) + la **continuité conversationnelle** (il se souvient de l'échange en cours et du contexte récent), le tout **privé et offline**.

---

## 2. Décisions actées (journal)

| # | Décision | Raison |
|---|----------|--------|
| D1 | **App téléphone**, pas Android Auto | Android Auto interdit le rendu custom (UI templatée), pas d'assistant vocal tiers, catégories restreintes. L'app téléphone libère l'UI (Flame) et le pipeline vocal. |
| D2 | Son vers la voiture **via Bluetooth** | Conserve l'usage « KITT me parle en conduisant » sans être une app Android Auto. |
| D3 | Cerveau **local on-device** | Offline, privé ; cohérent avec Tachikoma. |
| D4 | Persona **inspirée, non décalquée** | KITT/Knight Rider = IP Universal ; voix d'origine = acteur réel (William Daniels). Reproduire fidèlement le personnage/la voix pour une app **publiée** est un risque IP/voix. On garde le *caractère*, pas la copie. (Pas un avis juridique.) |
| D5 | Langue **français par défaut**, bilingue optionnel | Usage quotidien + cohérent avec CroissantLLM. |
| D6 | Activation par **wake-word « KITT » → écoute (STT)** | Flux wake-word classique : mot-clé → capture voix → STT. Bouton « maintenir pour parler » en repli. |
| D7 | UI : **modulateur vocal + scanner rouge** d'abord, cockpit complet plus tard | MVP visuel ; pass CRT/80s à venir. |

**Ouvert / à trancher** : voix de KITT (synthèse « à la KITT » vs voix clonée — possiblement *ta propre voix* pour contourner le souci IP) ; wake-word engine (Porcupine vs openWakeWord) ; cible Android min ; on-device vs hybride pour les requêtes lourdes.

> ⚠️ **Note réalité Tachikoma sur D6** : Tachikoma n'a **aucun wake-word** ; il déclenche par bouton (`VoicePipeline.startListening()`, `lib/services/voice_pipeline.dart:141`). Le wake-word « KITT » est à écrire intégralement côté KITT.

---

## 3. Architecture d'ensemble

```
┌──────────────────────────── App Flutter (téléphone) ────────────────────────────┐
│                                                                                  │
│  UI (Flutter + Flame)            Domaine (Dart, hexagonal/DDD)                    │
│  ├─ Écran companion              ├─ ConversationManager  (état + historique)     │
│  │   ├─ Modulateur vocal         ├─ ContextBuilder       (fenêtre + mémoire)     │
│  │   └─ Scanner K2000            ├─ Persona              (system prompt + règles)│
│  └─ États visuels                └─ DialoguePolicy       (abstention, barge-in)  │
│         ▲                                  │                                     │
│         │ events                           │ ports                               │
│  ┌──────┴───────────────── Pipeline vocal (ports & adapters) ─────────────────┐  │
│  │  WakeWord ──► STT ──► [ContextBuilder ─► LLM] ──► TTS ──► AudioOut(BT)      │  │
│  │  (à écrire)  (sherpa) (Croissant+Qwen / llamadart) (sherpa VITS)           │  │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                         ▲ réutilise les libs Tachikoma (§6)                       │
└──────────────────────────────────────────────────────────────────────────────────┘
```

Principe : chaque étage du pipeline est un **port** (interface Dart) avec un **adapter** d'implémentation. Ça permet de mocker en test, de swapper un moteur, et de réutiliser tel quel ce que Tachikoma expose déjà.

---

## 4. Le pipeline companion (étage par étage)

> Réécrit sur le code réel de Tachikoma. Chemins = fichiers Tachikoma.

### 4.1 Wake-word (KWS — Keyword Spotting)
- **Rôle** : détecter « KITT » en continu, faible coût CPU/batterie, sans réseau.
- **Réalité Tachikoma** : **absent du repo.** Aucun moteur KWS (ni Porcupine, ni `KeywordSpotter` de `sherpa_onnx`). Activation manuelle uniquement (`VoicePipeline.startListening()`, `lib/services/voice_pipeline.dart:141`).
- **Options à intégrer côté KITT** :
  - **Porcupine (Picovoice)** — mot-clé custom « KITT », SDK Flutter, léger, précis. Licence gratuite limitée.
  - **openWakeWord** — libre, mot-clé entraînable, intégration artisanale (ONNX + boucle audio).
  - **`sherpa_onnx KeywordSpotter`** — déjà dans la stack Tachikoma (`sherpa_onnx` 1.12.33), à privilégier pour homogénéité.
- **Décision** : à trancher (D-open). Recommandation : prototyper Porcupine (rapidité), cible libre = `sherpa_onnx KeywordSpotter` ou openWakeWord.
- **Comportement** : `idle → (KITT détecté) → listening`. Repli manuel : bouton maintenir (déjà couvert par `startListening`/`stopListening`).

### 4.2 STT — Speech To Text
- **Moteur (réel)** : `SttService` (`lib/services/stt_service.dart:5`) → `sherpa_onnx` 1.12.33, `OnlineRecognizer` + `OnlineTransducerModelConfig` (encoder/decoder/joiner, `modelType: 'zipformer2'`). Whisper **non utilisé** ; c'est un **zipformer transducer streaming**.
- **API publique exacte** : `initialize(String modelDir)`, `acceptWaveform(List<double> samples, int sampleRate)`, `getResult() → String`, `isEndpoint() → bool`, `reset()`, `dispose()`.
- **Streaming** : **oui** (recognizer *online*, décodage par buffers d'≈1,5 s — `voice_pipeline.dart:33,168-172`).
- **Sortie** : **texte seul.** ⚠️ **Pas de score de confiance, pas de langue détectée** exposés (`stt_service.dart:46-50`). → La politique d'abstention §5.5 basée sur `sttConfidence` n'a **pas** de donnée source côté Tachikoma ; à recoder.
- **VAD** : pas de module VAD dédié. Endpointing via les règles sherpa (`enableEndpoint: true`, `rule1MinTrailingSilence: 2.4`, `rule2MinTrailingSilence: 1.2`, `rule3MinUtteranceLength: 20` — `stt_service.dart:26-29`), lues via `_stt.isEndpoint()`.
- **Modèle attendu** : `sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06` (FR), fichiers `encoder.onnx`/`decoder.onnx`/`joiner.onnx`/`tokens.txt`, dépôt HF `csukuangfj/...` (`lib/services/model_manager.dart:39-70`). Format ONNX. Licence non documentée dans le repo.

### 4.3 LLM — le cerveau + la persona
- **Moteur (réel)** : `DualLlmService` (`lib/services/dual_llm_service.dart:186`) via **`llamadart` 0.6.9** (binding llama.cpp ; `LlamaEngine`, `LlamaBackend`, `ChatSession`, `ModelParams`, `GenerationParams`, `LlamaTextContent`). **Architecture double modèle**, chacun dans son propre `Isolate` :
  - **CroissantLLM** = conversation (session persistante, system prompt stable).
  - **Qwen2.5-1.5B-Instruct** = classification TOOL/CHAT, génération de tool call, reformulation, optimisation de requête.
- **API publique exacte** : `generateChat(String, {String? toolContext}) → Future<String>`, `generateChatStream(String, {String? toolContext}) → Stream<String>`, `classify(String) → Future<RouteDecision>`, `generateToolCall(String) → Future<ParsedToolCall?>`, `optimizeSearchQuery(String) → Future<String>`, `addToHistory(ConversationTurn)`, `clearHistory()`.
- **Entrée** : pour Qwen, prompt = `_historyContext()` + message ; pour Croissant, session persistante + mémoire utilisateur (`userMemory.toPromptContext()`). Le `ContextBuilder` KITT §5 est à construire **par-dessus** (Tachikoma n'a pas d'assemblage de fenêtre/résumé sophistiqué).
- **Sortie** : streaming token par token (`ChatSession.create()` → `_TokenChunk` → `generateChatStream`, `dual_llm_service.dart:138-150,375-401`).
- **Persona** : injectée en system prompt **stable** mais en **constante codée « Tachikoma »** (`_croissantSystemPrompt`, `dual_llm_service.dart:220-224`). À externaliser/réécrire pour KITT.
- **Modèles attendus** (GGUF, **Q4_K_M**, `contextSize: 2048` — `lib/services/llm_models.dart`, `dual_llm_service.dart:254-270`) :
  - `croissantllmchat-v0.1.Q4_K_M.gguf` (HF `croissantllm/CroissantLLMChat-v0.1-GGUF`, ~872 MB) ou variante `croissant-1.3b-tools.gguf` (832 MB, local, `url: ''`).
  - `qwen2.5-1.5b-instruct-q4_k_m.gguf` (HF `Qwen/Qwen2.5-1.5B-Instruct-GGUF`, ~1.0 GB).
  - Licences : non documentées dans le repo (amont : Croissant = MIT, Qwen2.5 = Apache-2.0).

### 4.4 TTS — Text To Speech (la voix de KITT)
- **Moteur (réel)** : `TtsService` (`lib/services/tts_service.dart:5`) → `sherpa_onnx` `OfflineTts` + `OfflineTtsVitsModelConfig`. **VITS/Piper**, pas Coqui/XTTS (XTTS **absent du repo**).
- **API publique exacte** : `initialize(String modelDir)`, `synthesize(String text, {int speakerId = 0, double speed = 1.0}) → Float32List?`, `get sampleRate → int`, `dispose()`.
- **Streaming** : **non.** `synthesize()` renvoie tout l'audio d'un bloc (`tts_service.dart:29-45`). Pas de découpage par phrase → le « parler dès la première phrase » de KITT est **à écrire**.
- **Voix** : speaker 0, voix par défaut. Pas de clonage. Décision D4 toujours ouverte ; pour la voix clonée (XTTS) il faudra une brique **hors Tachikoma**.
- **Barge-in** : interruption partielle seulement — `VoicePipeline.cancel()` stoppe la lecture (`voice_pipeline.dart:385-390`) mais rien n'écoute le micro pendant l'état `speaking`. À compléter.
- **Modèle attendu** : `vits-piper-fr_FR-siwis-medium` (FR), `model.onnx` + `tokens.txt` + `espeak-ng-data/` (HF `csukuangfj/vits-piper-fr_FR-siwis-medium`, `model_manager.dart:45-88`).

### 4.5 Audio out
- **Réalité Tachikoma** : `AudioPlayerService` (`lib/services/audio_player_service.dart:4`) → `just_audio` 0.10.5. `playPcm(Float32List samples, int sampleRate)` enveloppe le PCM en **WAV en mémoire** puis le joue ; `stop()`, `isPlaying`.
- **Capture** : `AudioRecorderService` (`audio_recorder_service.dart:5`) → `record` 6.2.0, `startStream(RecordConfig(encoder: pcm16bits, sampleRate: 16000, numChannels: 1, autoGain, echoCancel, noiseSuppress))`.
- ⚠️ **Bluetooth / focus audio / ducking** : **absent du repo.** `audio_session` est en dépendance mais **non utilisé** dans le code. Le routage BT vers l'autoradio, le ducking de la musique et la gestion du focus sont **à écrire côté KITT** (via `audio_session`, déjà disponible).

### 4.6 Budget de latence (cible indicative)
| Étage | Cible |
|------|-------|
| Wake-word → début écoute | < 300 ms |
| Fin de parole → texte STT | < 800 ms |
| LLM premier token | < 600 ms |
| Premier mot TTS audible | < 500 ms après premier token |
| **Ressenti total « j'ai fini de parler → KITT répond »** | **~1,5–2,5 s** |

Le streaming STT et LLM est présent dans Tachikoma ; le **streaming TTS par phrase n'existe pas** et sera le principal levier de latence restant à coder.

---

## 5. Conversation « normale » : gestion du contexte et de l'historique

C'est la partie demandée explicitement. Un LLM est **sans mémoire** entre appels : pour qu'une conversation soit naturelle, **on doit lui re-fournir l'historique pertinent à chaque tour**. Tout ça vit dans `ConversationManager` + `ContextBuilder`.

> **Ce que Tachikoma fournit déjà** (à réutiliser) : un historique court plafonné à 5 tours (`DualLlmService._history`, `dual_llm_service.dart:199-218`), une mémoire long terme KV (`UserMemory`), une session persistante côté CroissantLLM. **Ce qu'il ne fournit pas** : budget de tokens calculé, résumé glissant, abstention par confiance. Détails ci-dessous.

### 5.1 Structure des messages
On tient un **journal de tours** typé par rôle :

```dart
enum Role { system, user, assistant }

class Turn {
  final String id;          // ULID
  final Role role;
  final String content;
  final DateTime at;
  final double? sttConfidence; // ⚠️ non fourni par Tachikoma (STT sans confiance)
}
```

> Note : Tachikoma modélise un tour autrement — `ConversationTurn(userMessage, toolName?, toolResult?, response)` (`dual_llm_service.dart:165-184`). KITT garde son `Turn` riche ; l'adapter convertit. Le champ `sttConfidence` restera **null** tant qu'un STT à confiance n'est pas branché.

### 5.2 Assemblage du prompt (ContextBuilder)
```
[system]   persona + règles
[summary]  résumé glissant des tours anciens (mémoire de travail)
[history]  les N derniers tours verbatim (fenêtre courte)
[user]     l'énoncé courant
```
- **À écrire côté KITT** : Tachikoma n'a pas de `ContextBuilder` complet. Il a `_historyContext()` (concat brute des 5 derniers tours, `dual_llm_service.dart:215-218`) + `UserMemory.toPromptContext()`. Le résumé glissant est **absent**.

### 5.3 Budget de tokens (context window management)
- `contextSize: 2048` côté Tachikoma (`dual_llm_service.dart:254-270`). **Aucune éviction calculée, aucun résumé** : seule limite = « 5 derniers tours » + contexte interne de la session llama. La logique de budget/éviction §5.3 est **à implémenter côté KITT**.

### 5.4 Mémoire au-delà de la session
- **Mémoire de travail** (résumé glissant) : **absente du repo**, à écrire.
- **Mémoire persistante** : **présente** via `UserMemory` (`lib/services/user_memory.dart`) — `Map<String,String>` de faits en `SharedPreferences`, injectés au prompt (`toPromptContext()`), alimentée par l'outil `save_memory` (`tool_exec_node.dart:72-85`). ⚠️ KV simple : **pas de dédup, pas de TTL, pas de SQLite** (KITT visait SQLite — à porter). Réutilisable tel quel comme premier `MemoryStore`.

### 5.5 Politique d'abstention
- **Réalité Tachikoma** : **pas d'abstention par score.** Le STT n'expose pas de confiance (donc pas de « fais répéter » fondé sur `sttConfidence`). Ce qui existe :
  - garde-fous de reformulation (résultat vide/trop long → renvoie le brut, `dual_llm_service.dart:419-423`) ;
  - gestion d'échec de tool call (« Echec: aucun outil reconnu », `voice_pipeline.dart:302-309`) ;
  - consigne prompt-level « Si tu ne sais pas, dis-le simplement » (`dual_llm_service.dart:224`).
- Le travail d'**abstention CroissantLLM** évoqué initialement est **absent du repo** : ‹À CONFIRMER : repris de Tachikoma ?› → **non, absent du repo.**
- **À écrire côté KITT** : seuil de confiance (nécessite d'abord un STT à confiance), réponse « fais répéter », périmètre hors-sujet en restant dans le personnage.

### 5.6 Barge-in / interruption
- Tachikoma : interruption **partielle** (`cancel()` coupe la lecture) mais **pas d'écoute pendant `speaking`**. Le barge-in complet (wake-word/VAD actif pendant la TTS) est **à écrire côté KITT**.

### 5.7 Machine d'états (canonique)
```
idle ──(wake-word | bouton)──► listening
listening ──(silence/fin)──► thinking
thinking ──(1er token)──► responding (TTS)
responding ──(fin)──► idle
responding ──(barge-in)──► listening
listening ──(STT faible)──► clarifying ──► listening
```
> Tachikoma expose `PipelineState { idle, listening, processing, speaking }` (`voice_pipeline.dart:14`) — proche mais sans `clarifying` ni transition `barge-in`. La version complète est à porter côté KITT.

### 5.8 Liens UI
Le proto actuel mappe déjà : `listening` = modulateur piloté par le micro réel (`audioLevelStream` de Tachikoma fournit le niveau RMS) ; `responding` = enveloppe de parole ; scanner accéléré hors veille. La machine d'états ci-dessus est la version « complète » à porter en Flame.

---

## 6. Réutilisation de Tachikoma — plan d'intégration & checklist

> **Repo lu.** Marqueurs levés ci-dessous.

### 6.1 Inventaire (résolu)
- [x] Langage et structure : **app Flutter/Dart mono-package, Android** ; pas de Rust/FFI (`pubspec.yaml`, `lib/services/**`).
- [x] Lib **STT** : `SttService` → `sherpa_onnx` 1.12.33 (`OnlineRecognizer` zipformer), **streaming** (`lib/services/stt_service.dart`).
- [x] Lib **LLM** : `DualLlmService` → **`llamadart` 0.6.9** (CroissantLLM + Qwen2.5-1.5B, GGUF Q4_K_M), **streaming** (`lib/services/dual_llm_service.dart`).
- [x] Lib **TTS** : `TtsService` → `sherpa_onnx` `OfflineTts` VITS/Piper FR, **non streaming** (`lib/services/tts_service.dart`).
- [x] **VAD / capture audio** : pas de VAD dédié (endpointing sherpa) ; capture = `record` 6.2.0 (`audio_recorder_service.dart`).
- [x] Couche **orchestration** : **`dart_agent_graph`** (git privé `delfour-co/dart-agent-graph`, `pubspec.yaml:52-55` ref `59db367`) ; graphe construit dans `lib/services/dual_llm_graph.dart`.
- [x] Mécanismes **conversation** : historique 5 tours (`DualLlmService._history`) + `UserMemory` (KV) + session persistante Croissant. **Résumé/mémoire de travail = absent.** **Abstention par confiance = absent.**
- [x] Gestion des **modèles** : `ModelManager` (`lib/services/model_manager.dart`) — download HF par chunks + reprise, chemins, statut. Catalogue dans `llm_models.dart`.
- [x] Format de **config** : `SharedPreferences` (flags TTS/debug, mémoire) ; pas de fichier de config structuré. Points d'extension = les `typedef` injectés dans le graphe (`Classifier`, `ToolCallGenerator`, `ChatGenerator`, `ChatStreamGenerator`).

### 6.2 Stratégie de réutilisation (tranchée)
- **Verdict : dépendance Dart (git/path), PAS de FFI.** `flutter_rust_bridge` ‹À CONFIRMER› → **absent du repo / sans objet** (aucune crate Rust).
- Tachikoma n'est **pas** un monorepo de packages publiables (`publish_to: 'none'`, code dans `lib/services/**` de l'app).
- **Recommandé** : extraire un package `tachikoma_voice` (`lib/services/**` sauf UI et couplage Android `MethodChannel('tachikoma/tools')`), que KITT consomme en git dep, puis brancher chaque service comme **adapter** des ports KITT.
- **Rapide (dette)** : git dep directe sur Tachikoma + import des fichiers `lib/services/**` tels quels (traîne `d4_dark_ds` et le couplage outils Android).
- Pré-requis : reverrouiller `dart_agent_graph` (lock incohérent : `pubspec.yaml` = git `59db367`, `pubspec.lock:125-131` = path local `0.1.0`) ; externaliser la persona ; découpler le canal natif `tachikoma/tools`.

Détail complet du mapping ports → symboles et de la stratégie : voir `TACHIKOMA-INVENTORY.md`.

### 6.3 « Ce qu'on a mis en place dans Tachikoma pour améliorer la conversation » (résolu)
- Orchestration **graphe d'agents** : **présent** — `dart_agent_graph` + `buildDualLlmGraph` (route→classify→filler→tool_call→tool_exec→chat), exécution `streamMulti` avec `StreamMode.{state,custom,debug}` (`lib/services/dual_llm_graph.dart`, `voice_pipeline.dart:232-343`).
- **Routage hybride** patterns + LLM : `RouteNode` (mots-clés FR, `nodes/route_node.dart`) puis `ClassifyNode` (Qwen) si ambigu.
- **Phrases d'attente (filler)** pendant l'exécution outil : `FillerNode` (« Un instant… ») jouées en TTS dès la détection — vrai gain de latence perçue (`nodes/filler_node.dart`, `voice_pipeline.dart:242-258`).
- **Mémoire utilisateur** : `UserMemory` + auto-extraction de faits + outil `save_memory`.
- **Reformulation** des résultats d'outils en réponse FR courte (Qwen, `dual_llm_service.dart:403-424`).
- Abstention CroissantLLM ‹À CONFIRMER› → **absente du repo.**
- Évaluation automatisée de réponse ‹À CONFIRMER› → **absente du repo** ; il existe seulement une **évaluation humaine** (👍/👎 + commentaire, `JournalService`/`ConversationStore`).

---

## 7. Pipeline CI

Cible : **GitHub Actions**. Tachikoma étant 100 % Dart/Flutter, le job `rust` du squelette initial est **sans objet** — on garde `flutter` (+ `dart-libs` si on extrait `tachikoma_voice`).

```yaml
# .github/workflows/ci.yml
name: ci
on:
  push: { branches: [main] }
  pull_request: {}

jobs:
  flutter:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage
      - run: flutter build apk --debug   # build de fumée

  dart-libs:        # si package tachikoma_voice extrait
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart analyze
      - run: dart test
```

À prévoir : ne pas committer les poids (les récupérer en CI / mocker les ports STT/LLM/TTS) ; tests d'intégration pipeline avec adapters mock ; lint persona (system prompt non vide). NB : Tachikoma teste déjà ses nodes/parsers (`test/services/**`), modèle à suivre.

---

## 8. Stack & conventions (préférences projet)

- **Mobile** : Flutter / Dart ; rendu animé : **Flame**.
- **Archi** : **hexagonal / DDD**, ports & adapters ; **CQRS** où pertinent.
- **État** : **Riverpod**.
- **Identifiants** : **ULID**.
- **Inférence locale (confirmé Tachikoma)** : **`llamadart` 0.6.9** (CroissantLLM + Qwen2.5-1.5B, GGUF Q4_K_M), **`sherpa_onnx` 1.12.33** (STT zipformer FR streaming + TTS VITS/Piper FR). **Whisper et Coqui/XTTS ne sont PAS utilisés par Tachikoma.**
- **Orchestration** : `dart_agent_graph` (git privé `delfour-co/dart-agent-graph`).
- **Design system** : `d4_dark_ds` (git privé `delfour-co/d4-dark-ds`, v0.1.1).
- **Persistance Tachikoma** : `SharedPreferences` (mémoire/flags) + JSON (`ConversationStore`). SQLite visé par KITT = **à ajouter** (absent de Tachikoma).
- **Handoff** : ce doc + `TACHIKOMA-INVENTORY.md` + un `CLAUDE.md` par session.

### Arborescence proposée (KITT)
```
kitt/
├─ lib/
│  ├─ domain/         # Turn, ConversationManager, ContextBuilder, Persona, DialoguePolicy
│  ├─ application/    # use cases (orchestration du pipeline, machine d'états)
│  ├─ ports/          # interfaces: WakeWord, Stt, Llm, Tts, AudioOut, MemoryStore
│  ├─ adapters/       # implémentations (Tachikoma, Porcupine, etc.)
│  ├─ ui/             # écran companion (Flame), états visuels
│  └─ main.dart
├─ test/
├─ assets/persona/
└─ .github/workflows/ci.yml
```

---

## 9. Roadmap

1. **Persona** — system prompt + règles + exemples (externaliser la constante « Tachikoma »).
2. **Squelette domaine** — `Turn`, `ConversationManager`, `ContextBuilder` (fenêtre + résumé **à écrire**), machine d'états, **ports** vides + adapters mock.
3. **Intégration Tachikoma** — extraire `tachikoma_voice`, brancher STT/LLM/TTS réels comme adapters.
4. **Wake-word** — Porcupine ou `sherpa_onnx KeywordSpotter` « KITT », repli bouton (**à écrire**, absent de Tachikoma).
5. **Boucle bout-en-bout** — wake → STT → contexte → LLM → TTS → BT, en streaming (+ **TTS streaming par phrase** et **routage BT/ducking** à écrire).
6. **CI** — workflow ci-dessus, tests d'intégration mock.
7. **UI Flame** — porter le proto, pass CRT/80s.
8. **Mémoire long terme** (SQLite + dédup/TTL) + barge-in raffiné + abstention (nécessite STT à confiance).

---

## 10. Questions ouvertes

- Voix de KITT : synthèse VITS « à la KITT », **ta voix clonée** (brique hors Tachikoma), ou décalque (perso only) ?
- Wake-word : Porcupine vs openWakeWord vs `sherpa_onnx KeywordSpotter` ?
- 100 % offline strict, ou hybride ?
- Android minimum / contraintes RAM (≈ 2,7 Go de modèles : STT + 2 LLM + TTS) ?
- STT : garder le zipformer FR (sans confiance) ou passer à un moteur exposant un score (pour l'abstention) ?
- Mémoire long terme (SQLite) dans le MVP ou plus tard ?
- ~~Statut exact des libs Tachikoma~~ → **résolu** (cf. §4, §6, `TACHIKOMA-INVENTORY.md`). N'est plus bloquant.