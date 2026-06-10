# Adapters réels Sherpa + Audio + ModelManager — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Brancher les vrais moteurs Tachikoma (sherpa STT/TTS, audio record/just_audio) derrière les ports STT/TTS/AudioIn/AudioOut de KITT, alimentés par un `ModelManager` porté et testable, avec bascule mock ↔ réel ; le LLM reste mock (spec suivant).

**Architecture:** Adapters hexagonaux écrits **dans KITT** (`lib/adapters/{sherpa,audio,models}`), dépendant des mêmes packages pub.dev que Tachikoma. La logique pure (conversion PCM, encodage WAV, nettoyage texte, mapping STT, parsing HF, chemins) est isolée dans des fichiers **sans import natif**, donc testable par `flutter test` sur l'hôte. Les classes d'adapters qui touchent au natif sont du glue mince, validé par `flutter analyze` + build APK CI / device. Un faisceau `VoiceAdapters` + `--dart-define=KITT_ADAPTERS=real|mock` sélectionne l'implémentation au build.

**Tech Stack:** Flutter/Dart 3.12, Riverpod, `sherpa_onnx`, `record`, `just_audio`, `path_provider`, `http` (+ `package:http/testing.dart` pour les mocks réseau), `permission_handler`.

**Référence spec:** `docs/superpowers/specs/2026-06-10-adapters-reels-sherpa-audio-design.md`

---

## Structure des fichiers

Créés :
- `lib/adapters/models/model_catalog.dart` — value types (`ModelFile`/`ModelInfo`/`ModelStatus`/`HfEntry`), constantes de catalogue HF, `parseHfTree` (pur).
- `lib/adapters/models/model_not_available.dart` — exception `ModelNotAvailable`.
- `lib/adapters/models/model_manager.dart` — `ModelManager` injectable (baseDir + http.Client).
- `lib/adapters/audio/pcm.dart` — `int16BytesToFloat32`, `calculateAudioLevel` (purs).
- `lib/adapters/audio/wav_encoder.dart` — `pcmFloat32ToWav` (pur).
- `lib/adapters/audio/record_audio_in.dart` — `RecordAudioIn implements AudioInPort` (glue).
- `lib/adapters/audio/just_audio_out.dart` — `JustAudioOut implements AudioOutPort` (glue).
- `lib/adapters/sherpa/espeak_text.dart` — `sanitizeForEspeak` (pur).
- `lib/adapters/sherpa/stt_mapping.dart` — `mapSttResult` (pur).
- `lib/adapters/sherpa/sherpa_stt.dart` — `SherpaStt implements SttPort` (glue).
- `lib/adapters/sherpa/sherpa_tts.dart` — `SherpaTts implements TtsPort` (glue).
- Tests : `test/adapters/audio/pcm_test.dart`, `wav_encoder_test.dart`, `test/adapters/sherpa/espeak_text_test.dart`, `stt_mapping_test.dart`, `test/adapters/models/model_manager_test.dart`, `test/application/providers_test.dart`.

Modifiés :
- `pubspec.yaml` — dépendances.
- `lib/application/providers.dart` — faisceau `VoiceAdapters` + bascule + `modelManagerProvider`.
- `CLAUDE.md`, `docs/DEBRIEF.md` — réconciliation (LLM périmé, référence inventaire absente).

---

## Task 1: Dépendances

**Files:**
- Modify: `pubspec.yaml` (bloc `dependencies`)

- [ ] **Step 1: Ajouter les dépendances**

Dans `pubspec.yaml`, juste après la ligne `ulid: ^2.0.0` (et avant `dev_dependencies:`), ajouter :

```yaml
  # Pipeline vocal réel (adapters portés de Tachikoma)
  sherpa_onnx: ^1.12.33
  record: ^6.2.0
  just_audio: ^0.10.5
  path_provider: ^2.1.5
  permission_handler: ^11.4.0
  http: ^1.6.0
```

- [ ] **Step 2: Résoudre les packages**

Run: `flutter pub get`
Expected: `Got dependencies!` (aucune erreur de résolution).
Note : si plus tard `flutter build apk` ne trouve pas l'implémentation Android de `record`, ajouter `record_android: ^1.5.1` au même bloc. Sans objet pour `analyze`/`test` sur l'hôte.

- [ ] **Step 3: Vérifier la base analyze**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "build(deps): sherpa_onnx, record, just_audio, path_provider, http, permission_handler"
```

---

## Task 2: Helpers PCM (purs)

**Files:**
- Create: `lib/adapters/audio/pcm.dart`
- Test: `test/adapters/audio/pcm_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/adapters/audio/pcm_test.dart` :

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/audio/pcm.dart';

void main() {
  group('int16BytesToFloat32', () {
    test('bytes vides -> liste vide', () {
      expect(int16BytesToFloat32(Uint8List(0)), isEmpty);
    });

    test('longueur impaire : le dernier octet est ignoré', () {
      // 0x4000 (LE) = 16384 ; 3e octet ignoré.
      final out = int16BytesToFloat32(
        Uint8List.fromList([0x00, 0x40, 0x7F]),
      );
      expect(out.length, 1);
      expect(out.first, closeTo(16384 / 32768.0, 1e-9));
    });

    test('max positif ~ +1', () {
      final out = int16BytesToFloat32(Uint8List.fromList([0xFF, 0x7F]));
      expect(out.first, closeTo(32767 / 32768.0, 1e-9));
    });

    test('min négatif == -1', () {
      final out = int16BytesToFloat32(Uint8List.fromList([0x00, 0x80]));
      expect(out.first, closeTo(-1.0, 1e-9));
    });
  });

  group('calculateAudioLevel', () {
    test('vide et silence -> 0', () {
      expect(calculateAudioLevel(const []), 0.0);
      expect(calculateAudioLevel(const [0.0, 0.0]), 0.0);
    });

    test('signal fort -> borné à 1', () {
      expect(calculateAudioLevel(const [1.0, 1.0]), 1.0);
    });
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/adapters/audio/pcm_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kitt' ... pcm.dart` / cible introuvable.

