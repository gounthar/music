#!/bin/bash

# Check if beets is installed
if ! command -v beet &> /dev/null; then
    echo "Installing beets..."
    pip install beets beets[fetchart,lyrics,lastgenre,discogs]
fi

# Set directories
MUSIC_SOURCE="/mnt/c/Users/User/Music/to-sort"
OUTPUT_DIR="/mnt/c/Users/User/Music/lossless"

# Create non-interactive config
CONFIG_FILE="$HOME/.config/beets/config.yaml"
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOL
directory: $OUTPUT_DIR
paths:
    default: \$artist/\$album/\$track \$title
    singleton: Non-Album/\$artist/\$title
    comp: Compilations/\$album/\$track \$title
plugins: fetchart lyrics lastgenre discogs

import:
    move: yes
    quiet: yes
    timid: no           # Disable all prompts
    autotag: yes        # Auto-tag high-confidence matches
    resume: no          # Don't ask to resume
    skip_errors: yes    # Skip files with errors

# Non-interactive behavior for unmatched files
unmatched:
    quiet: yes          # Silence "no match" warnings

# Discogs token (replace with yours)
discogs:
    token: YOUR_DISCOGS_TOKEN
EOL

# Run import (fully non-interactive)
beet import -A "$MUSIC_SOURCE"  # -A: auto-apply matches

echo "Music organized in: $OUTPUT_DIR"