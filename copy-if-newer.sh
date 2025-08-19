#!/bin/bash

# Source directory (current directory)
SOURCE_DIR="."

# Target directory (will search recursively)
TARGET_DIR="/mnt/c/Users/User/Music"

# Find all .ps1 and .sh files in current directory
find "$SOURCE_DIR" -maxdepth 1 -type f \( -name "*.ps1" -o -name "*.sh" \) | while read -r source_file; do
    # Get just the filename without path
    filename=$(basename "$source_file")
    
    echo "Processing: $filename"
    
    # Find all occurrences of this filename in target directory (recursive search)
    find "$TARGET_DIR" -type f -name "$filename" | while read -r target_file; do
        # Compare modification times
        if [[ "$source_file" -nt "$target_file" ]]; then
            echo "  Updating: $target_file (source is newer)"
            cp -p "$source_file" "$target_file"
        else
            echo "  Skipping: $target_file (target is newer or same age)"
        fi
    done
    
    # Check if we found any matches
    if ! find "$TARGET_DIR" -type f -name "$filename" | read -r; then
        echo "  No existing copy found in target directory"
        echo "  Would you like to copy it to a specific location? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            echo "  Enter target subdirectory (relative to $TARGET_DIR):"
            read -r subdir
            target_path="$TARGET_DIR/${subdir%/}/$filename"
            mkdir -p "$(dirname "$target_path")"
            cp -p "$source_file" "$target_path"
            echo "  Copied to: $target_path"
        fi
    fi
done

echo "Sync completed!"