- [ ] **Step 3: Implémenter `pcm.dart`**

`lib/adapters/audio/pcm.dart` :

```dart
import 'dart:typed_data';

/// Convertit des octets PCM int16 (little-endian) en échantillons float
/// normalisés [-1.0, 1.0]. Tolère une longueur impaire (dernier octet ignoré).
/// Porté de Tachikoma `audio_recorder_service.dart`.
List<double> int16BytesToFloat32(Uint8List bytes) {
  final usableLength = bytes.lengthInBytes & ~1;
  if (usableLength == 0) return <double>[];
  final aligned = Uint8List(usableLength);
  aligned.setRange(0, usableLength, bytes);
  final int16Data = aligned.buffer.asInt16List(0, usableLength ~/ 2);
  return List<double>.generate(
    int16Data.length,
    (i) => int16Data[i] / 32768.0,
  );
}

/// Niveau audio (RMS approché) borné [0.0, 1.0] pour le modulateur visuel.
double calculateAudioLevel(List<double> samples) {
  if (samples.isEmpty) return 0.0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  final rms = sum / samples.length;
  return (rms * 50).clamp(0.0, 1.0);
}
```

- [ ] **Step 4: Lancer le test (doit passer)**

Run: `flutter test test/adapters/audio/pcm_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/adapters/audio/pcm.dart test/adapters/audio/pcm_test.dart
git commit -m "feat(audio): helpers PCM purs (int16->float, RMS) + tests"
```

---

## Task 3: Encodeur WAV (pur)

**Files:**
- Create: `lib/adapters/audio/wav_encoder.dart`
- Test: `test/adapters/audio/wav_encoder_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/adapters/audio/wav_encoder_test.dart` :

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/audio/wav_encoder.dart';

