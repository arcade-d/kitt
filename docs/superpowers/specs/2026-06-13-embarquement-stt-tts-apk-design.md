# Spec — Embarquement STT + TTS dans l'APK (fetch en CI)

Date : 2026-06-13
Statut : design validé (brainstorming), prêt pour plan d'implémentation.

## Contexte & problème

Au premier lancement (mode `real`), `ModelDownloadScreen` télécharge séquentiellement
STT → TTS → LLM via `ModelManager`. Ce téléchargement **plante**, en particulier :

- **La voix (TTS)** : `_downloadHfDirectory` aspire récursivement le dossier
  `espeak-ng-data` = **355 fichiers / 36 dossiers (~18 Mo)** en séquentiel via
  l'API HF tree. Fragile (rate-limit, échecs partiels, lenteur) → cause probable
  du crash « la voix ».
- **Le cerveau (LLM)** : download chunké d'un GGUF de **~832 Mo**.

Tailles réelles mesurées (HuggingFace, 2026-06-13) :

| Modèle | Détail | Taille |
|---|---|---|
| STT (zipformer FR streaming) | encoder 66.8 Mo + decoder 0.6 + joiner 0.3 + tokens | **~71 Mo** |
| TTS (vits-piper gilles low) | model.onnx 60 Mo + tokens + `espeak-ng-data` 355 fichiers ~18 Mo | **~81 Mo** |
| LLM (CroissantLLM Q4_K_M) | 1 fichier GGUF | **~832 Mo** |

## Décision

**Embarquer STT + TTS dans l'APK** (~152 Mo) ; **garder le LLM en téléchargement
runtime** (trop gros pour embarquer → APK ~1 Go sinon).

**Packaging = fetch en CI au build** (option retenue vs Git LFS vs hybride) :
les poids **n'entrent jamais dans git** → respecte la règle CLAUDE.md
« ne jamais committer les poids de modèles (`*.gguf`, `*.onnx`) ».

Distribution = APK sideloadé (artefact CI arm64-v8a, Pixel 7) → **aucune limite
de taille Play Store**. Les assets sont indépendants de l'ABI : `--split-per-abi`
reste OK (une seule APK uploadée).

## Objectifs

1. Supprimer les chemins de download STT et TTS (et donc le crash « la voix »).
2. STT + TTS disponibles offline dès le premier lancement, sans réseau.
3. Adapters `SherpaStt` / `SherpaTts` **inchangés** (mêmes chemins disque).
4. Poids absents de git.

## Non-objectifs

- Corriger la fiabilité du **download LLM** (sujet séparé, à traiter ensuite).
- Embarquer le LLM.
- Changer les modèles eux-mêmes (mêmes repos HF qu'aujourd'hui).

## Architecture

### 1. CI (`.github/workflows/ci.yml`)

Nouvelle étape **avant** `flutter build apk`, par ex. un script
`tool/fetch_voice_assets.sh` :

- télécharge les fichiers STT (`encoder/decoder/joiner.onnx`, `tokens.txt`) et
  TTS (`fr_FR-gilles-low.onnx`, `tokens.txt`, dossier `espeak-ng-data` complet) ;
- les range dans l'arborescence cible (`stt/…`, `tts/…`, `tts/espeak-ng-data/…`) ;
- empaquette le tout en **une archive** `assets/models/voice.tar` (tar non
  compressé : l'APK zippe déjà les assets, et l'`.onnx` est quasi incompressible).

`assets/models/` est **gitignoré**. Le script est idempotent (skip si déjà là)
pour accélérer les builds locaux.

### 2. `pubspec.yaml`

Déclarer l'archive comme asset unique :

```yaml
  assets:
    - assets/persona/
    - assets/models/voice.tar
```

### 3. Runtime — `AssetVoiceInstaller`

Nouveau composant (adapter `lib/adapters/models/`) :

- au démarrage en mode `real`, vérifie la présence des fichiers STT/TTS dans
  `<docs>/models/{stt,tts}/…` (mêmes chemins que `ModelManager`) ;
- si absents, **extrait `assets/models/voice.tar`** depuis `rootBundle` vers ces
  chemins (package `archive`, pur Dart). Offline, quelques secondes ;
- **idempotent** : si déjà extraits, ne fait rien ;
- injectable (bundle loader + baseDir) pour testabilité, comme `ModelManager`.

### 4. Câblage providers / readiness

- `adaptersProvider` (mode réel) : `await installer.ensureInstalled()` **avant**
  de construire `SherpaStt` / `SherpaTts`.
- `modelsReadyProvider` : STT/TTS prêts = installables/extraits ; LLM = présent.
- `ModelDownloadScreen` : ne télécharge plus que le **LLM**. STT/TTS retirés des
  étapes ; libellés/ barres mis à jour (une seule barre « Cerveau (CroissantLLM) »).
  L'extraction (rapide) peut afficher un court « Installation des voix… ».
- `ModelManager` : `downloadModel(sttModel/ttsModel)` n'est plus appelé au boot ;
  le code peut rester (utile pour un éventuel refresh), mais n'est plus dans le
  chemin critique. `model_catalog.dart` STT/TTS conservé (source des URLs CI).

## Flux de données

```
[CI] HF → fetch_voice_assets.sh → assets/models/voice.tar → flutter build apk
[App 1er lancement] rootBundle(voice.tar) → AssetVoiceInstaller → <docs>/models/{stt,tts}
                    → SherpaStt(sttDir) / SherpaTts(ttsDir)  (inchangés)
[App] LLM toujours téléchargé par ModelManager.downloadLlmModel (séparé)
```

## Gestion d'erreurs

- Extraction échoue (archive corrompue / espace disque) → **erreur explicite**
  remontée au `BootstrapGate` (pas de fallback silencieux vers download : on a
  choisi le mode embarqué, on échoue fort et clair).
- Vérification minimale post-extraction : présence des fichiers sentinelles déjà
  utilisés (`encoder.onnx`+`tokens.txt` STT ; `model.onnx`+`tokens.txt`+
  `espeak-ng-data/fr_dict`+`phontab` TTS) via les getters `isSttModelAvailable`/
  `isTtsModelAvailable` existants.

## Tests

- **Unitaire `AssetVoiceInstaller`** (sans natif) : injecter des bytes tar + un
  `baseDir` temporaire → assert fichiers extraits aux bons chemins ; assert
  idempotence (2e appel = no-op) ; assert erreur sur archive corrompue.
- **CI** : le script de fetch+pack ; smoke que `voice.tar` contient les entrées
  attendues (liste de fichiers) avant le build.
- Adapters sherpa et `ModelManager` : tests existants conservés (comportement
  inchangé).

## Questions ouvertes

- Format d'archive : `tar` (retenu) vs `zip`. Vérifier le surcoût mémoire de
  l'extraction `archive` sur gros `.onnx` (streaming d'extraction si besoin).
- Faut-il un checksum (sha256) embarqué pour valider l'intégrité à l'extraction ?
- Fiabilité du download LLM (hors périmètre) : à traiter dans un spec dédié.
