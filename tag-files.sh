#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    ensure_deps python3 pip beet || { echo "Missing dependencies (python3/pip/beet)" >&2; exit 1; }
    add_user_local_bin_to_path
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
    move: no
    resume: no
    incremental: yes

# Updated plugins - removed acousticbrainz, added lastgenre
plugins: fetchart lyrics lastgenre discogs

fetchart:
    auto: yes
    minwidth: 0

lyrics:
    auto: yes
    sources: genius musixmatch google

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
