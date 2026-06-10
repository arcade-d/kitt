# CLAUDE.md — KITT

Repère de session pour Claude Code. Le **document de référence** est
[`docs/DEBRIEF.md`](docs/DEBRIEF.md) (vision, décisions D1–D7, architecture,
inventaire Tachikoma, roadmap, questions ouvertes). Lis-le avant toute décision
d'archi.

## Nature du projet

App **Flutter/Dart**, Android, pipeline vocal **on-device** inspiré de K2000.
Réutilise les briques de **Tachikoma** (app Flutter mono-package — pas de Rust,
pas de FFI) : STT `sherpa_onnx` (zipformer FR streaming), TTS `sherpa_onnx`
(VITS/Piper FR). **LLM : choix KITT = CroissantLLM via `llamadart` (GGUF
Q4_K_M, FR natif)** — divergence assumée : Tachikoma a depuis migré vers
Gemma 4 (`flutter_gemma`, LiteRT-LM). **Whisper et XTTS ne sont PAS utilisés.**

## Conventions

- Archi **hexagonale / DDD**, ports & adapters ; CQRS où pertinent.
- État : **Riverpod**. Identifiants : **ULID**. Rendu animé : **Flame**.
- Le **domaine** (`lib/domain`, `lib/application`) ne dépend d'aucun moteur :
  il parle aux **ports** (`lib/ports`). Les moteurs sont des **adapters**.
- Persona **externalisée** dans `assets/persona/` — jamais en dur dans le code.
- **Ne jamais committer les poids** de modèles (`*.gguf`, `*.onnx`) — mockés en
  test, récupérés en CI/runtime via un futur `ModelManager`.

## État actuel (premier jet)

- Domaine complet + machine d'états (`idle/listening/thinking/responding/clarifying`).
- Ports définis. Adapters **mock** (`lib/adapters/mock`, `memory`) + **réels**
  `lib/adapters/{sherpa,audio,models}` (STT/TTS sherpa, audio record/just_audio,
  ModelManager) ; bascule `--dart-define=KITT_ADAPTERS=real|mock` (défaut mock).
- `CompanionPipeline` orchestre un tour bout-en-bout sur les mocks.
- UI Flame minimale (scanner + modulateur) + bouton repli.
- CI GitHub Actions (`flutter analyze` + `test` + build APK de fumée).

## Prochaines étapes (roadmap §9)

1. Extraire `tachikoma_voice` et brancher les adapters réels STT/LLM/TTS.
2. Wake-word « KITT ».
3. TTS streaming par phrase + routage Bluetooth/ducking.
4. Résumé glissant, abstention par confiance, mémoire SQLite.

## Environnement

Pas de toolchain Flutter/Dart garantie en session web → s'appuyer sur la **CI**
pour `analyze`/`test`/format. Branche de dev : `claude/empty-repo-debrief-qerjf9`.
