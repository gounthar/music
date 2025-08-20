# Set the source directory and destination folder
$src = 'C:\Users\User\Music\mp3\result'
$dst = 'D:\music'
$m3uFile = 'C:\path\to\your\playlist.m3u'  # Path to your M3U file

# Create destination directory if it doesn't exist
if (!(Test-Path $dst)) {
    New-Item -ItemType Directory -Path $dst | Out-Null
}

# Read M3U file and extract file paths
$playlistFiles = @()
if (Test-Path $m3uFile) {
    $playlistContent = Get-Content $m3uFile -Encoding UTF8
    foreach ($line in $playlistContent) {
        # Skip comments and empty lines
        if ($line -notmatch '^#' -and $line.Trim() -ne '') {
            $playlistFiles += $line.Trim()
        }
    }
} else {
    Write-Host "M3U file not found: $m3uFile"
    exit 1
}

# Process each file from the playlist
foreach ($playlistFile in $playlistFiles) {
    # Handle relative paths in M3U (relative to M3U file location)
    if ([System.IO.Path]::IsPathRooted($playlistFile)) {
        $sourceFile = $playlistFile
    } else {
        $m3uDir = [System.IO.Path]::GetDirectoryName($m3uFile)
        $sourceFile = Join-Path $m3uDir $playlistFile
    }
    
    # Check if the file exists
    if (!(Test-Path $sourceFile)) {
        Write-Host "File not found: $sourceFile"
        continue
    }
    
    # Get file info
    $file = Get-Item $sourceFile
    
    # Create relative path from source directory
    if ($file.FullName.StartsWith($src, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relative = $file.FullName.Substring($src.Length).TrimStart('\')
    } else {
        # If file is outside source directory, use filename only
        $relative = $file.Name
    }
    
    $target = Join-Path $dst $relative
    
    # Create the directory structure if needed
    $targetDir = Split-Path $target
    if (!(Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    try {
        if (Test-Path -Path $target) {
            # Check if source file is newer than destination
            $srcLastModified = $file.LastWriteTime
            $dstLastModified = (Get-Item $target).LastWriteTime

            if ($srcLastModified -gt $dstLastModified) {
                Copy-Item -Path $file.FullName -Destination $target -Force
                Write-Host "Updated (newer): ${relative}"
            } else {
                Write-Host "Skipped (same or older): ${relative}"
            }
        } else {
            # File doesn't exist in destination, copy it
            Copy-Item -Path $file.FullName -Destination $target -Force
            Write-Host "Copied (new): ${relative}"
        }
    } catch {
        if ($_.Exception.Message -match "There is not enough space") {
            Write-Host "No more space left copying: ${relative}"
            break
        } else {
            Write-Host "Error copying ${relative}: $($_.Exception.Message)"
        }
    }
}

Write-Host "Playlist copy completed. Processed $($playlistFiles.Count) files."