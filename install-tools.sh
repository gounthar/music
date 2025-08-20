#!/usr/bin/env bash
set -euo pipefail

# install-tools.sh — Bootstrap required tools for the music scripts (Debian/Ubuntu/WSL focused)
#
# Installs:
#   - apt packages: ffmpeg (ffprobe), jq, bc, libimage-exiftool-perl, python3-pip, chromaprint-tools (fpcalc)
#   - pip packages: beets[fetchart,lyrics,lastgenre,discogs], mutagen (mid3v2), pyacoustid
#
# Flags:
#   --no-sudo         Do not use sudo; print the commands instead
#   --pip-system      Install Python packages system-wide (default: --user)
#   --dry-run         Print actions without executing
# bash install-tools.sh --use-venv --venv .venv
# Environment (alternative to flags):
#   NO_SUDO=1           (same as --no-sudo)
#   ENSURE_PIP_SYSTEM=1 (same as --pip-system)
#   DRY_RUN=1           (same as --dry-run)
#
# Usage:
#   ./install-tools.sh
#   NO_SUDO=1 DRY_RUN=1 ./install-tools.sh

NO_SUDO="${NO_SUDO:-0}"
ENSURE_PIP_SYSTEM="${ENSURE_PIP_SYSTEM:-0}"
DRY_RUN="${DRY_RUN:-0}"
USE_VENV="${USE_VENV:-0}"
VENV_DIR="${VENV_DIR:-.venv}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sudo) NO_SUDO=1; shift ;;
    --pip-system) ENSURE_PIP_SYSTEM=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --use-venv) USE_VENV=1; shift ;;
    --venv) VENV_DIR="${2:-.venv}"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

is_cmd() { command -v "$1" >/dev/null 2>&1; }

can_sudo() { command -v sudo >/dev/null 2>&1; }
has_apt() { command -v apt-get >/dev/null 2>&1; }

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] $*"
    return 0
  else
    "$@"
    return $?
  fi
}

apt_install() {
  local pkgs=("$@")
  if ! has_apt; then
    echo "apt-get not found; this installer targets Debian/Ubuntu/WSL." >&2
    return 1
  fi
  if [[ "$NO_SUDO" == "1" ]]; then
    echo "NO_SUDO=1 set; please run:" >&2
    echo "  sudo apt-get update && sudo apt-get install -y ${pkgs[@]}" >&2
    return 1
  fi
  if can_sudo; then
    run_cmd sudo apt-get update
    run_cmd sudo apt-get install -y "${pkgs[@]}"
  else
    echo "sudo not available; please run as root:" >&2
    echo "  apt-get update && apt-get install -y ${pkgs[@]}" >&2
    return 1
  fi
}

ensure_user_local_bin() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

pip_install_user() {
  # In virtualenvs, --user is not allowed; fall back to system install.
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    echo "Virtualenv detected; using system pip install for: $1"
    pip_install_system "$1" || return 1
    return 0
  fi
  ensure_user_local_bin
  run_cmd python3 -m pip install -U --user -- "$1"
}

pip_install_system() {
  if [[ "$NO_SUDO" == "1" ]]; then
    echo "NO_SUDO=1 set; please run:" >&2
    echo "  sudo python3 -m pip install -U \"$1\"" >&2
    return 1
  fi
  if can_sudo; then
    run_cmd sudo python3 -m pip install -U -- "$1"
  else
    echo "sudo not available; please run as root:" >&2
    echo "  python3 -m pip install -U \"$1\"" >&2
    return 1
  fi
}

echo "==> Installing apt packages (ffmpeg jq bc exiftool python3-pip)..."
PKGS=(ffmpeg jq bc libimage-exiftool-perl python3-pip chromaprint-tools)
# If we'll create a venv (or user asked to use one and none is active), ensure python3-venv is present
if [[ "$USE_VENV" == "1" && -z "${VIRTUAL_ENV:-}" ]]; then
  PKGS+=(python3-venv)
fi
apt_install "${PKGS[@]}" || true

# Python packages: install either into a virtualenv (preferred if requested/active) or user/system site
if [[ "$USE_VENV" == "1" || -n "${VIRTUAL_ENV:-}" ]]; then
  # Determine venv dir/bin
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    VENV_DIR="$VIRTUAL_ENV"
  else
    echo "==> Creating virtual environment at: $VENV_DIR"
    if [[ "$DRY_RUN" == "1" ]]; then
      echo "[DRY_RUN] python3 -m venv \"$VENV_DIR\""
    else
      python3 -m venv "$VENV_DIR"
    fi
  fi
  VENV_BIN="$VENV_DIR/bin"

  echo "==> Ensuring venv pip is up-to-date..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] \"$VENV_BIN/python\" -m pip install -U pip"
  else
    "$VENV_BIN/python" -m pip install -U pip || true
  fi

  echo "==> Installing Python packages into virtualenv (beets + plugins, mutagen)..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] \"$VENV_BIN/python\" -m pip install -U \"beets[fetchart,lyrics,lastgenre,discogs]\""
    echo "[DRY_RUN] \"$VENV_BIN/python\" -m pip install -U mutagen"
    echo "[DRY_RUN] \"$VENV_BIN/python\" -m pip install -U pyacoustid"
  else
    "$VENV_BIN/python" -m pip install -U "beets[fetchart,lyrics,lastgenre,discogs]"
    "$VENV_BIN/python" -m pip install -U mutagen
    "$VENV_BIN/python" -m pip install -U pyacoustid
  fi

  echo "==> Virtualenv ready. To use CLI tools in your shell session, run:"
  echo "    source \"$VENV_DIR/bin/activate\""
else
  echo "==> Ensuring pip is up-to-date..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] python3 -m pip install -U pip"
  else
    python3 -m pip install -U pip || true
  fi

  echo "==> Installing Python packages (beets + plugins, mutagen)..."
  if [[ "$ENSURE_PIP_SYSTEM" == "1" ]]; then
    pip_install_system "beets[fetchart,lyrics,lastgenre,discogs]"
    pip_install_system "mutagen"
    pip_install_system "pyacoustid"
  else
    pip_install_user "beets[fetchart,lyrics,lastgenre,discogs]"
    pip_install_user "mutagen"
    pip_install_user "pyacoustid"
  fi
fi

echo "==> Verifying installations (versions)..."
ensure_user_local_bin
{
  echo "# Versions"
  is_cmd ffmpeg && ffmpeg -version | head -n1 || echo "ffmpeg: not found"
  is_cmd ffprobe && ffprobe -version | head -n1 || echo "ffprobe: not found"
  is_cmd fpcalc && fpcalc -version || echo "fpcalc: not found"
  is_cmd jq && jq --version || echo "jq: not found"
  is_cmd bc && bc --version 2>/dev/null | head -n1 || echo "bc: not found"
  is_cmd exiftool && exiftool -ver || echo "exiftool: not found"
  is_cmd python3 && python3 --version || echo "python3: not found"
  is_cmd pip && pip --version || echo "pip: not found"
  is_cmd beet && beet version || echo "beet: not found"
  is_cmd mid3v2 && mid3v2 --version || echo "mid3v2: not found"
} | sed 's/^/  /'

echo "==> Done."
echo "Note: If beet or mid3v2 are still not found, ensure '~/.local/bin' is on your PATH (for pip --user installs)."