void main() {
  test('en-tête RIFF/WAVE/fmt + longueur', () {
    final wav = pcmFloat32ToWav(Float32List.fromList([0.0]), 16000);
    expect(wav.length, 46); // 44 + 1 échantillon * 2 octets
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    final data = ByteData.sublistView(wav);
    expect(data.getUint32(24, Endian.little), 16000); // sampleRate
    expect(data.getUint32(40, Endian.little), 2); // dataSize
    expect(data.getInt16(44, Endian.little), 0); // échantillon 0.0
  });

  test('clamp des échantillons hors [-1, 1]', () {
    final hi = pcmFloat32ToWav(Float32List.fromList([2.0]), 16000);
    expect(ByteData.sublistView(hi).getInt16(44, Endian.little), 32767);
    final lo = pcmFloat32ToWav(Float32List.fromList([-2.0]), 16000);
    expect(ByteData.sublistView(lo).getInt16(44, Endian.little), -32767);
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/adapters/audio/wav_encoder_test.dart`
Expected: FAIL — cible `pcmFloat32ToWav` introuvable.

- [ ] **Step 3: Implémenter `wav_encoder.dart`**

`lib/adapters/audio/wav_encoder.dart` :

```dart
import 'dart:typed_data';

/// Encapsule des échantillons PCM Float32 mono dans un conteneur WAV
/// (PCM int16 little-endian, en-tête RIFF 44 octets). Pur, testable.
/// Porté de Tachikoma `audio_player_service.dart` (`_createWav`).
Uint8List pcmFloat32ToWav(Float32List samples, int sampleRate) {
  final numSamples = samples.length;
  const numChannels = 1;
  const bitsPerSample = 16;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  const blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = numSamples * blockAlign;
  final fileSize = 36 + dataSize;

  final buffer = ByteData(44 + dataSize);
  var offset = 0;

  // RIFF
  buffer.setUint8(offset++, 0x52); // R
  buffer.setUint8(offset++, 0x49); // I
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  buffer.setUint8(offset++, 0x57); // W
  buffer.setUint8(offset++, 0x41); // A
  buffer.setUint8(offset++, 0x56); // V
  buffer.setUint8(offset++, 0x45); // E

  // fmt
  buffer.setUint8(offset++, 0x66); // f
  buffer.setUint8(offset++, 0x6D); // m
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x20); // (espace)
  buffer.setUint32(offset, 16, Endian.little);
  offset += 4;
  buffer.setUint16(offset, 1, Endian.little); // PCM
  offset += 2;
  buffer.setUint16(offset, numChannels, Endian.little);
  offset += 2;
  buffer.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  buffer.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  buffer.setUint16(offset, blockAlign, Endian.little);
  offset += 2;
  buffer.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;

  // data
  buffer.setUint8(offset++, 0x64); // d
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  for (var i = 0; i < numSamples; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    final int16 = (clamped * 32767).toInt();
    buffer.setInt16(offset, int16, Endian.little);
    offset += 2;
  }

  return buffer.buffer.asUint8List();
}
```

- [ ] **Step 4: Lancer le test (doit passer)**

Run: `flutter test test/adapters/audio/wav_encoder_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/adapters/audio/wav_encoder.dart test/adapters/audio/wav_encoder_test.dart
git commit -m "feat(audio): encodeur WAV pur (PCM float32 -> WAV) + tests"
```

---

## Task 4: Nettoyage texte espeak (pur)

**Files:**
- Create: `lib/adapters/sherpa/espeak_text.dart`
- Test: `test/adapters/sherpa/espeak_text_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/adapters/sherpa/espeak_text_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/sherpa/espeak_text.dart';

void main() {
  test('retire les emojis, conserve les accents français', () {
    expect(
      sanitizeForEspeak('Bonjour 😀 ça va à Noël'),
      'Bonjour  ça va à Noël',
    );
  });

  test('texte 100% emoji -> vide après trim', () {
    expect(sanitizeForEspeak('😀🚗').trim(), '');
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/adapters/sherpa/espeak_text_test.dart`
Expected: FAIL — `sanitizeForEspeak` introuvable.

- [ ] **Step 3: Implémenter `espeak_text.dart`**

`lib/adapters/sherpa/espeak_text.dart` :

```dart
/// Retire les caractères qu'espeak-ng ne sait pas prononcer (emojis, scripts
/// non latins), en conservant l'ASCII, le Latin-1 accentué (À-ÿ) et la
/// ponctuation usuelle. Porté de Tachikoma `tts_service.dart`.
String sanitizeForEspeak(String text) {
  return text.replaceAll(
    RegExp(r'[^\x00-\x7FÀ-ÿ.,!?;: \-]+'),
    '',
  );
}
```

- [ ] **Step 4: Lancer le test (doit passer)**

Run: `flutter test test/adapters/sherpa/espeak_text_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/adapters/sherpa/espeak_text.dart test/adapters/sherpa/espeak_text_test.dart
git commit -m "feat(tts): sanitizeForEspeak pur + tests"
```

---

## Task 5: Mapping résultat STT (pur)

**Files:**
- Create: `lib/adapters/sherpa/stt_mapping.dart`
- Test: `test/adapters/sherpa/stt_mapping_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/adapters/sherpa/stt_mapping_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/sherpa/stt_mapping.dart';

void main() {
  test('trim du texte, confidence null, isFinal transmis', () {
    final r = mapSttResult('  salut KITT  ', isFinal: true);
    expect(r.text, 'salut KITT');
    expect(r.confidence, isNull);
    expect(r.isFinal, isTrue);
    expect(mapSttResult('x', isFinal: false).isFinal, isFalse);
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/adapters/sherpa/stt_mapping_test.dart`
Expected: FAIL — `mapSttResult` introuvable.

- [ ] **Step 3: Implémenter `stt_mapping.dart`**

`lib/adapters/sherpa/stt_mapping.dart` :

```dart
import '../../ports/stt_port.dart';

/// Mappe le texte brut du zipformer vers un [SttResult]. Le zipformer FR
/// n'expose pas de score → `confidence` est toujours `null` (cf. débrief §4.2).
SttResult mapSttResult(String rawText, {required bool isFinal}) {
  return SttResult(text: rawText.trim(), isFinal: isFinal);
}
```

- [ ] **Step 4: Lancer le test (doit passer)**

Run: `flutter test test/adapters/sherpa/stt_mapping_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add lib/adapters/sherpa/stt_mapping.dart test/adapters/sherpa/stt_mapping_test.dart
git commit -m "feat(stt): mapSttResult pur (texte -> SttResult, confidence null) + test"
```

---

## Task 6: Catalogue de modèles + exception + parseHfTree

**Files:**
- Create: `lib/adapters/models/model_catalog.dart`
- Create: `lib/adapters/models/model_not_available.dart`
- Test: `test/adapters/models/model_manager_test.dart` (sous-ensemble catalogue ; complété en Task 7)

- [ ] **Step 1: Écrire le test qui échoue (partie catalogue)**

Créer `test/adapters/models/model_manager_test.dart` avec d'abord les tests de catalogue (la partie ModelManager est ajoutée en Task 7) :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/models/model_catalog.dart';

void main() {
  group('catalogue', () {
    test('sttModel : 4 fichiers, URLs HF zipformer FR', () {
      expect(sttModel.files.length, 4);
      expect(
        sttModel.files.first.url,
        contains('sherpa-onnx-streaming-zipformer-fr-kroko'),
      );
      expect(sttModel.files.first.localPath, '$sttDirName/encoder.onnx');
    });

    test('ttsModel : dossier HF récursif espeak-ng-data', () {
      expect(ttsModel.hfSubdir, 'espeak-ng-data');
      expect(ttsModel.files.any((f) => f.localPath == '$ttsDirName/model.onnx'),
          isTrue);
    });

    test('parseHfTree : JSON tree -> entrées typées', () {
      const json =
          '[{"type":"file","path":"fr_dict"},{"type":"directory","path":"sub"}]';
      final entries = parseHfTree(json);
      expect(entries.length, 2);
      expect(entries[0].isDirectory, isFalse);
      expect(entries[0].path, 'fr_dict');
      expect(entries[1].isDirectory, isTrue);
    });

    test('ModelStatus.allReady', () {
      expect(const ModelStatus(sttReady: true, ttsReady: true).allReady, isTrue);
      expect(
        const ModelStatus(sttReady: true, ttsReady: false).allReady,
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: FAIL — `model_catalog.dart` introuvable.

- [ ] **Step 3: Implémenter `model_not_available.dart`**

`lib/adapters/models/model_not_available.dart` :

```dart
/// Levée quand un fichier de modèle requis est absent du dossier résolu.
class ModelNotAvailable implements Exception {
  const ModelNotAvailable(this.message);

  final String message;

  @override
  String toString() => 'ModelNotAvailable: $message';
}
```

- [ ] **Step 4: Implémenter `model_catalog.dart`**

`lib/adapters/models/model_catalog.dart` :

```dart
import 'dart:convert';

/// Dossiers locaux (sous `<models>/`) par modèle.
const String sttDirName = 'stt';
const String ttsDirName = 'tts';

const String _hfSttBase =
    'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06/resolve/main';
const String _ttsHfRepo = 'csukuangfj/vits-piper-fr_FR-siwis-medium';
const String _ttsHfBase = 'https://huggingface.co/$_ttsHfRepo/resolve/main';

class ModelFile {
  const ModelFile({required this.url, required this.localPath});

  final String url;
  final String localPath;
}

class ModelInfo {
  const ModelInfo({
    required this.name,
    required this.label,
    required this.files,
    this.hfRepoForRecursiveDownload,
    this.hfSubdir,
  });

  final String name;
  final String label;
  final List<ModelFile> files;

  /// Si défini, télécharger récursivement ce sous-dossier du repo HF.
  final String? hfRepoForRecursiveDownload;
  final String? hfSubdir;
}

class ModelStatus {
  const ModelStatus({required this.sttReady, required this.ttsReady});

  final bool sttReady;
  final bool ttsReady;

  bool get allReady => sttReady && ttsReady;
}

class HfEntry {
  const HfEntry({required this.type, required this.path});

  final String type;
  final String path;

  bool get isDirectory => type == 'directory';
}

/// Parse une réponse HuggingFace `tree/main` (JSON) en entrées typées.
List<HfEntry> parseHfTree(String jsonBody) {
  final decoded = jsonDecode(jsonBody) as List<dynamic>;
  return decoded
      .cast<Map<String, dynamic>>()
      .map(
        (e) => HfEntry(type: e['type'] as String, path: e['path'] as String),
      )
      .toList();
}

const ModelInfo sttModel = ModelInfo(
  name: sttDirName,
  label: 'Speech-to-Text',
  files: [
    ModelFile(
      url: '$_hfSttBase/encoder.onnx',
      localPath: '$sttDirName/encoder.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/decoder.onnx',
      localPath: '$sttDirName/decoder.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/joiner.onnx',
      localPath: '$sttDirName/joiner.onnx',
    ),
    ModelFile(
      url: '$_hfSttBase/tokens.txt',
      localPath: '$sttDirName/tokens.txt',
    ),
  ],
);

const ModelInfo ttsModel = ModelInfo(
  name: ttsDirName,
  label: 'Text-to-Speech',
  files: [
    ModelFile(
      url: '$_ttsHfBase/fr_FR-siwis-medium.onnx',
      localPath: '$ttsDirName/model.onnx',
    ),
    ModelFile(
      url: '$_ttsHfBase/tokens.txt',
      localPath: '$ttsDirName/tokens.txt',
    ),
  ],
  hfRepoForRecursiveDownload: _ttsHfRepo,
  hfSubdir: 'espeak-ng-data',
);
```

- [ ] **Step 5: Lancer le test (doit passer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: PASS (4 tests du groupe `catalogue`).

- [ ] **Step 6: Commit**

```bash
git add lib/adapters/models/model_catalog.dart lib/adapters/models/model_not_available.dart test/adapters/models/model_manager_test.dart
git commit -m "feat(models): catalogue HF + parseHfTree + ModelNotAvailable + tests"
```

---

## Task 7: ModelManager injectable

**Files:**
- Create: `lib/adapters/models/model_manager.dart`
- Test: `test/adapters/models/model_manager_test.dart` (ajout d'un groupe `ModelManager`)

- [ ] **Step 1: Ajouter les tests qui échouent**

Dans `test/adapters/models/model_manager_test.dart`, ajouter les imports en tête de fichier :

```dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kitt/adapters/models/model_manager.dart';
```

Puis, **dans** `void main() { ... }` (après le groupe `catalogue`), ajouter :

```dart
  group('ModelManager', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kitt_mm_');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    ModelManager make({http.Client? client}) => ModelManager(
          baseDirProvider: () async => tmp.path,
          client: client ?? MockClient((_) async => http.Response('', 404)),
        );

    test('chemins dérivés du baseDir', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.modelsDir, '${tmp.path}/models');
      expect(mm.sttModelDir, '${tmp.path}/models/stt');
      expect(mm.ttsModelDir, '${tmp.path}/models/tts');
    });

    test('isSttModelAvailable selon présence encoder + tokens', () async {
      final mm = make();
      await mm.initialize();
      expect(mm.isSttModelAvailable, isFalse);
      Directory(mm.sttModelDir).createSync(recursive: true);
      File('${mm.sttModelDir}/encoder.onnx').writeAsStringSync('x');
      File('${mm.sttModelDir}/tokens.txt').writeAsStringSync('x');
      expect(mm.isSttModelAvailable, isTrue);
    });

    test('downloadModel saute les fichiers déjà présents (aucun réseau)', () async {
      final mm = make(
        client: MockClient(
          (_) async => throw StateError('ne doit pas télécharger'),
        ),
      );
      await mm.initialize();
      Directory(mm.sttModelDir).createSync(recursive: true);
      for (final f in const [
        'encoder.onnx',
        'decoder.onnx',
        'joiner.onnx',
        'tokens.txt',
      ]) {
        File('${mm.sttModelDir}/$f').writeAsStringSync('present');
      }
      final progress = <double>[];
      await mm.downloadModel(sttModel, onProgress: progress.add);
      expect(progress.last, 1.0);
    });

    test('downloadModel écrit un fichier manquant depuis le réseau', () async {
      final mm = make(
        client: MockClient((_) async => http.Response('DATA', 200)),
      );
      await mm.initialize();
      const oneFile = ModelInfo(
        name: 'stt',
        label: 'x',
        files: [
          ModelFile(
            url: 'https://example.test/encoder.onnx',
            localPath: 'stt/encoder.onnx',
          ),
        ],
      );
      await mm.downloadModel(oneFile, onProgress: (_) {});
      expect(File('${mm.sttModelDir}/encoder.onnx').readAsStringSync(), 'DATA');
    });
  });
```

Le `sttModel`/`ModelInfo`/`ModelFile` viennent de l'import `model_catalog.dart` déjà présent (Task 6).

- [ ] **Step 2: Lancer les tests (doivent échouer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: FAIL — `model_manager.dart` introuvable.

- [ ] **Step 3: Implémenter `model_manager.dart`**

`lib/adapters/models/model_manager.dart` :

```dart
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'model_catalog.dart';

/// Fournit le dossier de base où stocker les modèles. Par défaut, le dossier
/// documents de l'app ; injectable pour les tests.
typedef BaseDirProvider = Future<String> Function();

/// Gère le catalogue, les chemins locaux et le téléchargement (avec reprise)
/// des modèles. Porté de Tachikoma `model_manager.dart`, épuré et rendu
/// injectable (baseDir + http.Client) pour la testabilité.
class ModelManager {
  ModelManager({BaseDirProvider? baseDirProvider, http.Client? client})
      : _baseDirProvider = baseDirProvider ?? _defaultBaseDir,
        _client = client ?? http.Client();

  final BaseDirProvider _baseDirProvider;
  final http.Client _client;

  static Future<String> _defaultBaseDir() async =>
      (await getApplicationDocumentsDirectory()).path;

  late final String _modelsDir;

  Future<void> initialize() async {
    final base = await _baseDirProvider();
    _modelsDir = '$base/models';
    await Directory(_modelsDir).create(recursive: true);
    await _cleanPartialDownloads();
  }

  String get modelsDir => _modelsDir;
  String get sttModelDir => '$_modelsDir/$sttDirName';
  String get ttsModelDir => '$_modelsDir/$ttsDirName';

  bool get isSttModelAvailable =>
      File('$sttModelDir/encoder.onnx').existsSync() &&
      File('$sttModelDir/tokens.txt').existsSync();

  bool get isTtsModelAvailable =>
      File('$ttsModelDir/model.onnx').existsSync() &&
      File('$ttsModelDir/tokens.txt').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/fr_dict').existsSync() &&
      File('$ttsModelDir/espeak-ng-data/phontab').existsSync();

  ModelStatus getStatus() => ModelStatus(
        sttReady: isSttModelAvailable,
        ttsReady: isTtsModelAvailable,
      );

  /// Supprime les `.tmp` laissés par un téléchargement interrompu.
  Future<void> _cleanPartialDownloads() async {
    final dir = Directory(_modelsDir);
    if (!dir.existsSync()) return;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await entity.delete();
      }
    }
  }

  /// Télécharge les fichiers d'un modèle. Progression 0.0–1.0 via [onProgress].
  /// Saute les fichiers déjà présents et non vides.
  Future<void> downloadModel(
    ModelInfo model, {
    required void Function(double progress) onProgress,
  }) async {
    final totalSteps = model.files.length;
    var completed = 0;

    for (final file in model.files) {
      final targetPath = '$_modelsDir/${file.localPath}';
      final targetFile = File(targetPath);
      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        completed++;
        onProgress(completed / (totalSteps + 1));
        continue;
      }
      await targetFile.parent.create(recursive: true);
      await _downloadFileWithRetry(file.url, targetPath);
      completed++;
      onProgress(completed / (totalSteps + 1));
    }

    if (model.hfRepoForRecursiveDownload != null && model.hfSubdir != null) {
      await _downloadHfDirectory(
        model.hfRepoForRecursiveDownload!,
        model.hfSubdir!,
        '$_modelsDir/${model.name}',
      );
    }

    onProgress(1.0);
  }

  Future<void> _downloadHfDirectory(
    String repo,
    String path,
    String localBase,
  ) async {
    final apiUrl = 'https://huggingface.co/api/models/$repo/tree/main/$path';
    final response = await _httpGetWithRetry(apiUrl);
    if (response.statusCode != 200) {
      throw Exception(
        'Échec listage dossier HF: $path (${response.statusCode})',
      );
    }
    for (final entry in parseHfTree(response.body)) {
      final localPath = '$localBase/${entry.path}';
      if (entry.isDirectory) {
        await Directory(localPath).create(recursive: true);
        await _downloadHfDirectory(repo, entry.path, localBase);
      } else {
        final file = File(localPath);
        if (file.existsSync() && file.lengthSync() > 0) continue;
        await file.parent.create(recursive: true);
        await _downloadFileWithRetry(
          'https://huggingface.co/$repo/resolve/main/${entry.path}',
          localPath,
        );
      }
    }
  }

  Future<http.Response> _httpGetWithRetry(
    String url, {
    int maxRetries = 3,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        return await _client.get(Uri.parse(url));
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
      }
    }
    throw Exception('Inatteignable');
  }

  Future<void> _downloadFileWithRetry(
    String url,
    String targetPath, {
    int maxRetries = 3,
  }) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        await _downloadFile(url, targetPath);
        return;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
      }
    }
  }

  Future<void> _downloadFile(String url, String targetPath) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Téléchargement échoué: HTTP ${response.statusCode} ($url)');
    }
    final tmpPath = '$targetPath.tmp';
    final tmpFile = File(tmpPath);
    final sink = tmpFile.openWrite();
    await response.stream.pipe(sink);
    await sink.close();
    await tmpFile.rename(targetPath);
  }

  void dispose() => _client.close();
}
```

- [ ] **Step 4: Lancer les tests (doivent passer)**

Run: `flutter test test/adapters/models/model_manager_test.dart`
Expected: PASS (4 catalogue + 4 ModelManager = 8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/adapters/models/model_manager.dart test/adapters/models/model_manager_test.dart
git commit -m "feat(models): ModelManager injectable (chemins, dispo, download repris) + tests"
```

