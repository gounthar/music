#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    ensure_deps python3 pip beet fpcalc acoustid || { echo "Missing dependencies (python3/pip/beet/fpcalc/acoustid)" >&2; exit 1; }
    add_user_local_bin_to_path

    # Ensure pyacoustid is installed in the same Python environment as 'beet'
    if command -v beet >/dev/null 2>&1; then
        BEET_EXE="$(command -v beet)"
        PY_INTERP=""
        if head -n1 "$BEET_EXE" | grep -q '^#!'; then
            # Read and parse shebang interpreter safely
            SHEBANG_LINE="$(head -n1 "$BEET_EXE" | sed 's/^#!//')"
            # Tokenize into words
            read -r -a _tok <<<"$SHEBANG_LINE"
            FIRST="${_tok[0]:-}"
            SECOND="${_tok[1]:-}"
            # If using /usr/bin/env, pick the second token (the interpreter); else pick the first
            if [ "$(basename "${FIRST:-}" 2>/dev/null)" = "env" ] && [ -n "$SECOND" ]; then
                PY_INTERP="$SECOND"
            else
                PY_INTERP="$FIRST"
            fi
        fi
        # Trim whitespace and fallback
        PY_INTERP="$(echo "${PY_INTERP:-}" | awk '{$1=$1;print}')"
        if [ -z "$PY_INTERP" ]; then
            PY_INTERP="python3"
        fi
        # Detect virtualenv; use --user only when not in venv to avoid permission issues
        if "$PY_INTERP" -c "import sys; print(getattr(sys, \"base_prefix\", sys.prefix) != sys.prefix)" | grep -q 'True'; then
            "$PY_INTERP" -m pip install -U pyacoustid || true
        else
            "$PY_INTERP" -m pip install -U --user pyacoustid || true
        fi
    fi
fi


# Global defaults (can be overridden by env)
TO_SORT_DIR="${TO_SORT_DIR:-/mnt/c/Users/User/Music/to-sort}"
LOSSLESS_DIR="${LOSSLESS_DIR:-/mnt/c/Users/User/Music/lossless}"
MUSIC_SOURCE="${MUSIC_SOURCE:-$TO_SORT_DIR}"
OUTPUT_DIR="${OUTPUT_DIR:-$LOSSLESS_DIR}"

# Create non-interactive config
CONFIG_FILE="${BEETS_CONFIG_FILE:-$HOME/.config/beets/config.yaml}"
if [ ! -f "$CONFIG_FILE" ]; then
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOL
# ~/.config/beets/config.yaml
directory: $OUTPUT_DIR
library: ~/.config/beets/musiclibrary.db

import:
    write: yes
    move: yes
    resume: no
    incremental: yes

# Plugins: enable acoustic fingerprinting (chroma) plus fetchart, lyrics, lastgenre, discogs
plugins: chroma fetchart lyrics lastgenre discogs

acoustid:
    apikey: YOUR_ACOUSTID_API_KEY

fetchart:
    auto: yes
    minwidth: 0

lyrics:
    auto: yes
    sources: genius musixmatch google

# Chroma plugin for acoustic fingerprinting (AcoustID)
chroma:
    auto: yes

# Optional: AcoustID API key (recommended for better lookups)
# acoustid:
#     apikey: YOUR_ACOUSTID_API_KEY

# LastGenre plugin for better genre detection
lastgenre:
    auto: yes           # Automatically fetch genres during import
    source: album       # Use album-level genre information
    count: 3            # Get up to 3 genres per track
    separator: ', '     # Separate multiple genres with commas
    canonical: yes      # Use canonical genre names
    fallback: Unknown_Genre
    min_weight: 10      # Minimum weight threshold for genres

# Optional: MusicBrainz integration for better metadata
musicbrainz:
    genres: yes

paths:
    default: \$artist/\$album/\$track \$title
    singleton: Non-Album/\$artist/\$title
    comp: Compilations/\$album/\$track \$title

# Discogs token (replace with yours)
discogs:
    token: YOUR_DISCOGS_TOKEN
EOL
else
    echo "Beets config already exists at: $CONFIG_FILE — leaving it unchanged."
fi

# Run import (fully non-interactive)
beet import -A "$MUSIC_SOURCE"  # -A: auto-apply matches

echo "Music organized in: $OUTPUT_DIR"
