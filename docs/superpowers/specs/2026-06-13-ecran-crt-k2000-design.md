# Spec — Écran KITT « moniteur CRT bi-chrome » années 80 / K2000

Date : 2026-06-13
Statut : design validé (brainstorming + compagnon visuel), prêt pour plan.

## Contexte

L'écran companion actuel (`CompanionScreen` + `KittGame` Flame) est un MVP visuel :
fond noir, un blob rouge qui balaie (ping-pong sinus), 24 barres ambre réactives
au micro, label d'état ambre, bouton micro rouge. Le débrief (D7) prévoyait déjà
« cockpit / CRT plus tard ». On réalise cette montée en gamme.

## Décisions (issues du compagnon visuel)

- **Direction C — Moniteur CRT phosphore** : gros écran cathodique central
  (grille, courbure simulée, glow, vignette, scanlines), scanner réduit à un bandeau.
- **Traitement 2 — Bi-chrome K2000** : **voicebox ambre** dans le CRT +
  **Larson rouge segmenté** en bandeau + accents rouges. (Ambre = voix, rouge =
  scanner — fidèle à l'identité K2000.)
- **Transcript dans le CRT** : oui (effet téléscripteur rétro).
- **Séquence de boot « K.I.T.T. SYSTEMS ONLINE »** : oui (bootstrap + download).

Palette : rouge `#FF1A1A` (scanner/accents), ambre `#FFB000` (voix/texte), fond
noir + glow. Police : mono + letter-spacing par défaut (zéro asset) ; option
police LCD/7-seg dédiée (`assets/fonts/`) en amélioration ultérieure.

## Objectifs

1. Transformer l'écran companion en moniteur CRT bi-chrome vivant, piloté par
   l'état du pipeline.
2. Afficher en CRT : oscilloscope (voicebox), scanner Larson, label d'état,
   et **transcript** (ce que KITT a compris + sa réponse).
3. Habiller l'écran de démarrage/téléchargement d'une séquence de boot K2000.
4. Bonnes perfs sur Pixel 7 (Flame + `CustomPaint`, gradients/shaders, pas
   d'images lourdes).

## Non-objectifs

- Modifier le **pipeline vocal**, la machine d'états ou les **ports** (aucun
  changement de contrat). On ajoute seulement 2 expositions **read-only** de
  signaux déjà calculés (voir ci-dessous).
- TTS streaming (reste synthèse en bloc).

## Architecture

### Composants Flame (`lib/ui/`, refactor de `companion_game.dart`)

- **`CrtComponent`** — l'écran cathodique : fond radial ambre, grille phosphore
  masquée en ellipse, vignette (inset shadow), scanlines, glow. Cadre commun.
- **`LarsonScannerComponent`** — bandeau **rouge segmenté** (~8 cellules) avec
  traînée qui s'estompe ; vitesse selon l'état (réutilise la logique `_speed`
  actuelle : idle lent, listening/clarifying attentif, thinking rapide,
  responding modéré).
- **`VoiceboxComponent`** — oscilloscope **ambre** dans le CRT (remplace les 24
  barres). Waveform pilotée :
  - `listening` → niveau micro (`audioLevelProvider`, déjà dispo) ;
  - `responding` → **niveau de sortie TTS** (nouveau signal, voir Données) ;
  - `idle` → ligne quasi-plate ; `thinking` → balayage/bruit animé.
- **`TranscriptComponent`** — texte ambre dans le CRT, effet machine à écrire :
  ligne « utilisateur » (utterance reconnue) + réponse de KITT en flux.
- **Overlay CRT** (scanlines + vignette + glow) rendu au-dessus des composants.

### Comportement par état

| État | Scanner | Voicebox | Transcript | Label |
|---|---|---|---|---|
| `idle` | lent | ligne plate | dernier échange estompé | EN VEILLE — dites « KITT » |
| `listening` | rapide | waveform micro live | — | À L'ÉCOUTE… |
| `thinking` | ping-pong rapide | balayage/bruit | utterance reconnue affichée | RÉFLEXION… |
| `responding` | modéré | waveform TTS | réponse en téléscripteur | KITT RÉPOND… |
| `clarifying` | flash | pulsation ambre | « ? » | PARDON ? |

### Séquence de boot (écrans `bootstrap_gate.dart` / `model_download_screen.dart`)

Thème CRT + animation de démarrage : scanlines, montée du scanner, texte 7-seg
`K.I.T.T. SYSTEMS ONLINE`, puis bascule normale. Le download LLM (restant)
s'affiche dans ce même cadre (barre ambre + texte CRT).

## Données (ajouts minimes, read-only)

Le pipeline expose **déjà** : `states` (état) et `partialResponse` (tokens de
KITT → téléscripteur de la réponse). À ajouter dans `CompanionPipeline`
(application, sans toucher aux ports) :

1. **Utterance reconnue** — exposer `heard.text` (ex. `Stream<String> userHeard`)
   pour la ligne « utilisateur » du transcript.
2. **Niveau de sortie TTS** — calculer une **enveloppe RMS** sur le PCM
   synthétisé (déjà en mémoire dans `runTurn`) et l'émettre (ex.
   `Stream<double> outputLevel`) synchronisée sur la durée de lecture
   (durée = samples / sampleRate) pour animer la voicebox en `responding`.
   MVP acceptable si approximé par une enveloppe pré-calculée jouée sur la durée.

Côté UI : nouveaux providers (`userHeardProvider`, `outputLevelProvider`) sur le
modèle des providers existants, pontés vers des `ValueNotifier` consommés par le
jeu Flame (comme `_state` / `_level` aujourd'hui).

## Gestion d'erreurs / dégradations

- Si `outputLevel` n'est pas branché (ex. tests/mock) → voicebox retombe sur une
  animation synthétique (pas de crash).
- Transcript borné (n dernières lignes) pour éviter une croissance mémoire.
- Aucune dépendance réseau ; tout est rendu local.

## Tests

- **Widget/golden** (si dispo en CI) : rendu de l'écran par état (5 états) en
  mode mock → snapshots stables.
- **Unitaire** : mapping état → paramètres visuels (vitesse scanner, mode
  voicebox) extrait en fonctions pures testables.
- **Unitaire pipeline** : `userHeard` émet l'utterance ; `outputLevel` émet une
  enveloppe non vide quand `synthesize` renvoie du PCM (avec TTS mock).
- Tests existants du pipeline/état conservés (comportement inchangé).

## Questions ouvertes

- Courbure CRT : simulée en CSS-like (border-radius/mask) côté Flame via
  `CustomPainter` — à valider visuellement sur device (vs shader fragment).
- Police 7-seg : rester en mono (zéro asset) pour la v1, ou embarquer une police
  LCD libre (`assets/fonts/`) ? (Amélioration, non bloquante.)
- Animation `responding` : enveloppe TTS réelle vs synthétique pour la v1.