---

## Task 8: Adapter `SherpaStt` (glue natif — analyze only)

> Glue mince sur `sherpa_onnx` : non testable sur l'hôte (natif). Vérifié par
> `flutter analyze` (compile + respecte `SttPort`) ; comportement réel validé
> device / build APK CI.

**Files:**
- Create: `lib/adapters/sherpa/sherpa_stt.dart`

- [ ] **Step 1: Implémenter `sherpa_stt.dart`**

`lib/adapters/sherpa/sherpa_stt.dart` :

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../ports/stt_port.dart';
import '../models/model_not_available.dart';
import 'stt_mapping.dart';

/// STT réel : `sherpa_onnx` OnlineRecognizer zipformer FR streaming.
/// Porté de Tachikoma `stt_service.dart`. Le dossier modèle est résolu par le
/// `ModelManager` et passé au constructeur.
class SherpaStt implements SttPort {
  SherpaStt(this.modelDir);

  final String modelDir;

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    for (final name in const [
      'encoder.onnx',
      'decoder.onnx',
      'joiner.onnx',
      'tokens.txt',
    ]) {
      if (!File('$modelDir/$name').existsSync()) {
        throw ModelNotAvailable('Fichier STT manquant: $modelDir/$name');
      }
    }
    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: '$modelDir/encoder.onnx',
          decoder: '$modelDir/decoder.onnx',
          joiner: '$modelDir/joiner.onnx',
        ),
        tokens: '$modelDir/tokens.txt',
        modelType: 'zipformer2',
        numThreads: 2,
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    );
    final recognizer = sherpa.OnlineRecognizer(config);
    _recognizer = recognizer;
    _stream = recognizer.createStream();
    _initialized = true;
  }

  @override
  void acceptWaveform(List<double> samples, int sampleRate) {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;
    stream.acceptWaveform(
      samples: Float32List.fromList(samples),
      sampleRate: sampleRate,
    );
    recognizer.decode(stream);
  }

  @override
  SttResult getResult() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) {
      return mapSttResult('', isFinal: false);
    }
    return mapSttResult(
      recognizer.getResult(stream).text,
      isFinal: recognizer.isEndpoint(stream),
    );
  }

  @override
  bool isEndpoint() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return false;
    return recognizer.isEndpoint(stream);
  }

  @override
  void reset() {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;
    recognizer.reset(stream);
  }

  @override
  Future<void> dispose() async {
    _stream?.free();
    _recognizer?.free();
    _stream = null;
    _recognizer = null;
    _initialized = false;
  }
}
```

- [ ] **Step 2: Vérifier l'analyse**

Run: `flutter analyze`
Expected: `No issues found!`
Note : si l'analyse remonte un nom d'API `sherpa_onnx` différent (ex. classe de config renommée entre versions), aligner sur l'API de la version résolue ; les noms ici reflètent `sherpa_onnx` 1.12.x tel qu'utilisé par Tachikoma.

- [ ] **Step 3: Commit**

```bash
git add lib/adapters/sherpa/sherpa_stt.dart
git commit -m "feat(stt): adapter SherpaStt (sherpa_onnx zipformer) implements SttPort"
```

---

## Task 9: Adapter `SherpaTts` (glue natif — analyze only)

**Files:**
- Create: `lib/adapters/sherpa/sherpa_tts.dart`

- [ ] **Step 1: Implémenter `sherpa_tts.dart`**

`lib/adapters/sherpa/sherpa_tts.dart` :

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../ports/tts_port.dart';
import '../models/model_not_available.dart';
import 'espeak_text.dart';

/// TTS réel : `sherpa_onnx` OfflineTts VITS/Piper FR.
/// Porté de Tachikoma `tts_service.dart`. Non streaming (synthèse en bloc).
class SherpaTts implements TtsPort {
  SherpaTts(this.modelDir);

  final String modelDir;

  sherpa.OfflineTts? _tts;

  @override
  Future<void> initialize() async {
    if (_tts != null) return;
    if (!File('$modelDir/model.onnx').existsSync() ||
        !File('$modelDir/tokens.txt').existsSync()) {
      throw ModelNotAvailable('Modèle TTS manquant dans $modelDir');
    }
    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$modelDir/model.onnx',
          tokens: '$modelDir/tokens.txt',
          dataDir: '$modelDir/espeak-ng-data',
        ),
        numThreads: 2,
      ),
    );
    _tts = sherpa.OfflineTts(config);
  }

  @override
  Future<Float32List?> synthesize(
    String text, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    final tts = _tts;
    if (tts == null) return null;
    final clean = sanitizeForEspeak(text);
    if (clean.trim().isEmpty) return null;
    final audio = tts.generate(text: clean, sid: speakerId, speed: speed);
    return audio.samples;
  }

  @override
  int get sampleRate => _tts?.sampleRate ?? 22050;

  @override
  Future<void> dispose() async {
    _tts?.free();
    _tts = null;
  }
}
```

