#!/usr/bin/env bash
set -euo pipefail

# install-tools.sh — Bootstrap required tools for the music scripts (Debian/Ubuntu/WSL focused)
#
# Installs:
#   - apt packages: ffmpeg (ffprobe), jq, bc, libimage-exiftool-perl, python3-pip, libchromaprint-tools (fpcalc) [fallbacks: chromaprint-tools, acoustid-fingerprinter, or chromaprint]
#   - pip packages: beets[fetchart,lyrics,lastgenre,discogs], mutagen (mid3v2), pyacoustid
#
# Flags:
#   --no-sudo         Do not use sudo; print the commands instead
#   --pip-system      Install Python packages system-wide (default: --user)
#   --dry-run         Print actions without executing
#   --use-venv        Use a Python virtual environment for pip installs
#   --venv <dir>      Specify virtual environment directory (default: .venv)
#
# Environment (alternative to flags):
#   NO_SUDO=1           (same as --no-sudo)
#   ENSURE_PIP_SYSTEM=1 (same as --pip-system)
#   DRY_RUN=1           (same as --dry-run)
#
# Usage:
#   ./install-tools.sh
#   NO_SUDO=1 DRY_RUN=1 ./install-tools.sh

# Read environment variables or set defaults
NO_SUDO="${NO_SUDO:-0}"
ENSURE_PIP_SYSTEM="${ENSURE_PIP_SYSTEM:-0}"
DRY_RUN="${DRY_RUN:-0}"
USE_VENV="${USE_VENV:-0}"
VENV_DIR="${VENV_DIR:-.venv}"

# Parse command-line arguments
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

# Helper: check if a command exists
is_cmd() { command -v "$1" >/dev/null 2>&1; }

# Helper: check if sudo and apt-get are available
can_sudo() { command -v sudo >/dev/null 2>&1; }
has_apt() { command -v apt-get >/dev/null 2>&1; }

# Helper: run a command, or just print it if DRY_RUN is set
run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] $*"
    return 0
  else
    "$@"
    return $?
  fi
}

# Install apt packages, using sudo if available and not disabled
apt_install() {
  local pkgs=("$@")
  if ! has_apt; then
    echo "apt-get not found; this installer targets Debian/Ubuntu/WSL." >&2
    return 1
  fi
  if [[ "$NO_SUDO" == "1" ]]; then
    echo "NO_SUDO=1 set; please run:" >&2
    echo "  sudo apt-get update && sudo apt-get install -y ${pkgs[*]}" >&2
    return 1
  fi
  if can_sudo; then
    run_cmd sudo apt-get update
    run_cmd sudo apt-get install -y "${pkgs[@]}"
  else
    echo "sudo not available; please run as root:" >&2
    echo "  apt-get update && apt-get install -y ${pkgs[*]}" >&2
    return 1
  fi
}

# Ensure ~/.local/bin is in PATH for pip --user installs
ensure_user_local_bin() {
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

# Install a pip package for the user (in a venv, install into the venv)
pip_install_user() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    echo "Virtualenv detected; installing into venv for: $1"
    run_cmd "${VIRTUAL_ENV}/bin/python" -m pip install -U -- "$1"
    return $?
  fi
  ensure_user_local_bin
  run_cmd python3 -m pip install -U --user -- "$1"
}

# Install a pip package system-wide (using sudo if available)
pip_install_system() {
  if [[ "$NO_SUDO" == "1" ]]; then
    echo "NO_SUDO=1 set; please run:" >&2
    if python3 -m pip help install 2>/dev/null | grep -q -- '--break-system-packages'; then
      echo "  sudo python3 -m pip install -U --break-system-packages \"$1\"" >&2
    else
      echo "  sudo python3 -m pip install -U \"$1\"" >&2
    fi
    return 1
  fi
  if can_sudo; then
    if python3 -m pip help install 2>/dev/null | grep -q -- '--break-system-packages'; then
      run_cmd sudo python3 -m pip install -U --break-system-packages -- "$1"
    else
      run_cmd sudo python3 -m pip install -U -- "$1"
    fi
  else
    echo "sudo not available; please run as root:" >&2
    if python3 -m pip help install 2>/dev/null | grep -q -- '--break-system-packages'; then
      echo "  python3 -m pip install -U --break-system-packages \"$1\"" >&2
    else
      echo "  python3 -m pip install -U \"$1\"" >&2
    fi
    return 1
  fi
}

