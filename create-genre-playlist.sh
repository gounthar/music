#!/bin/bash
set -euo pipefail

# Global defaults (can be overridden by env or args)
FLAT_DIR="${FLAT_DIR:-/mnt/c/Users/User/Music/Bonneville}"
MUSIC_DIR="${1:-${MUSIC_DIR:-$FLAT_DIR}}"
PLAYLIST_DIR="${2:-${PLAYLIST_DIR:-$MUSIC_DIR}}"

mkdir -p "$PLAYLIST_DIR"
cd "$MUSIC_DIR" || exit 1
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Load dependency helpers and ensure required tools
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    add_user_local_bin_to_path
    ensure_deps python3 pip beet mid3v2 exiftool
fi

# Sanitize a string for safe playlist filenames
sanitize_filename() {
    local input
    input="$1"
    # trim, remove commas/slashes/quotes/colons, replace spaces with underscores
    echo "$input" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//' -e "s/[,'\"\/:_]/_/g" -e 's/[[:space:]]\+/_/g' -e 's/_\+/_/g'
}

# Function to extract artist name
get_artist() {
    local file
    file="$1"
    local artist
    artist=""
    
    # Try beets first
    if command -v beet &> /dev/null; then
        local abs_path
        abs_path=$(realpath "$file")
        # shellcheck disable=SC2016
        artist=$(beet list path:"$abs_path" -f '$artist' | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi
    
    # Fallback to ID3 tags
    if [[ -z "$artist" ]] && command -v mid3v2 &> /dev/null; then
        artist=$(mid3v2 -l "$file" | grep -aim 1 -E '^(TPE1|TP1)=' | awk -F= '{print $2}' | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi
    
    if [[ -z "$artist" ]] && command -v exiftool &> /dev/null; then
        artist=$(exiftool -b -Artist "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi

    if [[ -z "$artist" ]]; then
        artist="Unknown_Artist"
    fi
    
    echo "$artist"
}

# Function to extract genre
get_genre() {
    local file
    file="$1"
    local genre
    genre=""
    
    # Try beets first
    if command -v beet &> /dev/null; then
        local abs_path
        abs_path=$(realpath "$file")
        # shellcheck disable=SC2016
        genre=$(beet list path:"$abs_path" -f '$genre' | head -n1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi
    
    # Fallback to ID3 tags
    if [[ -z "$genre" ]] && command -v mid3v2 &> /dev/null; then
        genre=$(mid3v2 -l "$file" | grep -aim 1 '^TCON=' | awk -F= '{print $2}' | paste -sd, - | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi
    
    if [[ -z "$genre" ]] && command -v exiftool &> /dev/null; then
        genre=$(exiftool -b -Genre "$file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    fi

    if [[ -z "$genre" ]]; then
        # Try to guess genre from artist name or other metadata
        local artist
        artist=$(get_artist "$file")
        genre=$(guess_genre_from_artist "$artist")
    fi
    
    echo "$genre"
}

# Simple function to guess genre from artist name (very basic)
# shellcheck disable=SC2221,SC2222
guess_genre_from_artist() {
    local artist
    artist="$1"
    case $(echo "$artist" | tr '[:upper:]' '[:lower:]') in
        *metal*|*death*|*black*|*thrash*|*slayer*|*megadeth*)
            echo "Metal"
            ;;
        *rock*|*ac/dc*|*gnr*|*guns*|*aerosmith*)
            echo "Rock"
            ;;
        *jazz*|*coltrane*|*miles*|*ellington*)
            echo "Jazz"
            ;;
        *classical*|*beethoven*|*mozart*|*bach*)
            echo "Classical"
            ;;
        *rap*|*hip*hop*|*eminem*|*jay*z*)
            echo "Hip-Hop"
            ;;
        *pop*|*madonna*|*michael*jackson*|*britney*)
            echo "Pop"
            ;;
        *)
            echo "Unknown_Genre"
            ;;
    esac
}

echo "Processing MP3 files to create playlists..."
find . -type f -name "*.mp3" -print0 | while IFS= read -r -d '' file; do
    filename="${file#./}"
    
    # Create artist playlist
    artist=$(get_artist "$file")
    clean_artist=$(sanitize_filename "$artist")
    echo "$filename" >> "$TEMP_DIR/artist_${clean_artist}.m3u"
    
    # Create genre playlist - FIXED TO HANDLE BOTH COMMA AND SEMICOLON
    genre=$(get_genre "$file")
    # Replace semicolons with commas first, then split by commas
    genre=$(echo "$genre" | tr ';' ',')
    IFS=',' read -ra genre_array <<< "$genre"
    for single_genre in "${genre_array[@]}"; do
        clean_genre=$(sanitize_filename "$single_genre")
        if [[ -n "$clean_genre" ]]; then
            echo "$filename" >> "$TEMP_DIR/genre_${clean_genre}.m3u"
        fi
    done
    
    echo "Processed: $filename"
done

# Move playlists to final location
for playlist in "$TEMP_DIR"/*.m3u; do
    playlist_name=$(basename "$playlist")
    mv -f "$playlist" "$PLAYLIST_DIR/$playlist_name"
done

echo "Playlists created in: $PLAYLIST_DIR"
find "$PLAYLIST_DIR" -maxdepth 1 -type f -name "*.m3u" -print0 | xargs -0 -r ls -la | head -10