- [ ] **Step 2: Vérifier l'analyse**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/adapters/sherpa/sherpa_tts.dart
git commit -m "feat(tts): adapter SherpaTts (sherpa_onnx VITS/Piper) implements TtsPort"
```

---

## Task 10: Adapter `RecordAudioIn` (glue natif — analyze only)

**Files:**
- Create: `lib/adapters/audio/record_audio_in.dart`

- [ ] **Step 1: Implémenter `record_audio_in.dart`**

`lib/adapters/audio/record_audio_in.dart` :

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../ports/audio_in_port.dart';
import 'pcm.dart';

/// Capture micro réelle : `record` (PCM16 16 kHz mono). Convertit chaque chunk
/// en échantillons float et publie le niveau RMS. Porté de Tachikoma
/// `audio_recorder_service.dart`.
class RecordAudioIn implements AudioInPort {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _level = StreamController<double>.broadcast();
  StreamSubscription<Uint8List>? _sub;

  @override
  Future<Stream<List<double>>> startStream({int sampleRate = 16000}) async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Permission micro refusée');
    }
    final raw = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    final controller = StreamController<List<double>>();
    _sub = raw.listen(
      (bytes) {
        final samples = int16BytesToFloat32(bytes);
        _level.add(calculateAudioLevel(samples));
        controller.add(samples);
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _recorder.stop();
  }

  @override
  Stream<double> get audioLevel => _level.stream;
}
```

