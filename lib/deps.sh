# shellcheck shell=bash
# Reusable dependency helpers for music scripts (Debian/Ubuntu/WSL focused)

# Env flags:
#   NO_SUDO=1           -> do not use sudo (print instructions instead)
#   DRY_RUN=1           -> print actions instead of executing
#   ENSURE_PIP_SYSTEM=1 -> install Python packages system-wide (pip3) instead of --user

add_user_local_bin_to_path() {
  # Add ~/.local/bin to PATH for pip --user installations
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}

_is_cmd() { command -v "$1" >/dev/null 2>&1; }
_has_apt() { command -v apt-get >/dev/null 2>&1; }
_can_sudo() { command -v sudo >/dev/null 2>&1; }

_install_apt() {
  # Usage: _install_apt pkg1 pkg2 ...
  if ! _has_apt; then
    echo "apt-get not found; cannot install: $*" >&2
    return 1
  fi
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] apt-get update && apt-get install -y $*"
    return 0
  fi
  if [ "${NO_SUDO:-0}" = "1" ]; then
    echo "NO_SUDO=1 set; please run: sudo apt-get update && sudo apt-get install -y $*" >&2
    return 1
  fi
  if _can_sudo; then
    sudo apt-get update && sudo apt-get install -y "$@"
  else
    echo "sudo not available; please run as root: apt-get update && apt-get install -y $*" >&2
    return 1
  fi
}

_install_pip_user() {
  # Usage: _install_pip_user spec1 spec2 ...
  # In virtualenvs, --user is not allowed; fall back to system install.
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo "Virtualenv detected; using system pip install for: $*"
    _install_pip_system "$@" || return $?
    return 0
  fi
  add_user_local_bin_to_path
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] python3 -m pip install -U --user $*"
    return 0
  fi
  python3 -m pip install -U --user "$@"
}

_install_pip_system() {
  # Usage: _install_pip_system spec1 spec2 ...
  if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "[DRY_RUN] python3 -m pip install -U $*"
    return 0
  fi
  if [ "${NO_SUDO:-0}" = "1" ]; then
    echo "NO_SUDO=1 set; please run: sudo python3 -m pip install -U $*" >&2
    return 1
  fi
  if _can_sudo; then
    sudo python3 -m pip install -U "$@"
  else
    echo "sudo not available; please run as root: python3 -m pip install -U $*" >&2
    return 1
  fi
}

# Command-to-package mapping (Debian/Ubuntu)
# apt packages
declare -A _APT_MAP
_APT_MAP[ffmpeg]=ffmpeg          # provides ffmpeg + ffprobe
_APT_MAP[ffprobe]=ffmpeg
_APT_MAP[fpcalc]=chromaprint-tools
_APT_MAP[jq]=jq
_APT_MAP[bc]=bc
_APT_MAP[exiftool]=libimage-exiftool-perl
_APT_MAP[pip]=python3-pip
_APT_MAP[python3]=python3

# pip packages
declare -A _PIP_MAP
_PIP_MAP[beet]='beets[fetchart,lyrics,lastgenre,discogs]'
_PIP_MAP[mid3v2]=mutagen         # mid3v2 comes from mutagen

# Attempt to install a single command
ensure_cmd() {
  local cmd="$1"
  # Already present?
  if _is_cmd "$cmd"; then
    return 0
  fi

  # Try apt mapping first if exists
  if [ -n "${_APT_MAP[$cmd]+x}" ]; then
    local pkg="${_APT_MAP[$cmd]}"
    echo "Installing '$cmd' via apt package '$pkg'..."
    _install_apt "$pkg" || true
    if _is_cmd "$cmd"; then
      return 0
    fi
  fi

  # Try pip mapping next
  if [ -n "${_PIP_MAP[$cmd]+x}" ]; then
    local spec="${_PIP_MAP[$cmd]}"
    echo "Installing '$cmd' via pip spec '$spec'..."
    if [ "${ENSURE_PIP_SYSTEM:-0}" = "1" ]; then
      _install_pip_system "$spec" || true
    else
      _install_pip_user "$spec" || true
    fi
    # Some pip-provided commands land in ~/.local/bin; ensure PATH contains it
    add_user_local_bin_to_path
    hash -r 2>/dev/null || true
    if _is_cmd "$cmd"; then
      return 0
    fi
  fi

  # Not installed
  echo "Warning: Could not ensure installation for command '$cmd' automatically." >&2
  return 1
}

# Ensure a list of commands exists; returns non-zero if any required command missing
ensure_deps() {
  local missing=0
  local c
  for c in "$@"; do
    if ! _is_cmd "$c"; then
      ensure_cmd "$c" || missing=$((missing + 1))
    fi
  done
  if [ "$missing" -gt 0 ]; then
    echo "One or more required commands are still missing ($missing). Please install manually." >&2
    return 1
  fi
  return 0
}
