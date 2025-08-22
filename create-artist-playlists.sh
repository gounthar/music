#!/bin/bash

# Fail fast and make parsing safer
set -euo pipefail
IFS=$'\n\t'

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    ensure_deps python3 pip mid3v2 || { echo "Missing dependencies (python3/pip/mid3v2). Aborting." >&2; exit 1; }
    add_user_local_bin_to_path
fi

# Global defaults (can be overridden by env or args)
FLAT_DIR="${FLAT_DIR:-/mnt/c/Users/User/Music/Bonneville}"
MUSIC_DIR="${1:-${MUSIC_DIR:-$FLAT_DIR}}"
PLAYLIST_DIR="${2:-${PLAYLIST_DIR:-$MUSIC_DIR}}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [MUSIC_DIR] [PLAYLIST_DIR]"
  echo "Defaults: MUSIC_DIR defaults to \$FLAT_DIR or \$MUSIC_DIR if set; PLAYLIST_DIR defaults to MUSIC_DIR unless \$PLAYLIST_DIR is set"
  exit 0
fi

if [[ ! -d "$MUSIC_DIR" ]]; then
  echo "Error: MUSIC_DIR does not exist: $MUSIC_DIR" >&2
  exit 1
fi

# Check for required tools
if ! command -v mid3v2 >/dev/null 2>&1; then
  echo "Error: mid3v2 (from python-mutagen) is required. Try: sudo apt-get install mutagen-tools"
  exit 1
fi

# Create the playlist directory if it doesn't exist
mkdir -p "$PLAYLIST_DIR"

# Change to the music directory to get relative paths
cd "$MUSIC_DIR" || { echo "Failed to change directory to: $MUSIC_DIR" >&2; exit 1; }

# Create a temporary directory for new playlists
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Find all mp3 files (case-insensitive), extract the artist tag, and create playlists
find . -type f -iname "*.mp3" -print0 | while IFS= read -r -d '' file; do
    # Use mid3v2 (from python-mutagen) to get the artist tag
    artist=$({ mid3v2 -l "$file" \
      | grep -Eaim1 '^(TPE1|TP1)=' \
      | awk -F= '{print $2}' \
      | sed -e 's/\r$//' -e 's/^[[:space:]]\+//' -e 's/[[:space:]]\+$//' \
      || true; })

    # If the artist tag is empty, skip or set to "Unknown"
    if [[ -z "$artist" ]]; then
        artist="Unknown_Artist"
    fi

    # Clean the artist name for use as a filename (Windows-safe when writing to /mnt/c)
    # - replace / and \ with _
    # - replace spaces with _
    # - strip invalid Windows filename characters: : * ? " < > |
    clean_artist=$(printf '%s' "$artist" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e "s/['\",\\/:*?<>|]/_/g" -e 's/[[:space:]]\+/_/g' -e 's/_\+/_/g')
    # Avoid reserved device names on Windows
    case "$clean_artist" in
      CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]) clean_artist="${clean_artist}_" ;;
    esac

    # Remove the ./ prefix from the filename
    filename="${file#./}"
    
    # Append the filename to the artist's playlist file in the temp directory
    echo "$filename" >> "$TEMP_DIR/${clean_artist}.m3u"
done

# Now replace only the artist playlists in the destination
echo "Updating artist playlists..."
if compgen -G "$TEMP_DIR/*.m3u" > /dev/null; then
  # Normalize each playlist before moving
  for f in "$TEMP_DIR"/*.m3u; do
      LC_ALL=C sort -u -o "$f" "$f"
  done
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
