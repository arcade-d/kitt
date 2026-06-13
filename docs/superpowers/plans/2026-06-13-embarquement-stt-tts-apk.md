# Embarquement STT + TTS dans l'APK — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Embarquer les modèles STT et TTS dans l'APK (récupérés en CI au build, jamais commités) et les extraire au premier lancement, supprimant le téléchargement runtime qui plante ; seul le LLM reste téléchargé.

**Architecture :** Une étape CI télécharge STT (4 fichiers HF) + TTS (bundle sherpa-onnx incluant `espeak-ng-data`) et les empaquette en `assets/models/voice.tar` (gitignoré). Au démarrage, `AssetVoiceInstaller` extrait cette archive vers `<docs>/models/{stt,tts}` — **les mêmes chemins** que `ModelManager` — donc `SherpaStt`/`SherpaTts` sont inchangés. `voice.tar` est un tar **non compressé** (l'APK zippe déjà ; décodage = parsing d'en-têtes, quasi zéro CPU).

**Tech Stack :** Flutter/Dart, Riverpod, package `archive` 4.0.9 (`TarDecoder`), `path_provider`, GitHub Actions, `curl`/`tar`.

Spec de référence : `docs/superpowers/specs/2026-06-13-embarquement-stt-tts-apk-design.md`

---

## Structure des fichiers

- **Créer** `lib/adapters/models/asset_voice_installer.dart` — extrait `voice.tar` vers `modelsDir` ; idempotent ; injectable (loader + `ModelManager`).
- **Créer** `test/adapters/models/asset_voice_installer_test.dart` — tests d'extraction/idempotence/erreur (fixture tar via `tar` système).
- **Créer** `tool/fetch_voice_assets.sh` — fetch CI : STT (HF) + TTS (bundle) → `assets/models/voice.tar`.
- **Créer** `assets/models/.gitkeep` — pour que le dossier asset existe (le `.tar` reste gitignoré).
- **Modifier** `pubspec.yaml` — dépendance directe `archive` + asset `assets/models/`.
- **Modifier** `.gitignore` — ignorer `assets/models/*` sauf `.gitkeep`.
- **Modifier** `lib/application/providers.dart` — `voiceInstallerProvider` ; `adaptersProvider`/`modelsReadyProvider` l'attendent.
- **Modifier** `lib/ui/model_download_screen.dart` — ne télécharger que le LLM.
- **Modifier** `.github/workflows/ci.yml` — étape de fetch avant le build APK.

---

## Task 1 : Dépendance `archive` + structure des assets + gitignore

**Files:**
- Modify: `pubspec.yaml`
- Modify: `.gitignore`
- Create: `assets/models/.gitkeep`

- [ ] **Step 1 : Ajouter `archive` en dépendance directe**

Run: `flutter pub add archive`
Expected: `pubspec.yaml` gagne une ligne `archive: ^4.0.9` sous `dependencies:` et `flutter pub get` réussit.

- [ ] **Step 2 : Déclarer le dossier d'assets modèles**

Dans `pubspec.yaml`, sous `flutter:` → `assets:`, ajouter la ligne `- assets/models/` :

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/persona/
    - assets/models/
