#!/bin/bash
mkdir -p result
declare -A file_hashes  # Associative array to track seen hashes

find . -mindepth 2 -type f -print0 | while IFS= read -r -d '' filepath; do
    # Calculate file content hash
    content_hash=$(md5sum "$filepath" | cut -d' ' -f1)
    
    # Skip if we've seen this content before
    if [[ -n "${file_hashes[$content_hash]}" ]]; then
        echo "Skipping duplicate: $filepath (same as ${file_hashes[$content_hash]})"
        continue
    fi
    file_hashes[$content_hash]="$filepath"
    
    # Generate path hash (6 chars) for filename prefix
    subdir=$(dirname "${filepath#./}")
    path_hash=$(printf "%s" "$subdir" | sha256sum | cut -c1-6)
    
    # Get filename and move
    filename=$(basename "$filepath")
    mv -i "$filepath" "result/${path_hash}_${filename}"
done