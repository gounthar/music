#!/usr/bin/env bash
set -euo pipefail

# Defaults (can be overridden by environment)
LOSSLESS_DIR="${LOSSLESS_DIR:-/mnt/c/Users/User/Music/lossless}"
MUSIC_ROOT="${MUSIC_ROOT:-$LOSSLESS_DIR}"
MP3_ROOT="${MP3_ROOT:-/mnt/c/Users/User/Music/mp3-test}"

export LOSSLESS_DIR MUSIC_ROOT MP3_ROOT
export VERBOSE=true DRY_RUN=false DELETE_ORIGINAL_MP3=false CONVERT_PARALLEL=false

# Select a single test file from supported extensions
SINGLE_FILE=""
for ext in flac alac wav aiff ape wv; do
  f=$(find "$LOSSLESS_DIR" -type f -name "*.${ext}" -print -quit || true)
  if [[ -n "${f:-}" ]]; then
    SINGLE_FILE="$f"
    break
  fi
done

echo "Testing SINGLE_FILE: ${SINGLE_FILE:-<none>}"
if [[ -z "${SINGLE_FILE:-}" ]]; then
  echo "No matching lossless file under: $LOSSLESS_DIR" >&2
  exit 1
fi

export SINGLE_FILE
bash organize-music-enhanced.sh
