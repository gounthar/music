#!/bin/bash
set -euo pipefail

TARGET_DIR="${1:-${TARGET_DIR:-./}}"
cd "$TARGET_DIR"

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
find . -maxdepth 1 -name "*.mp3" | while read -r file; do
    filename=$(basename "$file")
    echo -n "$filename: "
    # shellcheck disable=SC2016
    beet list path:"$(realpath "$filename")" -f '$genre' 2>/dev/null || echo "No genre found in beets"
done
echo ""

# 4. Check if files have multiple genres in their ID3 tags
echo "Checking ID3 tags for multiple genres:"
find . -maxdepth 1 -name "*.mp3" | while read -r file; do
    filename=$(basename "$file")
    echo -n "$filename: "
    if command -v mid3v2 &> /dev/null; then
        mid3v2 -l "$filename" | grep -i "TCON" || echo "No genre tag found"
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