# --- Main installation steps ---

echo "==> Installing apt packages (ffmpeg jq bc exiftool python3-pip)..."
PKGS=(ffmpeg jq bc libimage-exiftool-perl python3-pip)
# Add python3-venv if using a venv and not already in one
if [[ "$USE_VENV" == "1" && -z "${VIRTUAL_ENV:-}" ]]; then
  PKGS+=(python3-venv)
fi
apt_install "${PKGS[@]}" || true

# Try to install fpcalc (Chromaprint) using the best available package
if ! is_cmd fpcalc; then
  echo "==> Installing Chromaprint tool (fpcalc)..."
  apt_install libchromaprint-tools || apt_install chromaprint-tools || apt_install acoustid-fingerprinter || apt_install chromaprint || true
fi

# Install Python packages, using a venv if requested or active
if [[ "$USE_VENV" == "1" || -n "${VIRTUAL_ENV:-}" ]]; then
  # If already in a venv, use it; otherwise, create one
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

  # Upgrade pip in the venv
  echo "==> Ensuring venv pip is up-to-date..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY_RUN] \"$VENV_BIN/python\" -m pip install -U pip"
  else
    "$VENV_BIN/python" -m pip install -U pip || true
  fi

  # Install required Python packages in the venv
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
  # Not using a venv: upgrade pip and install packages (system or user)
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

# Ensure the 'acoustid' Python module is available for the 'beet' command
echo "==> Ensuring 'acoustid' module is present for the Python env used by 'beet'..."
if command -v beet >/dev/null 2>&1; then
  BEET_EXE="$(command -v beet)"
  PY_INTERP=""
  # Try to extract the Python interpreter from the beet shebang
  if head -n1 "$BEET_EXE" | grep -aq '^#!'; then
    SHEBANG_LINE="$(head -n1 "$BEET_EXE" | sed 's/^#!//')"
    read -r -a _tok <<<"$SHEBANG_LINE"
    FIRST="${_tok[0]:-}"
    if [ "$(basename "${FIRST:-}" 2>/dev/null)" = "env" ]; then
      # If using env, find the python interpreter in the shebang
      _rest=("${_tok[@]:1}")
      if [[ "${_rest[0]:-}" == "-S" ]]; then
        _rest=("${_rest[@]:1}")
      fi
      PY_INTERP=""
      for t in "${_rest[@]}"; do
        if [[ "$t" =~ (^|/|\\)python[0-9.]*$ ]]; then
          PY_INTERP="$t"
          break
        fi
      done
      PY_INTERP="${PY_INTERP:-${_rest[0]:-}}"
    else
      PY_INTERP="$FIRST"
    fi
  fi
  # Fallback to python3 if not found
  PY_INTERP="$(echo "${PY_INTERP:-}" | awk '{$1=$1;print}')"
  if [[ -z "$PY_INTERP" ]]; then
    PY_INTERP="python3"
  fi
  # Check if acoustid is installed for this interpreter
  NEEDS_INSTALL="$("$PY_INTERP" -c 'import importlib; print("0" if importlib.util.find_spec("acoustid") else "1")' 2>/dev/null || echo 1)"
  if [[ "$NEEDS_INSTALL" == "1" ]]; then
    IN_VENV="$("$PY_INTERP" -c 'import sys; print("1" if getattr(sys, "base_prefix", sys.prefix) != sys.prefix else "0")' 2>/dev/null || echo 0)"
    if [[ "$IN_VENV" == "1" ]]; then
      run_cmd "$PY_INTERP" -m pip install -U pyacoustid || true
    else
      run_cmd "$PY_INTERP" -m pip install -U --user pyacoustid || true
    fi
  fi
fi

# Print versions of installed tools for verification
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
