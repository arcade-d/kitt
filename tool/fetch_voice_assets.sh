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
mv "$SRC/tokens.txt" "$STAGE/tts/tokens.txt"
mv "$SRC/espeak-ng-data" "$STAGE/tts/espeak-ng-data"

# --- Archive finale : tar NON compressé (l'APK zippe déjà) ---
mkdir -p "$ROOT/assets/models"
tar -cf "$OUT" -C "$STAGE" stt tts

# --- Vérif : fichiers sentinelles attendus par les adapters ---
# On liste une seule fois dans un fichier puis on grep ce fichier : pas de
# pipe `tar | grep -q` (qui, sous `pipefail`, peut faire échouer la vérif via
# le SIGPIPE reçu par tar quand grep -q sort au premier match).
listing="$STAGE/listing.txt"
tar -tf "$OUT" >"$listing"
for need in \
  stt/encoder.onnx stt/decoder.onnx stt/joiner.onnx stt/tokens.txt \
  tts/model.onnx tts/tokens.txt \
  tts/espeak-ng-data/fr_dict tts/espeak-ng-data/phontab; do
  grep -qxF "$need" "$listing" || {
    echo "MANQUE dans voice.tar: $need" >&2
    exit 1
  }
done
echo "OK: $OUT ($(du -h "$OUT" | cut -f1))"
