# Music Library Workflow and Script Reference

This repository provides a set of Bash scripts to take a collection of untagged audio files and turn them into a clean, tagged, and organized MP3 library, complete with playlists and (optionally) beets library integration. It is designed for Linux and Windows users via WSL (Windows Subsystem for Linux).

The scripts now work from anywhere (any working directory) and use environment-driven defaults for locations. You can override these defaults via environment variables or positional arguments where supported.

---

## Prerequisites

- OS: Linux or Windows via WSL (Debian/Ubuntu recommended)
- Packages/Tools:
  - beets and selected plugins: chroma, fetchart, lyrics, lastgenre, discogs
  - ffmpeg, ffprobe
  - Chromaprint tools: fpcalc (for AcoustID fingerprinting)
  - jq, bc (for advanced organization and metadata comparisons)
  - Mutagen tools: mid3v2 (from python-mutagen)
  - Python: pyacoustid (AcoustID client library used by beets’ chroma)
  - exiftool (optional but helpful)
  - GNU coreutils: find, xargs, sed, awk, tr, sha256sum, md5sum, cmp, realpath
- WSL notes:
  - Windows drive paths appear under /mnt/c/...
  - Ensure your audio paths match your setup.

Install examples (WSL Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg jq bc exiftool python3-pip libchromaprint-tools
pip install "beets[fetchart,lyrics,lastgenre,discogs]" mutagen pyacoustid
```

Note: Package names for fpcalc vary by distro. On Debian/WSL use libchromaprint-tools; on Ubuntu use chromaprint-tools. If neither exists, try acoustid-fingerprinter or chromaprint.

Discogs token:
- For best results with Discogs metadata, get a personal token and configure beets accordingly.

### Quick install (WSL/Debian/Ubuntu)

To install all required tools in one step:
```bash
./install-tools.sh
```

Flags:
- --no-sudo: do not use sudo; prints commands to run manually
- --pip-system: install Python packages system-wide instead of per-user
- --dry-run: print actions without executing
- --use-venv / --venv DIR: create/use a virtual environment and install Python deps inside it

Environment equivalents:
- NO_SUDO=1, ENSURE_PIP_SYSTEM=1, DRY_RUN=1

### Virtual environment (recommended)

To isolate Python packages (beets, mutagen) and avoid permission or `--user` issues in virtualenvs:

Create/use a virtual environment and install into it:
```bash
./install-tools.sh --use-venv --venv .venv
source .venv/bin/activate
```

Notes:
- If you are already inside a virtualenv, the installer detects it and installs into that environment.
- If you prefer system-wide packages instead of a venv:
```bash
./install-tools.sh --pip-system
```

### Auto-ensure dependencies in scripts

Scripts that rely on external tools can self-check and install missing ones by sourcing `lib/deps.sh`:
```bash
# At the top of your script
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/deps.sh
. "$SCRIPT_DIR/lib/deps.sh"
add_user_local_bin_to_path
ensure_deps python3 pip beet fpcalc mid3v2 exiftool ffmpeg ffprobe jq bc
```

Behavior:
- On Debian/Ubuntu, `ensure_deps` installs mapped commands via apt or pip (`pip --user` by default)
- Respects `NO_SUDO=1` and `DRY_RUN=1`; prints guidance if installation cannot proceed
- Adds `~/.local/bin` to PATH for pip `--user` commands

---

## Directory Conventions and Defaults (work-from-anywhere)

The scripts no longer assume you run them from specific directories. They use these environment-driven defaults:

- TO_SORT_DIR (untagged input): `/mnt/c/Users/User/Music/to-sort`
- LOSSLESS_DIR (organized/tagged lossless): `/mnt/c/Users/User/Music/lossless`
- MP3_DIR (organized/tagged MP3 tree): `/mnt/c/Users/User/Music/mp3`
- FLAT_DIR (flattened MP3 output): `/mnt/c/Users/User/Music/Bonneville`  ← replaces the old `mp3/result`

Override any default by exporting the corresponding environment variable, or by passing positional arguments where supported (see per-script notes).

Examples:
```bash
# Use a different flattened output directory for one run
FLAT_DIR="/mnt/c/Users/User/Music/MyFlat" ./create-genre-playlist.sh

# Override lossless/mp3 roots for conversion
LOSSLESS_DIR="/data/lossless" MP3_DIR="/data/mp3" ./organize-music-enhanced.sh
# See Quickstart below for PRESET_MODE (quality/bitrate), CONVERT_PARALLEL, and DRY_RUN examples.
```

---

## Recommended End-to-End Workflow

1) Tag and import untagged audio (non-interactive)
- Use tag-files.sh to import from TO_SORT_DIR into a curated lossless library using beets. This both organizes files and adds them to your beets DB.

2) Optional: Clean up duplicates created by prior tooling
- Use de-duplicate.sh to remove duplicate files such as “Track (1).mp3” if they match original content.

3) Build the MP3 tree
- organize-music-enhanced.sh (canonical):
  - Moves existing MP3s into a mirrored MP3 tree, converts lossless files to MP3, supports parallelism and optional artwork embedding.

4) Flatten the MP3 tree for portable consumption
- Run flatten-directories.sh to create a single flat directory at FLAT_DIR (default: `/mnt/c/Users/User/Music/Bonneville`) with conflict-free filenames.

5) Generate playlists (against the flat directory by default)
- Use create-genre-playlist.sh to generate genre_*.m3u and artist_*.m3u playlists.
- Use create-artist-playlists.sh for a simpler artist-only playlist generation.

6) Optional: Add MP3s to beets
- If you also want the MP3 tree in your beets library:
  ```bash
  beet import -A "$MP3_DIR"
  ```

---

## Script Reference

Below are details for each script: synopsis, parameters, behavior, outputs, dependencies, examples, and safety notes.

### tag-files.sh

Non-interactive beets import from a to-sort folder into an organized lossless library.

- Synopsis:
  - Creates (if missing) a non-interactive beets config and runs `beet import -A "$MUSIC_SOURCE"` to auto-apply tag matches and import files into a structured lossless library. By default it copies (move: no); set `import.move: yes` in your beets config if you want files moved (source removed).
- Arguments:
  - None. Variables (env or inline):
    - `TO_SORT_DIR` (default: `/mnt/c/Users/User/Music/to-sort`)
    - `LOSSLESS_DIR` (default: `/mnt/c/Users/User/Music/lossless`)
    - `MUSIC_SOURCE` (defaults to `TO_SORT_DIR`)
    - `OUTPUT_DIR` (defaults to `LOSSLESS_DIR`)
- Behavior:
  - Optionally sources `lib/deps.sh` to ensure dependencies.
  - Creates `~/.config/beets/config.yaml` if it does not exist, with non-interactive defaults and plugins (including `chroma` for acoustic fingerprinting). Leaves an existing config unchanged.
  - Runs `beet import -A "$MUSIC_SOURCE"` for automated tagging and import.
- Outputs:
  - Tagged and organized files in `$OUTPUT_DIR`, available in your beets library.
- Dependencies:
  - Python3/pip, beets and plugins noted above (including `chroma`), Chromaprint `fpcalc`.
- Example:
  ```bash
  TO_SORT_DIR="/mnt/c/Users/User/Music/to-sort" LOSSLESS_DIR="/mnt/c/Users/User/Music/lossless" ./tag-files.sh
  ```
- Safety:
  - The script only creates `~/.config/beets/config.yaml` if it does not exist; otherwise it leaves your config unchanged. If you want to change behavior (e.g., move instead of copy), edit your beets config and set:
    import:
      move: yes

---

### de-duplicate.sh

Remove duplicate files suffixed with “ (n)” if content-identical to the original.

- Synopsis:
  - Finds files with a “ (number)” suffix, compares size and content with non-suffixed original, and removes duplicates when identical.
- Arguments:
  - `MUSIC_ROOT` (env var; default: `/mnt/c/Users/User/Music`)
- Behavior:
  - Uses `find` to locate candidates, `stat -c%s` to compare sizes, and `cmp -s` for content comparison.
  - Removes duplicate if content-identical; otherwise logs differences.
- Outputs:
  - Deletes duplicate files; logs actions.
- Dependencies:
  - `find`, `sed`, `stat`, `cmp`.
- Example:
  ```bash
  MUSIC_ROOT="/mnt/c/Users/User/Music" ./de-duplicate.sh
  ```
- Safety:
  - Destructive (removes files). Consider testing on a copy or snapshot.

---

### copy-if-newer.sh

Propagate updated scripts into a target tree based on modification time.

- Synopsis:
  - For each `.ps1` or `.sh` file in the current directory, find files with the same name under `TARGET_DIR` and copy if the source is newer. Also (by default) propagates each script’s sibling `lib/deps.sh`.
- Arguments:
  - None. Edit/override:
    - `SOURCE_DIR="."`
    - `TARGET_DIR="/mnt/c/Users/User/Music"`
    - `COPY_LIB=1` (copy sibling lib/deps.sh when copying a .sh)
    - `SYNC_BEFORE=1` (run `./sync-deps-lib.sh --quiet` before copying)
- Behavior:
  - Recursively searches the target tree. Copies with `cp -p` if source is newer.
  - If no matches are found, optionally copy to a user-specified subdirectory (Enter for root).
- Outputs:
  - Updated script files under `TARGET_DIR` where applicable.
- Dependencies:
  - `find`, `cp`.
- Example:
  ```bash
  TARGET_DIR="/mnt/c/Users/User/Music" ./copy-if-newer.sh
  ```

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


---

### organize-music-enhanced.sh

Advanced MP3 pipeline with parallel conversion and optional artwork embedding.

- Synopsis:
  - Moves MP3s to a mirrored MP3 tree, compares/handles duplicates, builds a list of lossless files, and converts them to MP3—optionally in parallel—with normalized metadata and artwork embedding.
- Configuration variables:
  - Paths/flags:
    - `LOSSLESS_DIR` (default: `/mnt/c/Users/User/Music/lossless`)
    - `MP3_DIR` (default: `/mnt/c/Users/User/Music/mp3`)
    - `MUSIC_ROOT` (defaults to `LOSSLESS_DIR`)
    - `MP3_ROOT` (defaults to `MP3_DIR`)
    - `DRY_RUN`, `VERBOSE`, `CONVERT_MISSING_MP3`, `CONVERT_PARALLEL`, `THREADS=$(nproc)`
  - Quality: `MP3_QUALITY=2` (when `PRESET_MODE="quality"`), or `BITRATE="192k"` (when `PRESET_MODE="bitrate"`)
  - Artwork: `PRESERVE_ARTWORK=true`
  - Cleanup: `DELETE_ORIGINAL_MP3=true` (delete source MP3 after moving)
- Behavior:
  - Phase 1: Move MP3s to `MP3_ROOT`. If target exists, compare and handle duplicates.
  - Phase 2: Build a list of lossless files lacking MP3 counterparts, convert serially or in parallel.
- Outputs:
  - MP3 tree populated in `MP3_ROOT`, with optional artwork embedded.
- Dependencies:
  - `ffmpeg`, `ffprobe`, `jq`, `bc`, `xargs`, coreutils.
- Example:
  ```bash
  LOSSLESS_DIR="/data/lossless" MP3_DIR="/data/mp3" CONVERT_PARALLEL=true ./organize-music-enhanced.sh
  ```

---

### flatten-directories.sh

Flatten a directory tree into `FLAT_DIR` with stable, conflict-free filenames.

- Synopsis:
  - Moves `.mp3` files from a nested tree to a single `DEST_DIR` (defaults to `FLAT_DIR`), skipping exact duplicates (by content hash), and avoiding filename collisions with a short path hash and counters.
- Arguments:
  - `SOURCE_ROOT` (positional 1 or env; defaults to `MP3_DIR`)
  - `DEST_DIR` (positional 2 or env; defaults to `FLAT_DIR` = `/mnt/c/Users/User/Music/Bonneville`)
- Behavior:
  - Uses an associative array of content hashes to skip duplicates.
  - Computes a 6-char path hash from each file’s subdirectory (relative to `SOURCE_ROOT`) and prefixes it in the output filename.
  - Handles name collisions by appending ` (counter)`.
- Outputs:
  - Flat directory populated at `DEST_DIR`.
- Dependencies:
  - `md5sum`, `sha256sum`, `cmp`, `find`, `coreutils`.
- Example:
  ```bash
  MP3_DIR="/mnt/c/Users/User/Music/mp3" FLAT_DIR="/mnt/c/Users/User/Music/Bonneville" ./flatten-directories.sh
  ```

---

### create-genre-playlist.sh

Generate genre-based and artist-based M3U playlists from the flat directory by default.

- Synopsis:
  - Scans MP3 files, extracts artist and genre via beets (preferred), or falls back to `mid3v2`/`exiftool`. Writes playlists to a temp directory, then moves them to the final location.
- Arguments:
  - `MUSIC_DIR` (positional 1 or env; defaults to `FLAT_DIR` = `/mnt/c/Users/User/Music/Bonneville`)
  - `PLAYLIST_DIR` (positional 2 or env; defaults to `MUSIC_DIR`)
- Behavior:
  - For each MP3, determine artist and genres; sanitize names for filesystem safety.
  - Genre tags can be comma or semicolon separated; script splits and writes each to its own `genre_*.m3u`.
- Outputs:
  - Artist playlists: `artist_<Artist>.m3u`
  - Genre playlists: `genre_<Genre>.m3u`
- Dependencies:
  - `beet` (optional), `mid3v2` (optional), `exiftool` (optional), `find`.
- Example:
  ```bash
  ./create-genre-playlist.sh   # uses FLAT_DIR by default
  ```

---

### create-artist-playlists.sh

Generate one M3U playlist per artist using MP3 tags (defaults to flat directory).

- Synopsis:
  - Minimal version focusing only on artist-based playlists using `mid3v2` tag reading.
- Arguments:
  - `MUSIC_DIR` (positional 1 or env; defaults to `FLAT_DIR`)
  - `PLAYLIST_DIR` (positional 2 or env; defaults to `MUSIC_DIR`)
- Behavior:
  - Reads artist from ID3 tags; sanitizes the name; groups tracks per artist into M3U files in a temp directory then moves them to the destination.
- Outputs:
  - `<Artist>.m3u` under `PLAYLIST_DIR`.
- Dependencies:
  - `mid3v2`, `find`.
- Example:
  ```bash
  ./create-artist-playlists.sh   # uses FLAT_DIR by default
  ```

---

### investigate-genres.sh

Investigate genre tagging and playlist contents; useful for debugging metadata and playlist generation (defaults to flat directory).

- Synopsis:
  - Lists genre playlists in the current directory, samples contents, tests `beet list` genre extraction on a few files, prints ID3 genre frames, and counts playlist entries.
- Arguments:
  - `TARGET_DIR` positional or env var; defaults to `FLAT_DIR`
- Behavior:
  - Uses null-delimited loops (`-print0` and `read -d ''`) to handle unusual filenames safely.
  - Uses `beet list` with `realpath` for robust matching.
- Outputs:
  - Diagnostic console output.
- Dependencies:
  - `beet` (optional), `mid3v2`, `exiftool`, `realpath`, `find`, coreutils.
- Example:
  ```bash
  ./investigate-genres.sh   # uses FLAT_DIR by default
  ```

---

## Quickstart

1) Tag and import untagged audio to lossless library:
```bash
# Edit or export env vars if needed (TO_SORT_DIR, LOSSLESS_DIR)
./tag-files.sh
```

2) Convert to MP3 tree:
```bash
# Canonical (recommended)
PRESET_MODE=quality MP3_QUALITY=2 CONVERT_PARALLEL=true ./organize-music-enhanced.sh

# Serial/simple run (no parallelism)
CONVERT_PARALLEL=false ./organize-music-enhanced.sh

# Bitrate-based example (constant bitrate)
PRESET_MODE=bitrate BITRATE=192k ./organize-music-enhanced.sh

# Convert a single file (if supported)
# SINGLE_FILE should point to one lossless input to process
SINGLE_FILE="/path/to/track.flac" ./organize-music-enhanced.sh

# Note: Boolean env vars accept true/false.
```

3) Flatten MP3 tree into Bonneville:
```bash
./flatten-directories.sh
# → creates/uses /mnt/c/Users/User/Music/Bonneville
```

4) Generate playlists (defaults to Bonneville):
```bash
./create-genre-playlist.sh
# or
./create-artist-playlists.sh
```

5) Optional: Import MP3s into beets:
```bash
beet import -A "$MP3_DIR"
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

- Scripts prefer strict mode where applicable, null-delimited loops for filenames, and explicit error handling.
- Playlists and filenames are sanitized to avoid platform-invalid characters, with whitespace normalization as needed.
