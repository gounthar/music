# Music Library Workflow and Script Reference

This repository provides a set of Bash scripts to take a collection of untagged audio files and turn them into a clean, tagged, and organized MP3 library, complete with playlists and (optionally) beets library integration. It is designed for Linux and Windows users via WSL (Windows Subsystem for Linux).

The typical pipeline is:
1) Tag and import untagged audio (to-sort) into a curated lossless library
2) Convert or consolidate audio to MP3 into a structured MP3 tree
3) Flatten MP3 tree to a single result/ directory for portable consumption
4) Generate artist- and genre-based playlists
5) Optionally re-import MP3 tree into beets

You can run just the parts you need; each script is designed to be individually useful.

---

## Prerequisites

- OS: Linux or Windows via WSL (Debian/Ubuntu recommended)
- Packages/Tools:
  - beets and selected plugins: fetchart, lyrics, lastgenre, discogs
  - ffmpeg, ffprobe
  - jq, bc (for advanced organization and metadata comparisons)
  - Mutagen tools: mid3v2 (from python-mutagen)
  - exiftool (optional but helpful)
  - GNU coreutils: find, xargs, sed, awk, tr, sha256sum, md5sum, cmp, realpath
- WSL notes:
  - Windows drive paths appear under /mnt/c/...
  - Ensure your audio paths match your setup.

