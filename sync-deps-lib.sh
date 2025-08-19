#!/usr/bin/env bash
set -euo pipefail

# sync-deps-lib.sh — ensure a lib/deps.sh is present next to every *.sh script
# Canonical source: repo_root/lib/deps.sh (this script resolves repo_root from its own location)
#
# Usage:
#   ./sync-deps-lib.sh                # copy missing/changed deps.sh next to all scripts
#   ./sync-deps-lib.sh --dry-run      # show what would change
#   ./sync-deps-lib.sh --force        # overwrite even if identical
#   ./sync-deps-lib.sh --quiet        # minimal output
#
# Env (alternatives to flags):
#   DRY_RUN=1   (same as --dry-run)
#   FORCE=1     (same as --force)
#   QUIET=1     (same as --quiet)

DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
QUIET="${QUIET:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1; shift ;;
    --quiet)   QUIET=1; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine repository root:
# 1) Prefer Git toplevel if available
# 2) Otherwise, walk up from script_dir until a parent containing lib/deps.sh is found
repo_root=""
if command -v git >/dev/null 2>&1; then
  if top=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null); then
    repo_root="$top"
  fi
fi
if [[ -z "$repo_root" ]]; then
  candidate="$script_dir"
  while [[ "$candidate" != "/" && "$candidate" != "." ]]; do
    if [[ -f "$candidate/lib/deps.sh" ]]; then
      repo_root="$candidate"
      break
    fi
    candidate="$(dirname "$candidate")"
  done
fi

canonical="$repo_root/lib/deps.sh"

if [[ ! -f "$canonical" ]]; then
  echo "Error: canonical deps not found at: $canonical" >&2
  exit 1
fi

log() {
  if [[ "$QUIET" != "1" ]]; then
    echo "$@"
  fi
}

same_file() {
  # Return 0 if two paths refer to the same file on disk
  local a="$1" b="$2"
  [[ -e "$a" && -e "$b" ]] && [[ "$(realpath -m -- "$a")" == "$(realpath -m -- "$b")" ]]
}

# Stats
examined=0
created_dirs=0
copied=0
skipped_equal=0
skipped_self=0

log "Canonical source: $canonical"
if [[ "$DRY_RUN" == "1" ]]; then
  log "[DRY_RUN] No changes will be written"
fi

# Find all *.sh outside of ./lib
# Use null-delimited iteration to handle spaces/newlines
while IFS= read -r -d '' script_path; do
  examined=$((examined + 1))

  # Skip this sync script itself if it lives in a lib folder structure decision doesn't matter
  # (covered by generic logic anyway)
  script_dirname="$(dirname "$script_path")"
  target_dir="$script_dirname/lib"
  target="$target_dir/deps.sh"

  # Skip copying canonical onto itself
  if same_file "$target" "$canonical"; then
    skipped_self=$((skipped_self + 1))
    continue
  fi

  # Ensure target_dir exists
  if [[ ! -d "$target_dir" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[DRY_RUN] mkdir -p \"$target_dir\""
    else
      mkdir -p "$target_dir"
    fi
    created_dirs=$((created_dirs + 1))
  fi

  # Decide if we need to copy
  need_copy=0
  if [[ "$FORCE" == "1" ]]; then
    need_copy=1
  elif [[ ! -f "$target" ]]; then
    need_copy=1
  else
    if ! cmp -s "$canonical" "$target"; then
      need_copy=1
    fi
  fi

  if [[ "$need_copy" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[DRY_RUN] cp -p \"$canonical\" \"$target\""
    else
      cp -p "$canonical" "$target"
    fi
    copied=$((copied + 1))
  else
    skipped_equal=$((skipped_equal + 1))
  fi

done < <(find "$repo_root" -type f -name "*.sh" -not -path "$repo_root/lib/*" -print0)

log "Sync complete."
log "  Examined scripts: $examined"
log "  Directories created: $created_dirs"
log "  Files copied: $copied"
log "  Skipped (equal): $skipped_equal"
log "  Skipped (self/canonical): $skipped_self"
