#!/bin/bash
# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    ensure_deps ffmpeg ffprobe || { echo "Missing dependencies (ffmpeg/ffprobe)" >&2; exit 1; }
    add_user_local_bin_to_path
fi

## Configuration
LOSSLESS_DIR="${LOSSLESS_DIR:-/mnt/c/Users/User/Music/lossless}"
MP3_DIR="${MP3_DIR:-/mnt/c/Users/User/Music/mp3}"
MUSIC_ROOT="${MUSIC_ROOT:-$LOSSLESS_DIR}"
MP3_ROOT="${MP3_ROOT:-$MP3_DIR}"
DRY_RUN=false
VERBOSE=true
CONVERT_MISSING_MP3=true

## Function to safely convert files
convert_to_mp3() {
    local lossless_file="$1"
    local mp3_path="$2"
    
    # Verify source exists
    if [[ ! -f "$lossless_file" ]]; then
        echo "Error: Source file not found: $lossless_file" >&2
        return 1
    fi

    if $VERBOSE; then
        echo "Converting: $lossless_file → $mp3_path"
    fi

    # Create target directory
    mkdir -p "$(dirname "$mp3_path")"
    
    if ! $DRY_RUN; then
        ffmpeg -i "$lossless_file" -codec:a libmp3lame -q:a 2 \
               -map_metadata 0 -id3v2_version 3 \
               "$mp3_path" </dev/null 2>/dev/null || {
            echo "Conversion failed for: $lossless_file" >&2
            return 1
        }
    fi
}

## Main Execution

# Create MP3 root directory
mkdir -p "$MP3_ROOT"

# Phase 1: Move existing MP3s
if $VERBOSE; then
    echo "=== Moving existing MP3 files ==="
fi

find "$MUSIC_ROOT" -type f -name "*.mp3" -not -path "$MP3_ROOT/*" -print0 | \
while IFS= read -r -d $'\0' mp3file; do
    target_mp3="$MP3_ROOT/${mp3file#$MUSIC_ROOT/}"
    
    if $VERBOSE; then
        echo "Moving: $mp3file → $target_mp3"
    fi
    
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$target_mp3")"
        mv -n "$mp3file" "$target_mp3" || echo "Failed to move: $mp3file" >&2
    fi
done

# Phase 2: Convert lossless files
if $CONVERT_MISSING_MP3; then
    if $VERBOSE; then
        echo -e "\n=== Converting lossless files ==="
    fi
    
    find "$MUSIC_ROOT" -type f \( -name "*.flac" -o -name "*.alac" \) \
         -not -path "$MP3_ROOT/*" -print0 | \
    while IFS= read -r -d $'\0' lossless_file; do
        mp3_path="$MP3_ROOT/${lossless_file#$MUSIC_ROOT/}"
        mp3_path="${mp3_path%.*}.mp3"
        
        [[ -f "$mp3_path" ]] && continue
        
        convert_to_mp3 "$lossless_file" "$mp3_path"
    done
fi

echo -e "\n=== Operation complete ==="
echo "MP3 files moved to: $MP3_ROOT"
echo "Lossless files converted: $(find "$MP3_ROOT" -type f -name "*.mp3" | wc -l)"
