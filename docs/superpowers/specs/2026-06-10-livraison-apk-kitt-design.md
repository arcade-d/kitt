---
title: Livraison APK KITT — push-to-talk + identité + voix/persona + CI artefact (+ wake-word bonus)
status: approved (directive utilisateur autonome 2026-06-10 soir)
created_at: 2026-06-10
références: messages utilisateur 2026-06-10 ; specs adapters réels + LLM CroissantLLM
---

# Spec — Livraison APK debug « KITT »

> Objectif : un **APK debug installable** sur Pixel 7 (Android 15) où le
> **push-to-talk** fonctionne de bout en bout (capture micro → STT → CroissantLLM
> avec persona → TTS FR masculine + filtre KITT → haut-parleur), packagé sous
> l'identité KITT, avec téléchargement des modèles à l'usage, et **produit par la
> CI en artefact téléchargeable**. Wake-word sherpa-onnx en **bonus** si le temps
> le permet. Directive utilisateur : exécution **autonome**, merge sur `main`
> autorisé.

## Contraintes de vérification

L'inférence native (sherpa, llamadart) et l'APK **ne sont pas exécutables sur
l'hôte de dev**. Vérification : `flutter analyze` + tests de **logique pure** +
**build APK par la CI** (artefact). Le test device/end-to-end est fait par
l'utilisateur sur Pixel 7. Les lots « UI/câblage » sont donc livrés correct-par-
construction + analyze, non testés end-to-end ici.

## Décisions (directive utilisateur)

| Sujet | Décision |
|---|---|
| Livrable | (a) **push-to-talk** fiable pour demain ; (b) wake-word local sherpa **bonus** si temps. |
| Nom app | **KITT** |
| Application ID | **co.delfour.kitt** (remplace `dev.levilainpetit.kitt`) |
| Icône | Fournie dans `_resources` — **absente au moment du dev** → placeholder généré + config `flutter_launcher_icons` ; à remplacer par l'icône réelle puis re-générer. |
| Wake-word | **sherpa-onnx KeywordSpotter** mot-clé « KITT », **local only**, **pas** de Porcupine/Picovoice, **pas** de clé/cloud. Fallback bouton **obligatoire**. |
| Sortie audio | Haut-parleur du téléphone (Bluetooth/ducking plus tard). |
| Cible | Pixel 7, Android 15 (API 35), 8 Go RAM. minSdk 26. |
| Git | PRs si possible, **merge sur main autorisé** (autonome). |
| Crashlytics/Firebase | **Aucun** pour l'instant. |
| Signature | **Debug APK**. |
| Persona | `_resources/persona.md` **custom** → devient l'asset persona de KITT. |
| Voix | **Piper FR masculine** (sherpa VITS) — remplace siwis (féminine). |
| Effet audio | **Filtre KITT** : grave + radio (bandpass) + synthétique. |
| CI | GitHub Actions : build APK debug **+ upload artefact mis en avant**. |

## Lots (ordre de priorité)

1. **Identité & packaging & permissions** : applicationId/namespace `co.delfour.kitt`,
   label « KITT », `RECORD_AUDIO` + `INTERNET` au manifeste, minSdk 26 / target+compile 35,
   config `flutter_launcher_icons` (+ placeholder si icône absente).
2. **Persona custom** : `_resources/persona.md` → `assets/persona/kitt_fr.md`.
3. **Capture micro + push-to-talk réel** : remplacer le stub `_onTalk` par une vraie
   capture maintien-pour-parler (RecordAudioIn : appui → accumulation des samples →
   relâche → `runTurn`), demande de permission micro, état UI piloté par le pipeline.
4. **Onboarding/téléchargement des modèles** : au lancement, si modèles absents
   (`ModelManager.getStatus()`), écran de téléchargement (STT/TTS + GGUF LLM) avec
   progression, puis companion. Mode réel par défaut dans l'APK.
5. **CI APK artefact** : build `flutter build apk --debug --dart-define=KITT_ADAPTERS=real`
   + `actions/upload-artifact` mis en avant (nom clair, rétention).
6. **Voix Piper FR masculine** : remplacer le modèle TTS du catalogue par une voix
   masculine FR (modèle Piper dispo sur HF), MAJ checks de disponibilité.
7. **Filtre audio KITT** : DSP pur (grave/low-shelf + bandpass radio + légère
   modulation synthétique) appliqué au PCM TTS avant lecture. **Testable** (pur).
8. **(Bonus) Wake-word sherpa KeywordSpotter** : adapter `SherpaWakeWord` derrière
   `WakeWordPort` (mot-clé « KITT », local), modèle KWS au catalogue/onboarding,
   câblage pipeline idle→listening, fallback bouton conservé.

## Critères d'acceptation (livrable minimal = lots 1–5)

1. APK debug se construit en CI et est **téléchargeable en artefact** (nom explicite).
2. Installé : l'app s'appelle **KITT**, id `co.delfour.kitt`, demande le micro.
3. Au 1er lancement sans modèles : écran de téléchargement → modèles récupérés.
4. **Push-to-talk** : maintenir le bouton → parler → relâcher → KITT répond à la voix
   (persona custom, voix FR masculine, filtre KITT) sur le haut-parleur.
5. `flutter analyze` 0 issue, `flutter test` vert (logique pure), `dart format` clean.
6. Aucun poids de modèle ni clé/cloud committé ; pas de Firebase.

Lots 6–7 améliorent l'expérience ; lot 8 (wake-word) est un bonus.