- [ ] **Step 2: Vérifier l'analyse**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/adapters/audio/record_audio_in.dart
git commit -m "feat(audio): adapter RecordAudioIn (record) implements AudioInPort"
```

---

## Task 11: Adapter `JustAudioOut` (glue natif — analyze only)

**Files:**
- Create: `lib/adapters/audio/just_audio_out.dart`

- [ ] **Step 1: Implémenter `just_audio_out.dart`**

`lib/adapters/audio/just_audio_out.dart` :

```dart
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../../ports/audio_out_port.dart';
import 'wav_encoder.dart';

/// Sortie audio réelle : `just_audio` jouant le PCM enveloppé en WAV mémoire.
/// Porté de Tachikoma `audio_player_service.dart`. Le routage Bluetooth/ducking
/// (`audio_session`) est hors périmètre (KITT-neuf).
class JustAudioOut implements AudioOutPort {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> playPcm(Float32List samples, int sampleRate) async {
    if (samples.isEmpty) return;
    final wav = pcmFloat32ToWav(samples, sampleRate);
    await _player.setAudioSource(_WavSource(wav));
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  bool get isPlaying => _player.playing;
}

/// Source `just_audio` servant des octets WAV depuis la mémoire.
class _WavSource extends StreamAudioSource {
  _WavSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: e - s,
      offset: s,
      stream: Stream<List<int>>.value(_bytes.sublist(s, e)),
      contentType: 'audio/wav',
    );
  }
}
```

- [ ] **Step 2: Vérifier l'analyse**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/adapters/audio/just_audio_out.dart
git commit -m "feat(audio): adapter JustAudioOut (just_audio) implements AudioOutPort"
```