```

- [ ] **Step 3 : Créer le dossier asset avec un `.gitkeep`**

```bash
mkdir -p assets/models
touch assets/models/.gitkeep
```

- [ ] **Step 4 : Ignorer les poids mais garder `.gitkeep`**

Ajouter à la fin de `.gitignore` :

```gitignore
# Poids de modèles embarqués (récupérés en CI au build, JAMAIS commités)
assets/models/*
!assets/models/.gitkeep
```

- [ ] **Step 5 : Vérifier que pub get passe et que l'ignore est correct**

Run: `flutter pub get && git check-ignore assets/models/voice.tar && git status --porcelain assets/models`
Expected: `flutter pub get` OK ; `git check-ignore` affiche `assets/models/voice.tar` (donc ignoré) ; `git status` ne liste QUE `assets/models/.gitkeep` (ajouté).

- [ ] **Step 6 : Commit**

```bash
git add pubspec.yaml pubspec.lock .gitignore assets/models/.gitkeep
git commit -m "build: dépendance archive + dossier assets/models (poids gitignorés)"
```

---

## Task 2 : `AssetVoiceInstaller` (extraction de `voice.tar`)

**Files:**
- Create: `lib/adapters/models/asset_voice_installer.dart`
- Test: `test/adapters/models/asset_voice_installer_test.dart`

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `test/adapters/models/asset_voice_installer_test.dart` :

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitt/adapters/models/asset_voice_installer.dart';
import 'package:kitt/adapters/models/model_manager.dart';

void main() {
  group('AssetVoiceInstaller', () {
    late Directory tmp;
    late Uint8List voiceTar;

    // Fichiers sentinelles attendus par ModelManager (STT + TTS).
    const entries = <String>[
      'stt/encoder.onnx',
      'stt/decoder.onnx',
      'stt/joiner.onnx',
      'stt/tokens.txt',
      'tts/model.onnx',
      'tts/tokens.txt',
      'tts/espeak-ng-data/fr_dict',
      'tts/espeak-ng-data/phontab',
    ];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('kitt_avi_');
      // Construit une archive tar de test avec le `tar` système (indépendant
      // de l'API d'encodage du package archive).
      final stage = Directory('${tmp.path}/stage');
      for (final e in entries) {
        final f = File('${stage.path}/$e')..createSync(recursive: true);
        f.writeAsStringSync('data:$e');
      }
      final res = await Process.run(
        'tar',
        <String>['-cf', '${tmp.path}/voice.tar', '-C', stage.path, 'stt', 'tts'],
      );
      expect(res.exitCode, 0, reason: res.stderr.toString());
      voiceTar = File('${tmp.path}/voice.tar').readAsBytesSync();
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    Future<ModelManager> makeManager() async {
      final mm = ModelManager(baseDirProvider: () async => '${tmp.path}/app');
      await mm.initialize();
      return mm;
    }

    test('extrait STT+TTS aux chemins du ModelManager', () async {
      final mm = await makeManager();
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async => voiceTar,
      );
      expect(installer.isInstalled, isFalse);

      await installer.ensureInstalled();

      expect(installer.isInstalled, isTrue);
      expect(mm.isSttModelAvailable, isTrue);
      expect(mm.isTtsModelAvailable, isTrue);
      expect(
        File('${mm.ttsModelDir}/espeak-ng-data/fr_dict').existsSync(),
        isTrue,
      );
    });

    test('idempotent : ne recharge pas si déjà installé', () async {
      final mm = await makeManager();
      var calls = 0;
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async {
          calls++;
          return voiceTar;
        },
      );
      await installer.ensureInstalled();
      await installer.ensureInstalled();
      expect(calls, 1);
    });

    test('archive corrompue : lève une erreur', () async {
      final mm = await makeManager();
      final installer = AssetVoiceInstaller(
        manager: mm,
        loader: (_) async => Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      await expectLater(installer.ensureInstalled(), throwsA(anything));
    });
  });
}
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/adapters/models/asset_voice_installer_test.dart`
Expected: ÉCHEC à la compilation (`asset_voice_installer.dart` n'existe pas / `AssetVoiceInstaller` introuvable).

- [ ] **Step 3 : Implémenter `AssetVoiceInstaller`**

Créer `lib/adapters/models/asset_voice_installer.dart` :

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'model_manager.dart';

/// Charge les octets d'un asset (injectable pour les tests).
typedef AssetBytesLoader = Future<Uint8List> Function(String assetKey);

/// Extrait les modèles voix (STT + TTS) embarqués dans l'APK
/// (`assets/models/voice.tar`) vers le dossier `models/` du `ModelManager`,
/// aux mêmes chemins que ceux attendus par `SherpaStt`/`SherpaTts`.
///
/// L'archive est un tar **non compressé** (l'APK zippe déjà les assets) :
/// le décodage se résume à du parsing d'en-têtes + découpage d'octets.
class AssetVoiceInstaller {
  AssetVoiceInstaller({required this.manager, AssetBytesLoader? loader})
      : _load = loader ?? _defaultLoad;

  final ModelManager manager;
  final AssetBytesLoader _load;

  static const String assetKey = 'assets/models/voice.tar';

  static Future<Uint8List> _defaultLoad(String key) async =>
      (await rootBundle.load(key)).buffer.asUint8List();

  /// Vrai si STT et TTS sont déjà présents sur disque (sentinelles du manager).
  bool get isInstalled =>
      manager.isSttModelAvailable && manager.isTtsModelAvailable;

  /// Extrait l'archive si nécessaire. No-op si déjà installé. Lève si
  /// l'extraction ne produit pas les fichiers attendus.
  Future<void> ensureInstalled() async {
    if (isInstalled) return;

    final Uint8List bytes = await _load(assetKey);
    final Archive archive = TarDecoder().decodeBytes(bytes);

    for (final ArchiveFile file in archive.files) {
      if (!file.isFile) continue;
      final Uint8List? data = file.readBytes();
      if (data == null) continue;
      final out = File('${manager.modelsDir}/${file.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(data);
    }

    if (!isInstalled) {
      throw StateError(
        'Extraction des voix incomplète depuis $assetKey '
        '(STT=${manager.isSttModelAvailable}, TTS=${manager.isTtsModelAvailable})',
      );
    }
  }
}
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il passe**

Run: `flutter test test/adapters/models/asset_voice_installer_test.dart`
Expected: PASS (3 tests verts).

- [ ] **Step 5 : Format + analyze**

Run: `dart format lib/adapters/models/asset_voice_installer.dart test/adapters/models/asset_voice_installer_test.dart && flutter analyze lib/adapters/models/asset_voice_installer.dart`
Expected: aucun changement de format, analyze sans erreur.

- [ ] **Step 6 : Commit**

```bash
git add lib/adapters/models/asset_voice_installer.dart test/adapters/models/asset_voice_installer_test.dart
git commit -m "feat(models): AssetVoiceInstaller — extraction de voice.tar embarqué"
```

---

## Task 3 : Câblage Riverpod (installer avant les adapters réels)

**Files:**
- Modify: `lib/application/providers.dart`
- Test: `test/application/providers_test.dart`

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans `test/application/providers_test.dart` (dans le `main()`, à côté des tests existants) :

```dart
  test('voiceInstallerProvider : no-op en mode mock', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await expectLater(
      container.read(voiceInstallerProvider.future),
      completes,
    );
  });
```

Si les imports manquent en tête du fichier, s'assurer d'avoir :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kitt/application/providers.dart';
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `flutter test test/application/providers_test.dart`
Expected: ÉCHEC compilation (`voiceInstallerProvider` non défini).

- [ ] **Step 3 : Ajouter le provider et le câbler**

Dans `lib/application/providers.dart` :

a) Ajouter l'import en tête (avec les autres imports d'adapters models) :

```dart
import '../adapters/models/asset_voice_installer.dart';
```

b) Ajouter le provider juste après `modelManagerProvider` :

```dart
/// Installe (extrait) les voix embarquées (STT+TTS) avant usage des adapters
/// réels. No-op en mode mock. Idempotent.
final voiceInstallerProvider = FutureProvider<void>((ref) async {
  if (!kUseRealAdapters) return;
  final mm = await ref.watch(modelManagerProvider.future);
  await AssetVoiceInstaller(manager: mm).ensureInstalled();
});
```

c) Dans `adaptersProvider`, attendre l'installer avant de construire les adapters sherpa (branche `kUseRealAdapters`) :

```dart
final adaptersProvider = FutureProvider<VoiceAdapters>((ref) async {
  if (kUseRealAdapters) {
    final mm = await ref.watch(modelManagerProvider.future);
    await ref.watch(voiceInstallerProvider.future);
    return VoiceAdapters(
      stt: SherpaStt(mm.sttModelDir),
      llm: LlamaCroissantLlm(mm.llmModelPath),
      tts: KittFilteredTts(SherpaTts(mm.ttsModelDir)),
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
```

d) Dans `modelsReadyProvider`, attendre l'installer puis ne vérifier que le LLM (STT/TTS garantis par l'extraction) :

```dart
/// Vrai si les modèles requis sont présents (toujours vrai en mode mock).
/// Les voix (STT/TTS) sont extraites de l'APK ; seul le LLM est téléchargé.
final modelsReadyProvider = FutureProvider<bool>((ref) async {
  if (!kUseRealAdapters) return true;
  final mm = await ref.watch(modelManagerProvider.future);
  await ref.watch(voiceInstallerProvider.future);
  return mm.isLlmModelAvailable;
});
```

- [ ] **Step 4 : Lancer les tests pour vérifier qu'ils passent**

Run: `flutter test test/application/providers_test.dart`
Expected: PASS (test no-op + tests existants verts).

- [ ] **Step 5 : Format + analyze**

Run: `dart format lib/application/providers.dart test/application/providers_test.dart && flutter analyze lib/application/providers.dart`
Expected: pas de reformat, analyze sans erreur.

- [ ] **Step 6 : Commit**

```bash
git add lib/application/providers.dart test/application/providers_test.dart
git commit -m "feat(app): extraire les voix (installer) avant les adapters réels"
```

---

## Task 4 : `ModelDownloadScreen` ne télécharge plus que le LLM

**Files:**
- Modify: `lib/ui/model_download_screen.dart`

- [ ] **Step 1 : Remplacer le contenu de l'écran**

Remplacer **tout** le fichier `lib/ui/model_download_screen.dart` par :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';

/// Écran de téléchargement du **LLM** (première utilisation, mode réel).
/// Les voix (STT/TTS) sont embarquées dans l'APK et déjà extraites par
/// l'installer avant cet écran ; il ne reste que le cerveau à télécharger.
/// Une fois terminé, invalide [modelsReadyProvider] pour basculer vers
/// [CompanionScreen].
class ModelDownloadScreen extends ConsumerStatefulWidget {
  const ModelDownloadScreen({super.key});

  @override
  ConsumerState<ModelDownloadScreen> createState() =>
      _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends ConsumerState<ModelDownloadScreen> {
  double _llmProgress = 0;
  bool _hasStarted = false;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startDownload());
  }

  Future<void> _startDownload() async {
    if (_hasStarted) return;
    _hasStarted = true;
    if (mounted) {
      setState(() {
        _hasError = false;
        _errorMessage = '';
        _llmProgress = 0;
      });
    }

    try {
      final mm = await ref.read(modelManagerProvider.future);
      await mm.downloadLlmModel(
        onProgress: (final double p) {
          if (mounted) setState(() => _llmProgress = p);
        },
      );
      if (mounted) {
        ref.invalidate(modelsReadyProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _hasStarted = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 24),
              const Text(
                'KITT',
                style: TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Téléchargement du cerveau — première utilisation',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Voix déjà embarquées. Cerveau ≈ 830 Mo — restez en Wi‑Fi.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 40),
              _ProgressRow(
                label: 'Cerveau (CroissantLLM)',
                progress: _llmProgress,
                done: _llmProgress >= 1.0,
              ),
              const SizedBox(height: 40),
              if (_hasError) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0000),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF1A1A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Erreur de téléchargement',
                        style: TextStyle(
                          color: Color(0xFFFF1A1A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A0000),
                    foregroundColor: const Color(0xFFFF1A1A),
                    side: const BorderSide(color: Color(0xFFFF1A1A)),
                  ),
                  onPressed: _startDownload,
                  child: const Text('Réessayer'),
                ),
              ] else ...<Widget>[
                const Text(
                  'Cerveau (CroissantLLM)',
                  style: TextStyle(
                    color: Color(0xFFFFB000),
                    fontSize: 13,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.label,
    required this.progress,
    required this.done,
  });

  final String label;
  final double progress;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                color: done ? const Color(0xFFFFB000) : Colors.white70,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
            if (done)
              const Icon(Icons.check_circle, color: Color(0xFFFFB000), size: 16)
            else
              Text(
                '${(progress * 100).toStringAsFixed(0)} %',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFF1A1A1A),
            valueColor: AlwaysStoppedAnimation<Color>(
              done ? const Color(0xFFFFB000) : const Color(0xFFCC8800),
            ),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2 : Format + analyze**

Run: `dart format lib/ui/model_download_screen.dart && flutter analyze lib/ui/model_download_screen.dart`
Expected: pas de reformat ; analyze sans erreur ni import inutilisé (plus de référence à `model_catalog.dart`).

- [ ] **Step 3 : Suite de tests complète (rien cassé)**

Run: `flutter test`
Expected: tous les tests verts.

- [ ] **Step 4 : Commit**

```bash
git add lib/ui/model_download_screen.dart
git commit -m "feat(ui): écran de download = LLM seul (voix embarquées)"
```

---

## Task 5 : Script de fetch CI + intégration workflow

**Files:**
- Create: `tool/fetch_voice_assets.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1 : Créer le script de fetch**

Créer `tool/fetch_voice_assets.sh` :

```bash
#!/usr/bin/env bash
# Récupère STT + TTS et produit assets/models/voice.tar.
# Les poids ne sont JAMAIS commités (assets/models/* gitignoré).
#   - STT : 4 fichiers HF (noms plats), attendus par SherpaStt.
#   - TTS : bundle sherpa-onnx (inclut model + tokens + espeak-ng-data complet),
#           remappé vers les chemins attendus par SherpaTts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/models/voice.tar"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

HF_STT="https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-fr-kroko-2025-08-06/resolve/main"
TTS_BUNDLE="https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-gilles-low.tar.bz2"

dl() { curl -fSL --retry 5 --retry-delay 3 -o "$1" "$2"; }

# --- STT : encoder/decoder/joiner/tokens ---
mkdir -p "$STAGE/stt"
for f in encoder decoder joiner; do
  dl "$STAGE/stt/$f.onnx" "$HF_STT/$f.onnx"
done
dl "$STAGE/stt/tokens.txt" "$HF_STT/tokens.txt"

# --- TTS : bundle -> model.onnx + tokens.txt + espeak-ng-data ---
mkdir -p "$STAGE/tts"
dl "$STAGE/tts.tar.bz2" "$TTS_BUNDLE"
tar -xjf "$STAGE/tts.tar.bz2" -C "$STAGE"
SRC="$STAGE/vits-piper-fr_FR-gilles-low"
mv "$SRC/fr_FR-gilles-low.onnx" "$STAGE/tts/model.onnx"
mv "$SRC/tokens.txt"            "$STAGE/tts/tokens.txt"
mv "$SRC/espeak-ng-data"        "$STAGE/tts/espeak-ng-data"

# --- Archive finale : tar NON compressé (l'APK zippe déjà) ---
mkdir -p "$ROOT/assets/models"
tar -cf "$OUT" -C "$STAGE" stt tts

# --- Vérif : fichiers sentinelles attendus par les adapters ---
for need in \
  stt/encoder.onnx stt/decoder.onnx stt/joiner.onnx stt/tokens.txt \
  tts/model.onnx tts/tokens.txt \
  tts/espeak-ng-data/fr_dict tts/espeak-ng-data/phontab; do
  tar -tf "$OUT" | grep -qx "$need" || { echo "MANQUE dans voice.tar: $need" >&2; exit 1; }
done
echo "OK: $OUT ($(du -h "$OUT" | cut -f1))"
```

- [ ] **Step 2 : Rendre exécutable**

Run: `chmod +x tool/fetch_voice_assets.sh`
Expected: pas de sortie ; le bit exécutable est posé.

- [ ] **Step 3 : Vérifier le script localement (réseau requis)**

Run: `bash tool/fetch_voice_assets.sh && tar -tf assets/models/voice.tar | head -8 && du -h assets/models/voice.tar`
Expected: se termine par `OK: …/voice.tar (…M)` ; le listing montre `stt/…` et `tts/…` ; taille ≈ 150 Mo.
(Note : `assets/models/voice.tar` reste gitignoré — ne pas l'ajouter à git.)

- [ ] **Step 4 : Intégrer l'étape dans la CI**

Dans `.github/workflows/ci.yml`, insérer une étape **avant** « Build debug APK (arm64) », juste après le bloc des gates qualité :

```yaml
      # Récupère STT+TTS dans assets/models/voice.tar (poids non commités)
      - name: Fetch voice models into APK assets
        run: bash tool/fetch_voice_assets.sh

      # APK debug KITT (adapters réels, split par ABI -> arm64 seul pour Pixel 7)
      - name: Build debug APK (arm64)
        run: flutter build apk --debug --dart-define=KITT_ADAPTERS=real --split-per-abi
```

- [ ] **Step 5 : Vérifier la syntaxe YAML**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('YAML OK')"`
Expected: `YAML OK`.

- [ ] **Step 6 : Commit**

```bash
git add tool/fetch_voice_assets.sh .github/workflows/ci.yml
git commit -m "ci: fetch STT+TTS -> assets/models/voice.tar avant le build APK"
```

---

## Task 6 : Vérification finale d'ensemble

**Files:** aucun (validation)

- [ ] **Step 1 : Gates qualité complètes (comme la CI)**

Run: `dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test`
Expected: format OK, analyze sans erreur, tous les tests verts.

- [ ] **Step 2 : Vérifier l'absence de poids dans git**

Run: `git status --porcelain && git check-ignore assets/models/voice.tar`
Expected: aucun `*.onnx`/`*.tar` listé par `git status` ; `git check-ignore` confirme que `voice.tar` est ignoré.

- [ ] **Step 3 : (Optionnel, device) build + smoke**

Run: `bash tool/fetch_voice_assets.sh && flutter build apk --debug --dart-define=KITT_ADAPTERS=real --split-per-abi`
Expected: build OK ; APK arm64 généré, taille augmentée d'environ +150 Mo. Au 1er lancement device : pas d'étape « voix » dans le téléchargement ; seul le LLM se télécharge ; STT/TTS fonctionnent offline.

---

## Notes de réalisation

- **Pas de fallback download** pour STT/TTS : on a choisi le mode embarqué ; en cas d'archive absente/corrompue, `AssetVoiceInstaller` échoue fort (remonté par `BootstrapGate`).
- **Extraction sur l'isolate principal** : acceptable car `voice.tar` est NON compressé (décodage = parsing d'en-têtes), et les écritures fichier sont `await`. Si un ANR/pic mémoire apparaît sur device, déplacer décodage+écriture dans `Isolate.run` (suivi, hors v1).
- **Hors périmètre** : fiabilité du download LLM (832 Mo) — spec dédiée à venir.
- **Source des URLs** : le script CI duplique les URLs de `model_catalog.dart` (STT) ; le TTS passe par le bundle sherpa-onnx (plus robuste que les 355 fichiers `espeak-ng-data` du repo HF). Garder les deux cohérents si on change de modèle.
