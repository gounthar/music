#!/bin/bash

# Set the root directory of your music library
MUSIC_ROOT="/mnt/c/Users/User/Music"

# Find all files with (1), (2), etc. suffixes
find "$MUSIC_ROOT" -type f -name '*([0-9])*' | while read -r duplicate; do
    # Get the original filename by removing the (n) suffix
    original=$(echo "$duplicate" | sed -E 's/ \([0-9]+\)//')
    
    # Check if the original file exists
    if [[ -f "$original" ]]; then
        # Compare file sizes first (quick check)
        size_duplicate=$(stat -c%s "$duplicate")
        size_original=$(stat -c%s "$original")
        
        if [[ "$size_duplicate" -eq "$size_original" ]]; then
            # If sizes match, do a full content comparison
            if cmp -s "$duplicate" "$original"; then
                echo "Removing duplicate: $duplicate"
                rm "$duplicate"
            else
                echo "Files have same size but different content: $duplicate and $original"
            fi
        else
            echo "Files have different sizes: $duplicate and $original"
        fi
    else
        echo "Original file not found for: $duplicate"
    fi
done

echo "Duplicate cleanup complete!"