# Livraison — APK debug KITT

> Handoff de la session autonome du 2026-06-10. Tout est sur `main`, CI verte,
> APK debug arm64 publié en artefact GitHub Actions.

## Récupérer l'APK

1. GitHub → dépôt `arcade-d/kitt` → onglet **Actions** → dernier run **ci** sur `main` (vert).
2. Section **Artifacts** → **`kitt-debug-apk`** (~73 Mo zippé) → télécharger, dézipper.
3. Tu obtiens `app-arm64-v8a-debug.apk` (~175 Mo, arm64 = Pixel 7).

## Installer (Pixel 7, Android 15)

```bash
adb install -r app-arm64-v8a-debug.apk
```
(ou transférer le fichier et l'ouvrir sur le téléphone, sources inconnues autorisées).

L'app s'appelle **KITT** (id `co.delfour.kitt`), icône custom.

## Premier lancement

- Au démarrage, si les modèles ne sont pas présents, un **écran de téléchargement**
  récupère **~2–3 Go** : STT (zipformer FR), TTS (Piper FR **masculine** « gilles »),
  cerveau **CroissantLLM** (GGUF). **Reste en Wi‑Fi.** Une seule fois.
- Ensuite l'app demande la **permission micro** au premier appui.

## Utiliser (push-to-talk — base fiable)

**Maintiens le bouton micro → parle → relâche.** KITT transcrit (STT), réfléchit
(CroissantLLM avec la persona custom), puis **répond à la voix** (voix FR masculine
+ **filtre KITT** : grave + radio + synthétique) sur le **haut-parleur**.

## Ce qui est livré

- **Identité** : KITT / `co.delfour.kitt`, icône, perms micro+réseau, minSdk 26 / target 35.
- **Persona custom** (`assets/persona/kitt_fr.md`) : intelligence embarquée transférée dans le téléphone.
- **Push-to-talk réel** : capture micro maintien-pour-parler → pipeline STT→LLM→TTS→HP.
- **Onboarding** des modèles (téléchargement repris, progression).
- **Voix FR masculine** (Piper gilles) + **filtre KITT** (décorateur TTS, DSP pur testé).
- **CI** : build APK debug arm64 (`--split-per-abi`, adapters réels) + artefact `kitt-debug-apk`.
- Pipeline vocal **100 % local**, pas de cloud, pas de clé, pas de Firebase.

## Expérimental / non activé

- **Wake-word « KITT »** : la **fondation sherpa-onnx `KeywordSpotter`** est codée
  (`lib/adapters/sherpa/sherpa_wake_word.dart`, **pas** Porcupine/Picovoice) mais
  **non câblée** (le push-to-talk reste la base fiable, comme demandé). Pour l'activer :
  fournir un **modèle KWS transducer** (encoder/decoder/joiner.onnx + tokens.txt), le
  mot-clé « KITT » **tokenisé** pour ce modèle, brancher `wakeWordProvider` sur
  `SherpaWakeWord`, et câbler la boucle `idle → (KITT détecté) → écoute`. ⚠️ L'écoute
  continue du wake-word et la capture push-to-talk se disputent le micro : n'en activer
  qu'une à la fois. (Aucun modèle KWS FR « KITT » prêt-à-l'emploi confirmé — à sourcer.)

## Caveats connus

- **Taille** : APK **debug** ~175 Mo (kernel debug + libs natives llama.cpp/onnxruntime).
  Un build **release** (AOT) serait bien plus petit — hors périmètre (debug demandé).
- **Signature** : debug uniquement (pas de release signing).
- **Warning Gradle** : `audio_session` / `record_android` utilisent l'ancien Kotlin
  Gradle Plugin — **avertissement amont, non bloquant** (build OK).
- **Warning CI** : actions GitHub sur Node 20 (déprécié le 2026-06-16) — non bloquant ;
  à re-tagger plus tard quand les actions publieront des versions Node 24.
- **STT sans score de confiance** (zipformer) : l'abstention « fais répéter » par seuil
  n'est pas active.
- **Bluetooth / autoradio / ducking** : plus tard (haut-parleur suffisant pour demain).

## Tuning rapide (sans toucher à l'archi)

- **Personnalité** : éditer `assets/persona/kitt_fr.md`.
- **Voix KITT (filtre)** : coefficients dans `lib/adapters/audio/kitt_filter.dart`
  (grave/low-pass, ring-mod, drive saturation).
- **Voix de base** : modèle Piper dans `lib/adapters/models/model_catalog.dart`.
- **Réponses LLM** : `GenerationParams` (maxTokens/temp…) dans `lib/adapters/llama/llama_croissant_llm.dart`.

## Tester en mock (sans device/modèles)

`flutter test` (50 tests) tourne en **mock** par défaut. L'APK est buildé en réel
via `--dart-define=KITT_ADAPTERS=real`. Pour lancer l'UI en mock sur un poste :
`flutter run` (réponses déterministes, sans modèles).
