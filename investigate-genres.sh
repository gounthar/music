#!/bin/bash
set -euo pipefail

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    add_user_local_bin_to_path
    ensure_deps python3 pip beet mid3v2 exiftool
fi

# Global defaults (can be overridden by env or args)
FLAT_DIR="${FLAT_DIR:-/mnt/c/Users/User/Music/Bonneville}"
TARGET_DIR="${1:-${TARGET_DIR:-$FLAT_DIR}}"
cd "$TARGET_DIR" || exit 1

# 1. Check what genre playlists actually exist
echo "Genre playlists found:"
ls -la genre_*.m3u 2>/dev/null || echo "No genre playlists found"
echo ""

# 2. Check the content of a few genre playlists
if [ -f "genre_Unknown_Genre.m3u" ]; then
    echo "Unknown_Genre playlist sample:"
    cat "genre_Unknown_Genre.m3u"
    echo ""
fi

# 3. Check what genres beets is actually finding for some files
echo "Testing genre extraction on a few files:"
max=${MAX_SAMPLES:-5}
count=0
find . -maxdepth 1 -type f -iname "*.mp3" -print0 | while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    printf '%s: ' "$filename"
    # shellcheck disable=SC2016
    genre_out=$(beet list path:"$(realpath "$file")" -f '$genre' 2>/dev/null || true)
    if [[ -n "$genre_out" ]]; then
        echo "$genre_out"
    else
        echo "No genre found in beets"
    fi
    count=$((count + 1))
    (( count >= max )) && break
done
echo ""

# 4. Check if files have multiple genres in their ID3 tags
echo "Checking ID3 tags for multiple genres:"
find . -maxdepth 1 -iname "*.mp3" -print0 | while IFS= read -r -d '' file; do
    filename=$(basename "$file")
    echo -n "$filename: "
    if command -v mid3v2 &> /dev/null; then
        mid3v2 -l "$filename" | grep -ai "TCON" || echo "No genre tag found"
    elif command -v exiftool &> /dev/null; then
        exiftool -b -Genre "$filename" || echo "No genre tag found"
    else
        echo "No tag tool available"
    fi
done
echo ""

# 5. Count entries in each genre playlist
echo "Genre playlist sizes:"
for playlist in genre_*.m3u; do
    if [ -f "$playlist" ]; then
        count=$(wc -l < "$playlist")
        echo "$playlist: $count tracks"
    fi
done 2>/dev/null