Install examples (WSL Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg jq bc exiftool python3-pip
pip install beets "beets[fetchart,lyrics,lastgenre,discogs]" mutagen
```

Discogs token:
- For best results with Discogs metadata, get a personal token and configure beets accordingly.

---

## Directory Conventions and Defaults

These defaults are used in the scripts (customize as needed):

- to-sort (source of untagged): `/mnt/c/Users/User/Music/to-sort`
- Lossless library root: `/mnt/c/Users/User/Music/lossless`
- MP3 tree root: `/mnt/c/Users/User/Music/mp3`
- Flat MP3 output (from MP3 root): `mp3/result`

How to customize:
- Many scripts have variables near the top (e.g., MUSIC_ROOT, MP3_ROOT, MUSIC_DIR).
- Some scripts accept arguments to override defaults (see each script reference below).

---

## Recommended End-to-End Workflow

1) Tag and import untagged audio (non-interactive)
- Use tag-files.sh to import from to-sort into a curated lossless library using beets. This both organizes files and adds them to your beets DB.

2) Optional: Clean up duplicates created by prior tooling
- Use de-duplicate.sh to remove duplicate files such as “Track (1).mp3” if they match original content.

3) Build the MP3 tree
- Option A (recommended): organize-music-enhanced.sh
  - Moves existing MP3s into a mirrored MP3 tree, converts lossless files to MP3, supports parallelism and optional artwork embedding.
- Option B: music-converter.sh
  - Simpler conversion with a “move existing MP3s” phase and conversion of missing MP3s.

4) Flatten the MP3 tree for portable consumption
- From the MP3 root, run flatten-directories.sh to create a single result/ directory with conflict-free filenames.

5) Generate playlists
- Use create-genre-playlist.sh to generate genre_*.m3u and artist_*.m3u playlists (uses beets/mid3v2/exiftool).
- Use create-artist-playlists.sh for a simpler artist-only playlist generation.

6) Optional: Add MP3s to beets
- If you also want the MP3 tree in your beets library:
  ```bash
  beet import -A "/mnt/c/Users/User/Music/mp3"
  ```

---

## Script Reference

Below are details for each script: synopsis, parameters, behavior, outputs, dependencies, examples, and safety notes.

### tag-files.sh

Non-interactive beets import from a to-sort folder into an organized lossless library.

- Synopsis:
  - Writes a non-interactive beets config and runs `beet import -A "$MUSIC_SOURCE"` to auto-apply tag matches and move files into a structured lossless library.
- Arguments:
  - None. Edit variables in the script:
    - `MUSIC_SOURCE` (default: `/mnt/c/Users/User/Music/to-sort`)
    - `OUTPUT_DIR` (default: `/mnt/c/Users/User/Music/lossless`)
- Behavior:
  - Checks if `beet` is installed; installs via `pip` if not present.
  - Writes `~/.config/beets/config.yaml` with these defaults:
    - `directory: $OUTPUT_DIR`
    - `plugins: fetchart lyrics lastgenre discogs`
    - `import.move: yes`, `import.quiet: yes`, `import.autotag: yes`, `skip_errors: yes`
    - `unmatched.quiet: yes`
    - `discogs.token: YOUR_DISCOGS_TOKEN` (placeholder)
  - Runs `beet import -A "$MUSIC_SOURCE"` for automated tagging and import.
- Outputs:
  - Tagged and organized files in `$OUTPUT_DIR`, available in your beets library.
- Dependencies:
  - Python3/pip, beets and plugins noted above.
- Example:
  ```bash
  # edit MUSIC_SOURCE/OUTPUT_DIR in script if needed
  ./tag-files.sh
  ```
- Safety:
  - The script overwrites `~/.config/beets/config.yaml`. Backup your config first if you have a custom setup.

---

### de-duplicate.sh

Remove duplicate files suffixed with “ (n)” if content-identical to the original.

- Synopsis:
  - Finds files with a “ (number)” suffix, compares size and content with non-suffixed original, and removes duplicates when identical.
- Arguments:
  - None. Edit `MUSIC_ROOT` in the script (default: `/mnt/c/Users/User/Music`).
- Behavior:
  - Uses `find` to locate candidates, `stat -c%s` to compare sizes, and `cmp -s` for content comparison.
  - Removes duplicate if content-identical; otherwise logs differences.
- Outputs:
  - Deletes duplicate files; logs actions.
- Dependencies:
  - `find`, `sed`, `stat`, `cmp`.
- Example:
  ```bash
  # edit MUSIC_ROOT to your tree root
  ./de-duplicate.sh
  ```
- Safety:
  - Destructive (removes files). Consider testing on a copy or snapshot.

---

### copy-if-newer.sh

Propagate updated scripts into a target tree based on modification time.

- Synopsis:
  - For each `.ps1` or `.sh` file in the current directory, find files with the same name under `TARGET_DIR` and copy if the source is newer.
- Arguments:
  - None. Edit:
    - `SOURCE_DIR="."`
    - `TARGET_DIR="/mnt/c/Users/User/Music"`
- Behavior:
  - Recursively searches the target tree. Copies with `cp -p` if source is newer.
  - If no matches are found, interactively prompts to copy to a specified location under `TARGET_DIR`.
- Outputs:
  - Updated script files under `TARGET_DIR` where applicable.
- Dependencies:
  - `find`, `cp`.
- Example:
  ```bash
  ./copy-if-newer.sh
  ```
- Safety:
  - Copies files with preservation of timestamps. Answer prompts carefully.

---

### mka2flac.sh

Convert `.mka` audio to `.flac`. Copies stream if codec is already FLAC, else transcodes.

- Synopsis:
  - Batch converts input files to `.flac` alongside originals, preserving metadata.
- Arguments:
  - Files/globs provided on the command line, e.g. `*.mka`.
- Behavior:
  - Uses `ffprobe` to detect codec. If `flac`, copies stream; otherwise transcodes to FLAC.
- Outputs:
  - `.flac` files in the same directories as inputs.
- Dependencies:
  - `ffprobe`, `ffmpeg`.
- Example:
  ```bash
  ./mka2flac.sh *.mka
  ```
- Safety:
  - Uses `yes | ffmpeg` to overwrite existing `.flac` if present. Back up if needed.

---

### music-converter.sh

Create and populate an MP3 tree from a lossless library (simple sequential approach).

- Synopsis:
  - Moves existing MP3s out of `MUSIC_ROOT` into `MP3_ROOT` and converts lossless files (FLAC/ALAC) that lack a corresponding MP3.
- Configuration variables:
  - `MUSIC_ROOT="/mnt/c/Users/User/Music/lossless"`
  - `MP3_ROOT="$MUSIC_ROOT/../mp3"`
  - `DRY_RUN=false`, `VERBOSE=true`, `CONVERT_MISSING_MP3=true`
- Behavior:
  - Phase 1: Move existing MP3s to `MP3_ROOT`, mirroring directory structure.
  - Phase 2: Convert `.flac`/`.alac` (excluding anything already under MP3_ROOT) using libmp3lame `-q:a 2`, preserving metadata with ID3v2.3 tags.
- Outputs:
  - MP3 tree under `MP3_ROOT` (mirrors the structure of the lossless library).
- Dependencies:
  - `ffmpeg`, `ffprobe`, `find`, `xargs`, coreutils.
- Example:
  ```bash
  # edit MUSIC_ROOT/MP3_ROOT if needed
  ./music-converter.sh
  ```
- Safety:
  - Set `DRY_RUN=true` to preview changes. Ensure sufficient disk space.

---

### organize-music-enhanced.sh

Advanced MP3 pipeline with parallel conversion and optional artwork embedding.

- Synopsis:
  - Moves MP3s to a mirrored MP3 tree, compares/handles duplicates, builds a list of lossless files, and converts them to MP3—optionally in parallel—with normalized metadata and artwork embedding.
- Configuration variables:
  - Paths/flags: `MUSIC_ROOT`, `MP3_ROOT`, `DRY_RUN`, `VERBOSE`, `CONVERT_MISSING_MP3`, `CONVERT_PARALLEL`, `THREADS=$(nproc)`
  - Quality: `MP3_QUALITY=2` (when `PRESET_MODE="quality"`), or `BITRATE="192k"` (when `PRESET_MODE="bitrate"`)
  - Artwork: `PRESERVE_ARTWORK=true`
  - Cleanup: `DELETE_ORIGINAL_MP3=true` (delete source MP3 after moving)
- Behavior:
  - Phase 1: Move MP3s to `MP3_ROOT`. If target exists, compare and handle duplicates.
  - Phase 2: Build a list of lossless files lacking MP3 counterparts, then:
    - Parallel mode: Use `xargs -0 -P $THREADS` to run conversions across CPUs.
    - Serial mode: Convert one-by-one.
  - Optional: Extract/attach artwork; enforce ID3v2.3 tagging.
- Outputs:
  - MP3 tree populated in `MP3_ROOT`, with optional artwork embedded.
- Dependencies:
  - `ffmpeg`, `ffprobe`, `jq`, `bc`, `xargs`, coreutils.
- Example:
  ```bash
  PRESET_MODE=quality MP3_QUALITY=2 CONVERT_PARALLEL=true ./organize-music-enhanced.sh
  ```
- Safety:
  - When `DELETE_ORIGINAL_MP3=true`, original MP3s may be removed after moving; ensure backups.
  - Use `DRY_RUN=true` to preview.

---

### flatten-directories.sh

Flatten a directory tree into `result/` with stable, conflict-free filenames.

- Synopsis:
  - Moves all `.mp3` files from a nested tree to a single `result/` directory. Skips exact duplicates (by content hash). Prevents filename collisions by adding a short path hash and counters.
- Arguments:
  - None; run it from the directory you want to flatten (e.g., MP3 root).
- Behavior:
  - Uses an associative array of content hashes to skip duplicates.
  - Computes a 6-char path hash from the file’s subdirectory and prefixes it in the output filename.
  - Handles name collisions by appending ` (counter)`.
- Outputs:
  - `result/` directory populated with flattened `.mp3` files.
- Dependencies:
  - `md5sum`, `sha256sum`, `cmp`, `find`, `coreutils`.
- Example:
  ```bash
  cd "/mnt/c/Users/User/Music/mp3"
  ./flatten-directories.sh
  # → creates /mnt/c/Users/User/Music/mp3/result
  ```
- Safety:
  - Destructive move from source into `result/`. Review before running on your only copy.

---

### create-genre-playlist.sh

Generate genre-based and artist-based M3U playlists from the flat `result/` directory.

- Synopsis:
  - Scans MP3 files, extracts artist and genre via beets (preferred), or falls back to `mid3v2`/`exiftool`. Writes playlists to a temp directory, then moves them to the final location.
- Arguments:
  - `MUSIC_DIR` (default: `/mnt/c/Users/User/Music/mp3/result`)
  - `PLAYLIST_DIR` (default: same as `MUSIC_DIR`)
- Behavior:
  - For each MP3, determine artist and genres; sanitize names for filesystem safety.
  - Genre tags can be comma or semicolon separated; script splits and writes each to its own `genre_*.m3u`.
  - Uses a temp directory to avoid partial/locked outputs during processing.
- Outputs:
  - Artist playlists: `artist_<Artist>.m3u`
  - Genre playlists: `genre_<Genre>.m3u`
- Dependencies:
  - `beet` (optional), `mid3v2` (optional), `exiftool` (optional), `find`.
- Example:
  ```bash
  ./create-genre-playlist.sh "/mnt/c/Users/User/Music/mp3/result"
  ```
- Notes:
  - If `beet` is installed and library contains your tracks, it is used first for artist/genre extraction.

---

### create-artist-playlists.sh

Generate one M3U playlist per artist using MP3 tags.

- Synopsis:
  - Minimal version focusing only on artist-based playlists using `mid3v2` tag reading.
- Arguments:
  - `MUSIC_DIR` (default: `/mnt/c/Users/User/Music/mp3/result`)
  - `PLAYLIST_DIR` (default: same as `MUSIC_DIR`)
- Behavior:
  - Reads artist from ID3 tags; sanitizes the name; groups tracks per artist into M3U files in a temp directory then moves them to the destination.
- Outputs:
  - `<Artist>.m3u` under `PLAYLIST_DIR`.
- Dependencies:
  - `mid3v2`, `find`.
- Example:
  ```bash
  ./create-artist-playlists.sh "/mnt/c/Users/User/Music/mp3/result"
  ```

---

### investigate-genres.sh

Investigate genre tagging and playlist contents; useful for debugging metadata and playlist generation.

- Synopsis:
  - Lists genre playlists in the current directory, samples contents, tests `beet list` genre extraction on a few files, prints ID3 genre frames, and counts playlist entries.
- Arguments:
  - `TARGET_DIR` positional or env var; default `./`
- Behavior:
  - Uses null-delimited loops (`-print0` and `read -d ''`) to handle unusual filenames safely.
  - Uses `beet list` with `realpath` for robust matching.
- Outputs:
  - Diagnostic console output.
- Dependencies:
  - `beet` (optional), `mid3v2`, `exiftool`, `realpath`, `find`, coreutils.
- Example:
  ```bash
  ./investigate-genres.sh "/mnt/c/Users/User/Music/mp3/result"
  ```

---

## Quickstart

1) Tag and import untagged audio to lossless library:
```bash
# Edit variables in tag-files.sh if needed (MUSIC_SOURCE, OUTPUT_DIR)
./tag-files.sh
```

2) Convert to MP3 tree (choose one):
```bash
# Simple
./music-converter.sh

# Advanced (recommended)
PRESET_MODE=quality MP3_QUALITY=2 CONVERT_PARALLEL=true ./organize-music-enhanced.sh
```

3) Flatten MP3 tree:
```bash
cd "/mnt/c/Users/User/Music/mp3"
./flatten-directories.sh
```

4) Generate playlists:
```bash
./create-genre-playlist.sh "/mnt/c/Users/User/Music/mp3/result"
# or
./create-artist-playlists.sh "/mnt/c/Users/User/Music/mp3/result"
```

5) Optional: Import MP3s into beets:
```bash
beet import -A "/mnt/c/Users/User/Music/mp3"
```

---

## Safety, Troubleshooting, and Tips

- Always keep backups or use versioned storage (e.g., Git, ZFS snapshots) before running destructive operations.
- Use DRY_RUN modes where available (e.g., organize-music-enhanced.sh).
- Be mindful of config overwrites (tag-files.sh writes `~/.config/beets/config.yaml`).
- WSL paths differ from native Windows paths; ensure you use `/mnt/c/...` style in scripts.
- If `beet list` is not returning data for a file, ensure it’s already imported into the beets library.
- If genre tags aren’t as expected, use `investigate-genres.sh` to diagnose; it can print TCON frames and sample playlist contents.

---

## Notes on Style and Robustness

- Scripts prefer strict mode where applicable (`set -euo pipefail`), null-delimited loops for filenames, and explicit error handling.
- Playlists and filenames are sanitized to avoid commas, slashes, quotes, and colons, with spaces replaced by underscores where needed.
