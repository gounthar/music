#!/bin/bash

# Load dependency helpers and ensure required tools (if available)
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/deps.sh" ]; then
    # shellcheck source=lib/deps.sh
    . "$SCRIPT_DIR/lib/deps.sh"
    add_user_local_bin_to_path
    ensure_deps ffmpeg ffprobe jq bc
fi

## Configuration
LOSSLESS_DIR="${LOSSLESS_DIR:-/mnt/c/Users/User/Music/lossless}"
MP3_DIR="${MP3_DIR:-/mnt/c/Users/User/Music/mp3}"
MUSIC_ROOT="${MUSIC_ROOT:-$LOSSLESS_DIR}"
MP3_ROOT="${MP3_ROOT:-$MP3_DIR}"
DRY_RUN=false              # Set to true to preview changes
VERBOSE=true               # Set to false for quieter output
CONVERT_MISSING_MP3=true   # Set to false to skip conversion
THREADS=$(nproc)           # Use all available CPU cores
CONVERT_PARALLEL=true      # Parallel conversion (set false to debug)

# Audio Quality Settings
MP3_QUALITY=2              # LAME quality preset (0-9, 0=best)
BITRATE="192k"             # Alternative: Set specific bitrate
PRESET_MODE="quality"      # "quality" or "bitrate"

# File Handling
PRESERVE_ARTWORK=true      # Embed album art in MP3s
DELETE_ORIGINAL_MP3=true  # Caution: Will delete original MP3s after move

## Advanced Configuration
LOSSLESS_FORMATS=("flac" "alac" "wav" "aiff" "ape" "wv" "dsf" "m4a")
NAME_VARIANTS=(
    " (Official Video)" " (Official Audio)" " (Remastered)" " (Remaster)"
    " [Remastered]" " [Remaster]" " - Remastered" " - Remaster" " (Live)"
    " [Live]" " - Live" " (Radio Edit)" " [Radio Edit]" " - Radio Edit"
)

## Functions

normalize_name() {
    local name="${1%.*}"
    for variant in "${NAME_VARIANTS[@]}"; do
        name="${name//$variant/}"
    done
    echo "$name" | tr '[:upper:]' '[:lower:]' | tr -d '[:punct:]' | sed 's/ //g'
}

get_metadata() {
    ffprobe -v quiet -print_format json -show_format -show_streams "$1" 2>/dev/null
}