---

## Task 12: Bascule providers + faisceau VoiceAdapters

**Files:**
- Modify: `lib/application/providers.dart` (remplacement complet)
- Test: `test/application/providers_test.dart`

- [ ] **Step 1: Écrire le test qui échoue**

`test/application/providers_test.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/mock/mock_audio_in.dart';
import 'package:kitt/adapters/mock/mock_stt.dart';
import 'package:kitt/adapters/mock/mock_tts.dart';
import 'package:kitt/application/providers.dart';

void main() {
  test('mode mock (défaut) : le faisceau câble les adapters mock', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final adapters = await container.read(adaptersProvider.future);
    expect(adapters.stt, isA<MockStt>());
    expect(adapters.tts, isA<MockTts>());
    expect(adapters.audioIn, isA<MockAudioIn>());
  });
}
```

- [ ] **Step 2: Lancer le test (doit échouer)**

Run: `flutter test test/application/providers_test.dart`
Expected: FAIL — `adaptersProvider` / `VoiceAdapters` introuvable.

- [ ] **Step 3: Remplacer `providers.dart`**

Remplacer **tout** le contenu de `lib/application/providers.dart` par :

```dart
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
/// Le LLM reste mock dans ce lot (l'adapter llamadart/CroissantLLM viendra dans
/// un lot ultérieur).
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
      llm: MockLlm(),
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
```

- [ ] **Step 4: Lancer le test (doit passer)**

Run: `flutter test test/application/providers_test.dart`
Expected: PASS (1 test).

- [ ] **Step 5: Vérifier la non-régression globale**

Run: `flutter test`
Expected: PASS — toute la suite (mocks par défaut), y compris `companion_pipeline_test`, `state_machine_test`, etc.

- [ ] **Step 6: Commit**

```bash
git add lib/application/providers.dart test/application/providers_test.dart
git commit -m "feat(app): faisceau VoiceAdapters + bascule mock/real (--dart-define=KITT_ADAPTERS)"
```

---

