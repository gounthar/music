#!/bin/bash

MUSIC_DIR="/mnt/c/Users/User/Music/mp3/result"
PLAYLIST_DIR="/mnt/c/Users/User/Music/mp3/result"

mkdir -p "$PLAYLIST_DIR"
cd "$MUSIC_DIR"
TEMP_DIR=$(mktemp -d)

# Function to extract artist name
get_artist() {
    local file="$1"
    local artist=""
    
    # Try beets first
    if command -v beet &> /dev/null; then
        local abs_path=$(realpath "$file")
        artist=$(beet list path:"$abs_path" -f '$artist' | head -n1 | xargs)
    fi
    
    # Fallback to ID3 tags
    if [[ -z "$artist" ]] && command -v mid3v2 &> /dev/null; then
        artist=$(mid3v2 -l "$file" | grep -i "TPE1\|TP1" | awk -F= '{print $2}' | head -n1 | xargs)
    fi
    
    if [[ -z "$artist" ]] && command -v exiftool &> /dev/null; then
        artist=$(exiftool -b -Artist "$file" | xargs)
    fi

    if [[ -z "$artist" ]]; then
        artist="Unknown_Artist"
    fi
    
    echo "$artist"
}

# Function to extract genre
get_genre() {
    local file="$1"
    local genre=""
    
    # Try beets first
    if command -v beet &> /dev/null; then
        local abs_path=$(realpath "$file")
        genre=$(beet list path:"$abs_path" -f '$genre' | head -n1 | xargs)
    fi
    
    # Fallback to ID3 tags
    if [[ -z "$genre" ]] && command -v mid3v2 &> /dev/null; then
        genre=$(mid3v2 -l "$file" | grep -i "TCON" | awk -F= '{print $2}' | head -n1 | xargs)
    fi
    
    if [[ -z "$genre" ]] && command -v exiftool &> /dev/null; then
        genre=$(exiftool -b -Genre "$file" | xargs)
    fi

    if [[ -z "$genre" ]]; then
        # Try to guess genre from artist name or other metadata
        local artist=$(get_artist "$file")
        genre=$(guess_genre_from_artist "$artist")
    fi
    
    echo "$genre"
}

# Simple function to guess genre from artist name (very basic)
guess_genre_from_artist() {
    local artist="$1"
    case $(echo "$artist" | tr '[:upper:]' '[:lower:]') in
        *metal*|*death*|*black*|*thrash*|*slayer*|*metallica*|*megadeth*)
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
find . -type f -name "*.mp3" | while read -r file; do
    filename="${file#./}"
    
    # Create artist playlist
    artist=$(get_artist "$file")
    clean_artist=$(echo "$artist" | sed 's/[,/]//g' | tr ' ' '_' | tr -d ':''"'"'"'')
    echo "$filename" >> "$TEMP_DIR/artist_${clean_artist}.m3u"
    
    # Create genre playlist
    genre=$(get_genre "$file")
    IFS=',' read -ra genre_array <<< "$genre"
    for single_genre in "${genre_array[@]}"; do
        clean_genre=$(echo "$single_genre" | xargs | sed 's/[,/]//g' | tr ' ' '_' | tr -d ':''"'"'"'')
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

rm -rf "$TEMP_DIR"
echo "Playlists created in: $PLAYLIST_DIR"
ls -la "$PLAYLIST_DIR"/*.m3u | head -10