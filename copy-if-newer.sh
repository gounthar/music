#!/bin/bash

# Source directory (current directory)
SOURCE_DIR="."

# Target directory (will search recursively)
TARGET_DIR="/mnt/c/Users/User/Music"

# Options:
#   COPY_LIB=1      -> when copying a .sh script, also copy its sibling lib/deps.sh (default: 1)
#   SYNC_BEFORE=1   -> run ./sync-deps-lib.sh --quiet before copying (default: 1 if present)
COPY_LIB="${COPY_LIB:-1}"
SYNC_BEFORE="${SYNC_BEFORE:-1}"

# Optionally sync canonical deps to sibling lib/ next to each repo script before propagation
if [[ "$SYNC_BEFORE" = "1" && -x "./sync-deps-lib.sh" ]]; then
    ./sync-deps-lib.sh --quiet || true
fi

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
            # If we copied a shell script and COPY_LIB=1, also copy its sibling lib/deps.sh
            if [[ "$COPY_LIB" = "1" && "$filename" == *.sh ]]; then
                src_script_dir="$(dirname "$source_file")"
                src_dep="$src_script_dir/lib/deps.sh"
                if [[ -f "$src_dep" ]]; then
                    target_dir="$(dirname "$target_file")"
                    target_lib_dir="$target_dir/lib"
                    target_dep="$target_lib_dir/deps.sh"
                    mkdir -p "$target_lib_dir"
                    if [[ ! -f "$target_dep" || "$src_dep" -nt "$target_dep" ]]; then
                        cp -p "$src_dep" "$target_dep"
                        echo "    Updated deps: $target_dep"
                    else
                        echo "    Deps up-to-date: $target_dep"
                    fi
                fi
            fi
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
            # Also propagate sibling lib/deps.sh for shell scripts if requested
            if [[ "$COPY_LIB" = "1" && "$filename" == *.sh ]]; then
                src_script_dir="$(dirname "$source_file")"
                src_dep="$src_script_dir/lib/deps.sh"
                if [[ -f "$src_dep" ]]; then
                    target_dir="$(dirname "$target_path")"
                    target_lib_dir="$target_dir/lib"
                    target_dep="$target_lib_dir/deps.sh"
                    mkdir -p "$target_lib_dir"
                    if [[ ! -f "$target_dep" || "$src_dep" -nt "$target_dep" ]]; then
                        cp -p "$src_dep" "$target_dep"
                        echo "  Copied deps to: $target_dep"
                    else
                        echo "  Deps up-to-date: $target_dep"
                    fi
                fi
            fi
        fi
    fi
done

echo "Sync completed!"
