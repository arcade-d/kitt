# KITT

Compagnon vocal local inspiré de K2000 — app téléphone Flutter, pipeline vocal
**100 % on-device**, réutilisant les briques de [Tachikoma](docs/DEBRIEF.md).

> Wake-word « KITT » → STT → contexte/mémoire → LLM (persona) → TTS → audio (Bluetooth).
> Privé, offline, avec une vraie continuité conversationnelle.

Le document de référence complet (vision, décisions, architecture, inventaire
Tachikoma, roadmap) est dans [`docs/DEBRIEF.md`](docs/DEBRIEF.md).

## État du dépôt

Premier jet : **squelette domaine + ports & adapters MOCK**, machine d'états,
persona externalisée, UI Flame (scanner K2000 + modulateur), CI. Aucune
intégration des moteurs réels (STT/LLM/TTS) pour l'instant — ce sont des mocks
déterministes qui exercent tout le pipeline.

## Architecture (hexagonale / ports & adapters)

```
lib/
├─ domain/         Turn, ConversationManager, ContextBuilder, Persona, DialoguePolicy
├─ application/    machine d'états, CompanionPipeline (orchestration), providers Riverpod
├─ ports/          interfaces : WakeWord, Stt, Llm, Tts, AudioOut, AudioIn, MemoryStore
├─ adapters/       implémentations (mock/, memory/) ; les adapters Tachikoma viendront ici
├─ ui/             écran companion (Flame) : scanner + modulateur
└─ main.dart
assets/persona/    system prompt + règles de KITT (FR)
docs/DEBRIEF.md    débrief technique & handoff (référence)
```

Chaque étage du pipeline est un **port** (interface Dart) avec un **adapter**.
Brancher les vrais moteurs = remplacer les providers dans
`lib/application/providers.dart` par les adapters Tachikoma, sans toucher au
domaine.

## Développement

```bash
flutter pub get
flutter test          # tests domaine + pipeline (mocks)
flutter analyze
dart format .
flutter run           # app (UI Flame + bouton « maintenir pour parler »)
```

## Ce qui reste à écrire (cf. débrief §9)

- **Wake-word** « KITT » (absent de Tachikoma) — Porcupine / `sherpa_onnx KeywordSpotter`.
- **Adapters réels** STT/LLM/TTS via extraction d'un package `tachikoma_voice`.
- **TTS streaming par phrase**, **routage Bluetooth + ducking** (`audio_session`).
- **Résumé glissant** (mémoire de travail) et **abstention par confiance**
  (nécessite un STT exposant un score).
- **Mémoire long terme SQLite** (+ dédup/TTL) en remplacement du KV.
