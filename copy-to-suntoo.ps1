# Set the source and destination folders
$src = 'C:\Users\User\Music\mp3\result'
$dst = 'D:\music'

# Create destination directory if it doesn't exist
if (!(Test-Path $dst)) {
    New-Item -ItemType Directory -Path $dst | Out-Null
}

# Find all files recursively
$files = Get-ChildItem -Path $src -File -Recurse

foreach ($file in $files) {
    # Create full destination path
    $relative = $file.FullName.Substring($src.Length)
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
