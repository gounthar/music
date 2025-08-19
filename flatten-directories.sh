#!/bin/bash
set -euo pipefail
mkdir -p result
declare -A file_hashes  # Associative array to track seen hashes

find . -mindepth 2 -type f -name "*.mp3" -print0 | while IFS= read -r -d '' filepath; do
    # Calculate file content hash
    content_hash=$(md5sum "$filepath" | cut -d' ' -f1)
    
    # Skip if we've seen this content before (exact duplicate)
    if [[ -v file_hashes[$content_hash] ]]; then
        echo "Skipping duplicate: $filepath (same as ${file_hashes[$content_hash]})"
        continue
    fi
    file_hashes[$content_hash]="$filepath"
    
    # Generate unique filename with counter for conflicts
    subdir=$(dirname "${filepath#./}")
    path_hash=$(printf "%s" "$subdir" | sha256sum | cut -c1-6)
    filename=$(basename "$filepath")
    base_name="${filename%.*}"
    extension="${filename##*.}"
    
    target_file="result/${path_hash}_${filename}"
    counter=1
    
    # If file exists, find a unique name
    while [[ -e "$target_file" ]]; do
        # Check if it's the exact same file (shouldn't happen due to content hash, but just in case)
        if cmp -s "$filepath" "$target_file"; then
            echo "Skipping identical file: $filepath (already exists as $target_file)"
            continue 2  # Continue to next file in find loop
        fi
        
        # Different file with same name, add counter
        target_file="result/${path_hash}_${base_name} (${counter}).${extension}"
        ((counter++))
    done
    
    # Move the file
    mv "$filepath" "$target_file"
    echo "Moved: $filepath -> $target_file"
done

echo "Flattening complete. Files moved to result/ directory."
