---
title: Adapters réels — Sherpa (STT/TTS) + Audio + ModelManager
status: approved
created_at: 2026-06-10
références: docs/DEBRIEF.md (§4, §6), CLAUDE.md
---

# Spec — Adapters réels Sherpa + Audio + ModelManager (KITT)

> Remplacer les adapters **mock** STT/TTS/Audio par des implémentations **réelles**
> portées de Tachikoma, et fournir les modèles via un `ModelManager` porté et
> rendu testable. L'adapter **LLM** (llamadart/CroissantLLM) fait l'objet d'un
> spec **suivant** — il n'est pas couvert ici.

## 1. Contexte & objectif

KITT a un squelette hexagonal complet (`domain` / `application` / `ports` /
`adapters`) câblé sur des **mocks déterministes**. Les ports STT/LLM/TTS/Audio
ont été dessinés alignés 1:1 sur l'API des services Tachikoma. Ce spec branche
les **vrais moteurs** derrière trois de ces ports (STT, TTS, AudioIn, AudioOut)
sans toucher au domaine, conformément à la stratégie ports & adapters du débrief.

**Objectif** : à l'issue de ce spec, KITT peut — sur un device Android avec les
modèles présents — transcrire (sherpa zipformer FR), synthétiser (sherpa VITS
Piper FR) et jouer de l'audio réel, le LLM restant mocké. La logique pure est
couverte par des tests ; l'inférence native se valide sur device / build APK CI.

## 2. Décisions actées (cette session)

