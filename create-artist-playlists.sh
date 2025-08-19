#!/bin/bash

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

# Create the playlist directory if it doesn't exist
mkdir -p "$PLAYLIST_DIR"

# Change to the music directory to get relative paths
cd "$MUSIC_DIR" || exit 1

# Create a temporary directory for new playlists
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Find all mp3 files, extract the artist tag, and create playlists
find . -type f -name "*.mp3" | while read -r file; do
    # Use mid3v2 (from python-mutagen) to get the artist tag
    artist=$(mid3v2 -l "$file" | grep -i "TPE1\|TP1" | awk -F= '{print $2}' | head -n1)

    # If the artist tag is empty, skip or set to "Unknown"
    if [[ -z "$artist" ]]; then
        artist="Unknown_Artist"
    fi

    # Clean the artist name for use as a filename (remove slashes, spaces, etc.)
    clean_artist=$(echo "$artist" | tr '/' '_' | tr ' ' '_' | tr -d ':')

    # Remove the ./ prefix from the filename
    filename="${file#./}"
    
    # Append the filename to the artist's playlist file in the temp directory
    echo "$filename" >> "$TEMP_DIR/${clean_artist}.m3u"
done

# Now replace only the artist playlists in the destination
echo "Updating artist playlists..."
for playlist in "$TEMP_DIR"/*.m3u; do
    playlist_name=$(basename "$playlist")
    mv -f "$playlist" "$PLAYLIST_DIR/$playlist_name"
    echo "Updated: $playlist_name"
done

# Clean up temporary directory
rm -rf "$TEMP_DIR"

echo "Artist playlists updated in: $PLAYLIST_DIR"
