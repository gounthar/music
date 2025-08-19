#!/bin/bash

# Fail fast and make parsing safer
set -euo pipefail
IFS=$'\n\t'

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    add_user_local_bin_to_path
    ensure_deps python3 pip mid3v2
fi

# Define your music directory and playlist output directory
MUSIC_DIR="${1:-/mnt/c/Users/User/Music/mp3/result}"
PLAYLIST_DIR="${2:-/mnt/c/Users/User/Music/mp3/result}"

# Check for required tools
if ! command -v mid3v2 >/dev/null 2>&1; then
  echo "Error: mid3v2 (from python-mutagen) is required. Try: sudo apt-get install mutagen-tools"
  exit 1
fi

# Create the playlist directory if it doesn't exist
mkdir -p "$PLAYLIST_DIR"

# Change to the music directory to get relative paths
cd "$MUSIC_DIR" || { echo "Error: MUSIC_DIR not found or not accessible: $MUSIC_DIR"; exit 1; }

# Create a temporary directory for new playlists
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Find all mp3 files (case-insensitive), extract the artist tag, and create playlists
find . -type f -iname "*.mp3" -print0 | while IFS= read -r -d '' file; do
    # Use mid3v2 (from python-mutagen) to get the artist tag
    artist=$(mid3v2 -l "$file" | grep -Ei "TPE1|TP1" | awk -F= '{print $2}' | head -n1)

    # If the artist tag is empty, skip or set to "Unknown"
    if [[ -z "$artist" ]]; then
        artist="Unknown_Artist"
    fi

    # Clean the artist name for use as a filename (Windows-safe when writing to /mnt/c)
    # - replace / and \ with _
    # - replace spaces with _
    # - strip invalid Windows filename characters: : * ? " < > |
    clean_artist=$(printf '%s' "$artist" | tr '/\\' '__' | tr ' ' '_' | tr -d ':*?"<>|')

    # Remove the ./ prefix from the filename
    filename="${file#./}"
    
    # Append the filename to the artist's playlist file in the temp directory
    echo "$filename" >> "$TEMP_DIR/${clean_artist}.m3u"
done

# Now replace only the artist playlists in the destination
echo "Updating artist playlists..."
if compgen -G "$TEMP_DIR/*.m3u" > /dev/null; then
  for playlist in "$TEMP_DIR"/*.m3u; do
      playlist_name=$(basename "$playlist")
      mv -f "$playlist" "$PLAYLIST_DIR/$playlist_name"
      echo "Updated: $playlist_name"
  done
else
  echo "No artist playlists to update."
fi

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo "Artist playlists updated in: $PLAYLIST_DIR"
