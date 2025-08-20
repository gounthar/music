<# 
.SYNOPSIS
  Copy tracks referenced by an M3U/M3U8 playlist to a destination folder.

.DESCRIPTION
  Reads a playlist file (.m3u/.m3u8), resolves each entry (absolute or relative to the playlist),
  and copies files to the destination. If -SourceRoot is provided and a file resides under it,
  the script preserves the relative subpath under Destination; otherwise it copies as a flat filename.

  Existing files are only overwritten if the source is newer (unless -NoClobber is used).
  Supports -WhatIf/-Confirm and -Verbose via CmdletBinding/ShouldProcess.

.PARAMETER PlaylistPath
  Full path to the M3U/M3U8 file to read.

.PARAMETER Destination
  Destination root folder where files will be copied. Created if it doesn't exist.

.PARAMETER SourceRoot
  Optional source root to preserve relative paths. If a source file's path starts with this root
  (case-insensitive), its subpath is preserved under Destination. Otherwise, only the filename is used.

.PARAMETER Encoding
  Text encoding used when reading the playlist. Defaults to UTF8.

.PARAMETER NoClobber
  If set, never overwrite an existing destination file (skips regardless of timestamps).

.EXAMPLE
  .\copy-playlist.ps1 -PlaylistPath 'C:\Playlists\gym.m3u' -Destination 'E:\Music'

.EXAMPLE
  .\copy-playlist.ps1 -PlaylistPath 'C:\Playlists\gym.m3u' -Destination 'E:\Music' -SourceRoot 'C:\Users\User\Music\mp3'

.EXAMPLE
  .\copy-playlist.ps1 -PlaylistPath 'C:\Playlists\gym.m3u' -Destination 'E:\Music' -WhatIf -Verbose

.NOTES
  Requires PowerShell 5+ (or PowerShell 7+). Uses ShouldProcess to honor -WhatIf/-Confirm.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  # Full path to the .m3u/.m3u8 file
  [Parameter(Mandatory, Position = 0)]
  [ValidateNotNullOrEmpty()]
  [string]$PlaylistPath,

  # Destination root where tracks will be copied
  [Parameter(Mandatory, Position = 1)]
  [ValidateNotNullOrEmpty()]
  [string]$Destination,

  # Optional source root used to preserve relative directory structure if a track lies under this root
  [Parameter(Position = 2)]
  [string]$SourceRoot,

  # Encoding used to read the playlist
  [ValidateSet('UTF8','UTF8BOM','ASCII','Unicode','UTF7','UTF32','BigEndianUnicode','Default','OEM')]
  [string]$Encoding = 'UTF8',

  # If set, skip when destination exists regardless of timestamps
  [switch]$NoClobber
)

Set-StrictMode -Version Latest

# Resolve/validate paths
try {
  $PlaylistPath = (Resolve-Path -LiteralPath $PlaylistPath -ErrorAction Stop).Path
} catch {
  throw "Playlist file not found: $PlaylistPath"
}

# Normalize Destination; create if missing
try {
  if (-not (Test-Path -LiteralPath $Destination)) {
    Write-Verbose "Creating destination directory: $Destination"
    New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null
  }
  $Destination = (Resolve-Path -LiteralPath $Destination -ErrorAction Stop).Path
} catch {
  throw "Unable to prepare destination '$Destination': $($_.Exception.Message)"
}

# Normalize SourceRoot if provided
$NormalizedSourceRoot = $null
if ($SourceRoot) {
  try {
    if (Test-Path -LiteralPath $SourceRoot) {
      $NormalizedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
    } else {
      # Allow a not-yet-existing root; use as provided for StartsWith compare
      $NormalizedSourceRoot = $SourceRoot
    }
  } catch {
    $NormalizedSourceRoot = $SourceRoot
  }
}

# Read playlist lines
try {
  $lines = Get-Content -LiteralPath $PlaylistPath -Encoding $Encoding -ErrorAction Stop
} catch {
  throw "Failed to read playlist '$PlaylistPath': $($_.Exception.Message)"
}

# Filter out comments/blank lines
$playlistFiles = @()
foreach ($line in $lines) {
  $t = ($line ?? '').Trim()
  if ($t.Length -gt 0 -and -not $t.StartsWith('#')) {
    $playlistFiles += $t
  }
}

$processed = 0
$copied    = 0
$updated   = 0
$skipped   = 0
$errors    = 0

$playlistDir = Split-Path -LiteralPath $PlaylistPath -Parent

foreach ($entry in $playlistFiles) {
  # Resolve absolute vs relative entries
  if ([System.IO.Path]::IsPathRooted($entry)) {
    $sourceFile = $entry
  } else {
    $sourceFile = Join-Path -Path $playlistDir -ChildPath $entry
  }

  if (-not (Test-Path -LiteralPath $sourceFile)) {
    Write-Warning "File not found: $sourceFile"
    $skipped++
    continue
  }

  $file = Get-Item -LiteralPath $sourceFile

  # Determine relative path under Destination
  $relative = $file.Name
  if ($NormalizedSourceRoot) {
    # Case-insensitive StartsWith
    if ($file.FullName.StartsWith($NormalizedSourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      $relative = $file.FullName.Substring($NormalizedSourceRoot.Length).TrimStart('\','/')
      if ([string]::IsNullOrWhiteSpace($relative)) {
        $relative = $file.Name
      }
    }
  }

  $target = Join-Path -Path $Destination -ChildPath $relative
  $targetDir = Split-Path -Path $target -Parent

  # Ensure target directory exists
  if (-not (Test-Path -LiteralPath $targetDir)) {
    try {
      Write-Verbose "Creating directory: $targetDir"
      New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning "Unable to create directory '$targetDir': $($_.Exception.Message)"
      $errors++
      continue
    }
  }

  try {
    if (Test-Path -LiteralPath $target) {
      if ($NoClobber) {
        Write-Verbose "Skipping existing (NoClobber): $relative"
        $skipped++
      } else {
        $dstItem = Get-Item -LiteralPath $target
        if ($file.LastWriteTime -gt $dstItem.LastWriteTime) {
          if ($PSCmdlet.ShouldProcess($target, "Update (newer) from '$($file.FullName)'")) {
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            Write-Host "Updated: $relative"
            $updated++
          }
        } else {
          Write-Host "Skipped (same or older): $relative"
          $skipped++
        }
      }
    } else {
      if ($PSCmdlet.ShouldProcess($target, "Copy (new) from '$($file.FullName)'")) {
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        Write-Host "Copied: $relative"
        $copied++
      }
    }
  } catch {
    $errors++
    if ($_.Exception.Message -match "There is not enough space") {
      Write-Host "No more space left copying: $relative"
      break
    } else {
      Write-Warning "Error copying $relative: $($_.Exception.Message)"
    }
  }

  $processed++
}

Write-Host "Playlist copy completed. Processed: $processed. Copied: $copied. Updated: $updated. Skipped: $skipped. Errors: $errors."