compare_metadata() {
    local meta1="$1" meta2="$2"
    local duration1=$(jq -r '.format.duration // .streams[0].duration' <<< "$meta1")
    local duration2=$(jq -r '.format.duration // .streams[0].duration' <<< "$meta2")
    
    if (( $(echo "define abs(i) { if (i < 0) return (-i); return (i) } 
              abs($duration1 - $duration2) > 1" | bc -l) )); then
        return 1
    fi
    
    local artist1=$(jq -r '.format.tags.ARTIST // .format.tags.artist // ""' <<< "$meta1")
    local artist2=$(jq -r '.format.tags.ARTIST // .format.tags.artist // ""' <<< "$meta2")
    local title1=$(jq -r '.format.tags.TITLE // .format.tags.title // ""' <<< "$meta1")
    local title2=$(jq -r '.format.tags.TITLE // .format.tags.title // ""' <<< "$meta2")
    
    if [[ -n "$artist1" && -n "$artist2" && -n "$title1" && -n "$title2" ]]; then
        if [[ "$artist1" != "$artist2" || "$title1" != "$title2" ]]; then
            return 1
        fi
    fi
    
    return 0
}

extract_artwork() {
    local input="$1"
    local output="$2"
    
    # Skip if artwork preservation is disabled or in DRY_RUN mode
    if ! $PRESERVE_ARTWORK || $DRY_RUN; then
        return
    fi

    ffmpeg -i "$input" -an -vcodec copy "$output" -y 2>/dev/null
}

convert_to_mp3() {
    local lossless_file="$1"
    local target_mp3="$2"

    if $VERBOSE; then
        echo "Converting: $lossless_file → $target_mp3"
    fi

    # Build ffmpeg command:
    # - Map ONLY the first audio stream
    # - Map ONLY attached picture (skip true video to avoid MP3 muxer errors)
    local ffmpeg_cmd="ffmpeg -nostdin -hide_banner -i \"$lossless_file\" -map 0:a:0 -c:a libmp3lame"

    if [[ "$PRESET_MODE" == "quality" ]]; then
        ffmpeg_cmd+=" -q:a $MP3_QUALITY"
    else
        ffmpeg_cmd+=" -b:a $BITRATE"
    fi

    # Copy tags and write ID3v2
    ffmpeg_cmd+=" -map_metadata 0 -id3v2_version 3 -write_id3v2 1"

    if $PRESERVE_ARTWORK; then
        # Map only attached picture stream (if present) and convert to JPEG, mark as cover
        ffmpeg_cmd+=" -map 0:v:m:attached_pic? -c:v mjpeg -disposition:v attached_pic -metadata:s:v title=\"Album cover\" -metadata:s:v comment=\"Cover (front)\""
    fi

    ffmpeg_cmd+=" \"$target_mp3\""

    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$target_mp3")"
        eval "$ffmpeg_cmd" </dev/null
    fi
}

# Export functions and config so they're available to subshells spawned by xargs
export -f normalize_name get_metadata compare_metadata extract_artwork convert_to_mp3
export PRESERVE_ARTWORK DRY_RUN VERBOSE PRESET_MODE MP3_QUALITY BITRATE MP3_ROOT MUSIC_ROOT

## Main Processing

# Create MP3 root directory
if ! $DRY_RUN; then
    mkdir -p "$MP3_ROOT"
fi

# Phase 1: Move existing MP3s
if $VERBOSE; then
    echo "=== Moving existing MP3 files ==="
fi

find "$MUSIC_ROOT" -type f -name "*.mp3" -not -path "$MP3_ROOT/*" | \
while read -r mp3file; do
    target_mp3="$MP3_ROOT/${mp3file#$MUSIC_ROOT/}"
    
    if $VERBOSE; then
        echo "Found MP3: $mp3file → $target_mp3"
    fi
    
    if ! $DRY_RUN; then
        mkdir -p "$(dirname "$target_mp3")"
        if [[ -f "$target_mp3" ]]; then
            if $VERBOSE; then
                echo "  Target exists, comparing..."
            fi
            if cmp -s "$mp3file" "$target_mp3"; then
                echo "  Duplicate found, removing original"
                $DELETE_ORIGINAL_MP3 && rm "$mp3file"
            else
                echo "  Different files, keeping both"
                mv -n "$mp3file" "${target_mp3%.mp3}_dup$$.mp3"
            fi
        else
            mv -n "$mp3file" "$target_mp3"
        fi
    fi
done

# Phase 2: Convert lossless files
if $CONVERT_MISSING_MP3; then
    if $VERBOSE; then
        echo -e "\n=== Converting lossless files ==="
    fi
    
    # Prepare file list for parallel processing
    file_list=()
    while IFS= read -r -d $'\0' lossless_file; do
        mp3_path="$MP3_ROOT/${lossless_file#$MUSIC_ROOT/}"
        mp3_path="${mp3_path%.*}.mp3"
        
        if [[ ! -f "$mp3_path" ]]; then
            file_list+=("$lossless_file")
        fi
    done < <(find "$MUSIC_ROOT" -type f \( -name "*.flac" -o -name "*.alac" -o \
             -name "*.wav" -o -name "*.aiff" -o -name "*.ape" -o -name "*.wv" \) \
             -not -path "$MP3_ROOT/*" -print0)
    
    # If a SINGLE_FILE path is provided, restrict processing to that file
    if [[ -n "${SINGLE_FILE:-}" ]]; then
        if [[ -f "$SINGLE_FILE" ]]; then
            file_list=( "$SINGLE_FILE" )
        else
            echo "SINGLE_FILE not found: $SINGLE_FILE" >&2
            file_list=()
        fi
    fi

    # Process conversion
    if $CONVERT_PARALLEL; then
        if $VERBOSE; then
            echo "Processing ${#file_list[@]} files with $THREADS threads..."
        fi
        
        printf "%s\0" "${file_list[@]}" | \
        xargs -0 -P $THREADS -I {} bash -c '
            lossless_file="{}"
            mp3_path="$MP3_ROOT/${lossless_file#$MUSIC_ROOT/}"
            mp3_path="${mp3_path%.*}.mp3"
            
            # Check again in case parallel processes created it
            [[ -f "$mp3_path" ]] && exit 0
            
            convert_to_mp3 "$lossless_file" "$mp3_path"
        '
    else
        for lossless_file in "${file_list[@]}"; do
            mp3_path="$MP3_ROOT/${lossless_file#$MUSIC_ROOT/}"
            mp3_path="${mp3_path%.*}.mp3"
            convert_to_mp3 "$lossless_file" "$mp3_path"
        done
    fi
fi

echo -e "\n=== Operation complete ==="
if $DRY_RUN; then
    echo "DRY RUN: No changes were made"
fi
echo "Summary:"
echo "- MP3 files moved to: $MP3_ROOT"
echo "- Lossless files converted: ${#file_list[@]}"