## Task 13: Réconciliation documentaire

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/DEBRIEF.md`

- [ ] **Step 1: Corriger la nature du LLM dans `CLAUDE.md`**

Dans `CLAUDE.md`, remplacer le bloc « Nature du projet » :

Remplacer :
```
Réutilise les briques de **Tachikoma** (app Flutter mono-package — pas de Rust,
pas de FFII) : STT `sherpa_onnx` (zipformer FR streaming), LLM `llamadart`
(CroissantLLM + Qwen2.5-1.5B, GGUF Q4_K_M), TTS `sherpa_onnx` (VITS/Piper FR).
**Whisper et XTTS ne sont PAS utilisés.**
```
Par :
```
Réutilise les briques de **Tachikoma** (app Flutter mono-package — pas de Rust,
pas de FFI) : STT `sherpa_onnx` (zipformer FR streaming), TTS `sherpa_onnx`
(VITS/Piper FR). **LLM : choix KITT = CroissantLLM via `llamadart` (GGUF
Q4_K_M, FR natif)** — divergence assumée : Tachikoma a depuis migré vers
Gemma 4 (`flutter_gemma`, LiteRT-LM). **Whisper et XTTS ne sont PAS utilisés.**
```

- [ ] **Step 2: Documenter les dossiers d'adapters dans `CLAUDE.md`**

Dans `CLAUDE.md`, sous « État actuel (premier jet) », remplacer :
```
- Ports définis ; **adapters MOCK** seulement (`lib/adapters/mock`, `memory`).
```
Par :
```
- Ports définis. Adapters **mock** (`lib/adapters/mock`, `memory`) + **réels**
  `lib/adapters/{sherpa,audio,models}` (STT/TTS sherpa, audio record/just_audio,
  ModelManager) ; bascule `--dart-define=KITT_ADAPTERS=real|mock` (défaut mock).
```

- [ ] **Step 3: Ajouter une mise à jour datée en tête du `DEBRIEF.md`**

Dans `docs/DEBRIEF.md`, juste après le titre de section `## 0. Statut des sources`, insérer (avant le paragraphe existant) :

```
> **Mise à jour 2026-06-10.** Le LLM décrit ci-dessous (§4.3, §6, §8 :
> `llamadart` + CroissantLLM + Qwen, dual-model) **n'est plus le code vivant de
> Tachikoma** : Tachikoma a migré vers **Gemma 4 (`flutter_gemma`, LiteRT-LM)**
> (branche `feat/gemma4-migration`, commit `0840801`). **Décision KITT :** garder
> **CroissantLLM via `llamadart`** (FR natif, GGUF offline) — divergence
> assumée. Le wrapper de référence est récupérable au commit `0840801^`
> (`lib/services/llm_service.dart`, mono-isolate). STT et TTS (`sherpa_onnx`)
> restent **inchangés** et confirmés. Voir le spec
> `docs/superpowers/specs/2026-06-10-adapters-reels-sherpa-audio-design.md`.

```

- [ ] **Step 4: Retirer les références à `TACHIKOMA-INVENTORY.md` (absent)**

Dans `docs/DEBRIEF.md`, appliquer ces remplacements (l'inventaire est déjà intégré aux §4/§6) :

Remplacer :
```
Voir l'inventaire détaillé `TACHIKOMA-INVENTORY.md`.
```
Par :
```
L'inventaire détaillé est intégré aux §4 et §6 de ce document.
```

Remplacer :
```
Détail complet du mapping ports → symboles et de la stratégie : voir `TACHIKOMA-INVENTORY.md`.
```
Par :
```
Détail complet du mapping ports → symboles et de la stratégie : §4 et §6.2 ci-dessus.
```

Remplacer :
```
- **Handoff** : ce doc + `TACHIKOMA-INVENTORY.md` + un `CLAUDE.md` par session.
```
Par :
```
- **Handoff** : ce doc + un `CLAUDE.md` par session.
```

Remplacer :
```
- ~~Statut exact des libs Tachikoma~~ → **résolu** (cf. §4, §6, `TACHIKOMA-INVENTORY.md`). N'est plus bloquant.
```
Par :
```
- ~~Statut exact des libs Tachikoma~~ → **résolu** (cf. §4, §6). N'est plus bloquant.
```

- [ ] **Step 5: Vérifier qu'aucune référence ne subsiste**

Run: `grep -rn "TACHIKOMA-INVENTORY" docs/ CLAUDE.md`
Expected: aucune sortie (exit code 1).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/DEBRIEF.md
git commit -m "docs: réconcilier LLM (CroissantLLM assumé vs Gemma 4) + retirer réf inventaire absente"
```

---

## Task 14: Vérification finale

**Files:** aucun (vérification)

- [ ] **Step 1: Format**

Run: `dart format .`
Then: `dart format --set-exit-if-changed .`
Expected: `0 changed` (aucune reformatation en attente).

- [ ] **Step 2: Analyse complète**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Suite de tests complète**

Run: `flutter test`
Expected: PASS — anciens tests + nouveaux (pcm, wav_encoder, espeak_text, stt_mapping, model_manager [8], providers).

- [ ] **Step 4: Commit éventuel de format**

```bash
git add -A
git diff --cached --quiet || git commit -m "chore(format): dart format"
```

---

## Critères d'acceptation (rappel du spec §10)

1. `flutter pub get` résout les 6 nouvelles dépendances. *(Task 1)*
2. `flutter analyze` : 0 erreur, 0 warning. *(Task 14)*
3. `flutter test` passe, dont les tests de logique pure, sans device/natif/modèles. *(Task 14)*
4. `KITT_ADAPTERS=mock` (défaut) : comportement identique à aujourd'hui. *(Task 12, Step 5)*
5. `KITT_ADAPTERS=real` : compile ; STT/TTS/audio réels fonctionnent sur device avec modèles (hors test unitaire — CI APK / device).
6. Aucun poids de modèle committé (les adapters lisent des dossiers résolus à l'exécution). *(par construction)*
7. `DEBRIEF.md`/`CLAUDE.md` réconciliés ; référence `TACHIKOMA-INVENTORY.md` retirée. *(Task 13)*
