#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# Make this script work from anywhere with sensible defaults
# Global defaults (can be overridden by env or args)
MP3_DIR="${MP3_DIR:-/mnt/c/Users/User/Music/mp3}"
FLAT_DIR="${FLAT_DIR:-/mnt/c/Users/User/Music/Bonneville}"

# Source (root to flatten) and destination (flat output)
SOURCE_ROOT="${1:-${SOURCE_ROOT:-$MP3_DIR}}"
DEST_DIR="${2:-${DEST_DIR:-$FLAT_DIR}}"

# Validate source and prepare destination
if [[ ! -d "$SOURCE_ROOT" ]]; then
  echo "Error: SOURCE_ROOT not found or not accessible: $SOURCE_ROOT" >&2
  exit 1
fi
mkdir -p "$DEST_DIR"

declare -A file_hashes  # Associative array to track seen content hashes

# Iterate over MP3 files below the source root (excluding the root level)
find "$SOURCE_ROOT" -mindepth 2 -type f -iname "*.mp3" -print0 | while IFS= read -r -d '' filepath; do
  # Calculate file content hash
  content_hash=$(md5sum "$filepath" | cut -d' ' -f1)

  # Skip if we've seen this content before (exact duplicate)
  if [[ -v file_hashes[$content_hash] ]]; then
    echo "Skipping duplicate: $filepath (same as ${file_hashes[$content_hash]})"
    continue
  fi
  file_hashes[$content_hash]="$filepath"

  # Derive a stable path-hash based on the file's subdirectory relative to SOURCE_ROOT
  rel="${filepath#"$SOURCE_ROOT"/}"
  subdir=$(dirname "$rel")
  path_hash=$(printf "%s" "$subdir" | sha256sum | cut -c1-6)

  filename=$(basename "$filepath")
  base_name="${filename%.*}"
  extension="${filename##*.}"

  target_file="$DEST_DIR/${path_hash}_${filename}"
  counter=1

  # If target exists, find a unique name
  while [[ -e "$target_file" ]]; do
    # If it's the exact same file (shouldn't happen due to content hash, but just in case)
    if cmp -s "$filepath" "$target_file"; then
      echo "Skipping identical file: $filepath (already exists as $target_file)"
      continue 2  # Continue to next file in find loop
    fi
    # Different file with same name, add counter
    target_file="$DEST_DIR/${path_hash}_${base_name} (${counter}).${extension}"
    ((counter++))
  done

  # Move the file to the flat destination
  mv "$filepath" "$target_file"
  echo "Moved: $filepath -> $target_file"
done

echo "Flattening complete. Files moved to: $DEST_DIR"