| # | Décision | Raison |
|---|----------|--------|
| A1 | **Adapters écrits dans KITT** (`lib/adapters/{sherpa,audio}`), dépendant des **mêmes packages pub.dev** que Tachikoma. Pas de package `tachikoma_voice`, pas de git dep sur Tachikoma. | Les wrappers sont fins (50–70 lignes) ; l'extraction d'un package partagé (relock `dart_agent_graph`, découplage canal natif, externalisation persona) est un coût non justifié à ce stade. |
| A2 | **LLM = CroissantLLM via llamadart** (plan d'origine du débrief), **divergence assumée** vis-à-vis de Tachikoma qui a migré vers Gemma 4 (`flutter_gemma`). | FR natif (CroissantLLM ★★★★★ vs Gemma ★★★★), 100 % GGUF offline. Code de référence récupérable au commit `0840801^` de Tachikoma. **Hors périmètre de ce spec** (spec LLM suivant). |
| A3 | **Périmètre de ce spec** : Sherpa (STT+TTS) + Audio (in/out) + `ModelManager`. LLM reporté au spec suivant. | Dé-risque la plomberie (deps natives, `modelDir`, bascule, build APK CI) avant le morceau lourd (isolate llamadart). |
| A4 | **`ModelManager` complet porté** (catalogue HF + téléchargement repris + résolution de chemins), rendu **injectable** (`baseDir` + `http.Client`). | KITT n'a aucun ModelManager. L'injection rend la logique catalogue/chemins/parsing testable sans télécharger ni dépendre du device. |
| A5 | **Bascule mock ↔ réel** par `--dart-define=KITT_ADAPTERS=real|mock`, défaut **mock**. | Tests et CI restent sur mock (pas de natif ni de modèles ~2,7 Go en CI). La suite existante continue de passer. |

> **Note réalité Tachikoma** : le LLM décrit par le débrief (§4.3 : `DualLlmService`
> llamadart + CroissantLLM + Qwen) n'est **plus** le code vivant de Tachikoma
> (branche `feat/gemma4-migration`, commit `0840801 refactor(llm): rewrite
> LlmService on top of flutter_gemma`). STT et TTS (`sherpa_onnx`) sont
> **inchangés** et directement portables. Cf. tâche de réconciliation §9.

## 3. Architecture — ports → adapters

Aucun changement de domaine. Les ports STT/TTS/AudioIn/AudioOut existants sont
conservés tels quels. Câblage actuel (tout mock) → câblage cible (bascule) :

```
ports/                    adapters/                       paquet pub.dev
  SttPort        ───►  sherpa/sherpa_stt.dart       ──►  sherpa_onnx
  TtsPort        ───►  sherpa/sherpa_tts.dart       ──►  sherpa_onnx
  AudioInPort    ───►  audio/record_audio_in.dart   ──►  record
  AudioOutPort   ───►  audio/just_audio_out.dart    ──►  just_audio
  (modelDir)     ◄──  models/model_manager.dart     ──►  path_provider + http
  LlmPort        ───►  mock/mock_llm.dart  (inchangé ce spec)
```

`ModelManager` n'est **pas** un port du domaine : c'est un service
d'infrastructure que les providers initialisent et dont les adapters Sherpa
reçoivent le `modelDir` résolu via leur constructeur.

## 4. Composants

### 4.1 `ModelManager` (`lib/adapters/models/model_manager.dart`)

Porté de `tachikoma/lib/services/model_manager.dart`, **épuré** (pas les flags
`tts_enabled`/`debug_enabled` qui sont des prefs applicatives Tachikoma) et
**rendu injectable**.

```dart
class ModelManager {
  ModelManager({
    Future<String> Function()? baseDirProvider, // défaut: getApplicationDocumentsDirectory()
    http.Client? client,                         // défaut: http.Client()
  });

  Future<void> initialize();         // résout baseDir, crée models/, nettoie *.tmp
  String get modelsDir;
  String get sttModelDir;            // $modelsDir/stt
  String get ttsModelDir;            // $modelsDir/tts
  bool get isSttModelAvailable;      // encoder.onnx + tokens.txt
  bool get isTtsModelAvailable;      // model.onnx + tokens.txt + espeak-ng-data/{fr_dict,phontab}
  ModelStatus getStatus();
  Future<void> downloadModel(ModelInfo model, {required void Function(double) onProgress});
}
```

- **Catalogue** (constantes statiques `sttModel`, `ttsModel`) : repris à l'identique.
  - STT : `csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06` → `encoder/decoder/joiner.onnx` + `tokens.txt`.
  - TTS : `csukuangfj/vits-piper-fr_FR-siwis-medium` → `fr_FR-siwis-medium.onnx` (→ `model.onnx`) + `tokens.txt` + `espeak-ng-data/` (dossier HF récursif).
- **Téléchargement** : fichiers explicites (skip si présent et non vide, écriture `.tmp` puis `rename`) + dossier HF récursif via l'API `tree/main`. Retries (3, backoff). Value types `ModelFile` / `ModelInfo` / `ModelStatus` portés.
- **Hors périmètre** : catalogue LLM + `downloadLlmModel` (chunks parallèles/reprise) → spec LLM. La structure du catalogue laisse la place pour l'ajouter.

### 4.2 `SherpaStt` (`lib/adapters/sherpa/sherpa_stt.dart`) — `implements SttPort`

Porté de `tachikoma/lib/services/stt_service.dart` (code **actuel**, inchangé).

- Constructeur : `SherpaStt(this.modelDir)`.
- `initialize()` : construit `OnlineRecognizerConfig` (transducer encoder/decoder/joiner, `modelType: 'zipformer2'`, `numThreads: 2`, endpointing `enableEndpoint:true`, `rule1=2.4`, `rule2=1.2`, `rule3=20`) depuis `modelDir`, crée recognizer + stream. **Lève une erreur typée si les fichiers du modèle sont absents.**
- `acceptWaveform`, `isEndpoint`, `reset`, `dispose` : 1:1.
- `getResult()` : `recognizer.getResult(stream).text.trim()` enveloppé en **`SttResult(text: …, confidence: null, isFinal: …)`** (le zipformer n'expose pas de confiance — cf. débrief §4.2). Mapping `String → SttResult` = **logique pure testable**.

### 4.3 `SherpaTts` (`lib/adapters/sherpa/sherpa_tts.dart`) — `implements TtsPort`

Porté de `tachikoma/lib/services/tts_service.dart` (code **actuel**).

- Constructeur : `SherpaTts(this.modelDir)`.
- `initialize()` : `OfflineTtsConfig` VITS (`model.onnx`, `tokens.txt`, `dataDir: espeak-ng-data`, `numThreads: 2`). Erreur typée si modèle absent.
- `synthesize(text, {speakerId, speed})` : **nettoyage texte** via une fonction pure de niveau bibliothèque `sanitizeForEspeak(String) → String` (strip emojis/non-latin via la regex Tachikoma `[^\x00-\x7FÀ-ÿ.,!?;: \-]+`), `null` si texte vide après nettoyage ; sinon `tts.generate(...).samples`. Le wrapper sync de Tachikoma devient `Future<Float32List?>`. `sanitizeForEspeak` = **logique pure testable**.
- `sampleRate` : `tts?.sampleRate ?? 22050`.

### 4.4 `RecordAudioIn` (`lib/adapters/audio/record_audio_in.dart`) — `implements AudioInPort`

Porté de `tachikoma/lib/services/audio_recorder_service.dart`.

- `startStream({sampleRate = 16000})` : `recorder.startStream(RecordConfig(encoder: pcm16bits, sampleRate, numChannels:1, autoGain, echoCancel, noiseSuppress))`, convertit chaque chunk `Uint8List` (int16) → `List<double>` normalisé, émet sur le `Stream<List<double>>` retourné.
- `audioLevel` : `Stream<double>` du RMS calculé par chunk (alimente le modulateur UI).
- `stop()`.
- **Logique pure testable** (statics) : `int16BytesToFloat32` (gestion longueur impaire / alignement) et `calculateAudioLevel` (RMS borné [0,1]).
- Permission micro : `startStream` vérifie `recorder.hasPermission()` et **lève une erreur typée si refusée** (pas de stream vide silencieux). `permission_handler` reste en dépendance pour la demande explicite au bootstrap UI (hors périmètre).

### 4.5 `JustAudioOut` (`lib/adapters/audio/just_audio_out.dart`) — `implements AudioOutPort`

Porté de `tachikoma/lib/services/audio_player_service.dart`.

- `playPcm(Float32List samples, int sampleRate)` : encapsule le PCM Float32 en **WAV en mémoire** via une fonction pure de niveau bibliothèque `pcmFloat32ToWav(Float32List, int) → Uint8List` (int16 little-endian, en-tête RIFF 44 octets) servie via un `StreamAudioSource`, puis `player.play()`. Complète à la fin de lecture.
- `stop()`, `isPlaying`.
- **Logique pure testable** : `pcmFloat32ToWav` (octets d'en-tête RIFF/fmt/data corrects, conversion float→int16 clampée).

### 4.6 Câblage & bascule (`lib/application/providers.dart`)

- Nouveau `modelManagerProvider` (`FutureProvider<ModelManager>`) : crée + `initialize()`.
- Les providers `sttProvider` / `ttsProvider` / `audioInProvider` / `audioOutProvider` choisissent l'adapter selon
  `const String.fromEnvironment('KITT_ADAPTERS', defaultValue: 'mock')` :
  - `mock` (défaut) → adapters mock actuels (inchangé).
  - `real` → `SherpaStt(mm.sttModelDir)`, `SherpaTts(mm.ttsModelDir)`, `RecordAudioIn()`, `JustAudioOut()`.
- `llmProvider` reste `MockLlm()` dans **les deux** modes ce spec (config partielle-réelle valide).
- Les providers `real` dépendent de `modelManagerProvider.future` pour obtenir les chemins ; tant que les modèles ne sont pas présents, `initialize()` de l'adapter lève une erreur typée (gérée par le bootstrap UI — hors périmètre).

## 5. Flux de données (mode `real`, LLM mocké)

```
mic ─(record)─► RecordAudioIn ─List<double>/16k─► [CompanionPipeline.runTurn]
                                                     │ acceptWaveform / getResult
                                              SherpaStt ─SttResult(conf:null)─►
                                                     │ (domaine: contexte + MockLlm)
                                              MockLlm ─tokens─► texte
                                              SherpaTts.synthesize ─Float32List─►
                                              JustAudioOut.playPcm ─WAV─► HP / (BT plus tard)
```

> La **boucle de capture** continue (brancher `RecordAudioIn` → STT dans le
> pipeline) n'est **pas** câblée par ce spec : `runTurn` reçoit déjà des samples.
> L'adapter `AudioIn` est livré conforme au port ; son intégration au pipeline
> (et le routage BT) sont des pièces ultérieures.

## 6. Gestion d'erreurs

- **Modèle absent** : `initialize()` des adapters Sherpa lève une exception typée
  `ModelNotAvailable` (définie dans `adapters/models/`) citant le fichier manquant —
  pas de fallback silencieux. Le `ModelStatus` permet de tester la disponibilité
  avant de construire le pipeline réel.
- **Téléchargement** : retries (3, backoff) ; écriture `.tmp`/`.part` puis
  `rename` atomique ; vérification de taille pour le LLM (spec suivant). Une
  erreur réseau finale **remonte** (pas avalée).
- **Synthèse vide** (`synthesize` → `null`) : `CompanionPipeline` saute déjà la
  lecture audio (`if (audio != null)`). Comportement conservé.
- **Permission micro refusée** : `RecordAudioIn.startStream` lève une erreur
  explicite ; pas de stream silencieux vide.

## 7. Tests (logique pure, sans natif ni modèles)

`flutter test` doit passer **sans** device, natif, ni poids de modèles. Cibles :

- `RecordAudioIn` : `int16BytesToFloat32` (cas vide, longueur impaire, valeurs
  bornes ±32768) ; `calculateAudioLevel` (silence→0, plein→1, clamp).
- `JustAudioOut` : `_createWav` — magic `RIFF`/`WAVE`/`fmt `/`data`, tailles,
  `byteRate`/`blockAlign`, échantillons int16 clampés.
- `SherpaStt` : mapping `String → SttResult` (`confidence == null`, `text.trim()`,
  `isFinal`). *(Sans charger sherpa : tester la fonction de mapping isolée.)*
- `SherpaTts` : nettoyage texte espeak (emoji retiré, accents FR conservés,
  vide→`null`).
- `ModelManager` : avec `baseDirProvider` → dossier temp + `http.Client` **factice**
  (MockClient `package:http/testing.dart`) : getters de chemins, `isSttModelAvailable`/
  `isTtsModelAvailable` selon fichiers présents, construction d'URL du catalogue,
  parsing d'une réponse `tree/main` (JSON → chemins, dossiers récursifs), skip des
  fichiers déjà présents, nettoyage des `.tmp`.
- **Mocks restent le défaut** → `companion_pipeline_test`, `state_machine_test`,
  etc. inchangés et verts.
- CI : `analyze` + `test` + `format` ; le build APK reste le smoke test du natif.

## 8. Hors périmètre (reportés)

- **Adapter LLM** llamadart/CroissantLLM + `LlmPort.initialize()` + catalogue LLM
  & `downloadLlmModel` → **spec suivant**.
- **Routage Bluetooth + ducking + focus audio** (`audio_session`) — KITT-neuf,
  absent de Tachikoma (débrief §4.5).
- **Boucle de capture micro → STT** dans `CompanionPipeline` (streaming continu,
  endpointing live).
- **Déclenchement UI** du téléchargement des modèles + écran d'onboarding.
- **Wake-word**, **TTS streaming par phrase**, **abstention par confiance**.

## 9. Réconciliation documentaire (incluse dans ce spec)

- `docs/DEBRIEF.md` : annoter §4.3 / §6.1 / §8 — le LLM décrit (llamadart dual
  CroissantLLM+Qwen) n'est plus le code vivant de Tachikoma ; acter la décision
  **A2** (KITT garde CroissantLLM, Tachikoma a migré vers Gemma 4 — divergence
  volontaire pour le FR natif). STT/TTS restent confirmés inchangés.
- `CLAUDE.md` : corriger la ligne « LLM `llamadart` … » pour refléter qu'il s'agit
  d'un choix KITT divergent (et non d'un état actuel de Tachikoma) ; ajouter les
  dossiers `adapters/sherpa`, `adapters/audio`, `adapters/models`.
- `docs/TACHIKOMA-INVENTORY.md` : référencé par le débrief mais **absent**. →
  soit le créer (mapping ports→symboles + chemins+lignes), soit retirer la
  référence du débrief. **Décision : retirer la référence** (le débrief §4/§6
  contient déjà l'inventaire ancré) pour éviter une dette de doc fantôme.

## 10. Critères d'acceptation

1. `flutter pub get` résout `sherpa_onnx`, `record`, `just_audio`, `path_provider`,
   `http`, `permission_handler`.
2. `flutter analyze` : 0 erreur, 0 warning.
3. `flutter test` : tous les tests passent, dont les nouveaux tests de logique pure
   (§7), **sans** device/natif/modèles.
4. `KITT_ADAPTERS=mock` (défaut) : comportement identique à aujourd'hui.
5. `KITT_ADAPTERS=real` : l'app compile ; avec modèles présents sur device, STT/TTS/
   audio réels fonctionnent (validé device/CI, hors test unitaire).
6. Aucun poids de modèle (`*.onnx`, `*.gguf`) committé.
7. `DEBRIEF.md` / `CLAUDE.md` réconciliés ; référence `TACHIKOMA-INVENTORY.md` résolue.
