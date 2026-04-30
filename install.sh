#!/usr/bin/env bash
# install.sh — one-line installer for awx
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/cschindlbeck/awx/main/install.sh | bash
#
# Environment overrides (all optional):
#   INSTALL_DIR          — destination directory          (default: ~/.local/bin)
#   SHELL_RC             — shell config file to update    (default: auto-detected)
#   COMPLETIONS_DIR      — directory for zsh completions  (default: auto-detected)
#   BRANCH               — GitHub branch to fetch from    (default: main)
#   NO_MODIFY_SHELL_RC   — set to "true" to skip rc edit  (default: false)

set -euo pipefail

REPO="cschindlbeck/awx"
BRANCH="${BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
AWX_DEST="${INSTALL_DIR}/awx"

# ---------------------------------------------------------------------------
# Color support — only emit escape codes when stdout is a TTY with 8+ colours
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && tput colors &>/dev/null && [[ "$(tput colors)" -ge 8 ]]; then
  COL_INFO="$(tput setaf 2)"
  COL_WARN="$(tput setaf 3)"
  COL_ERR="$(tput setaf 1)"
  COL_RESET="$(tput sgr0)"
else
  COL_INFO=""
  COL_WARN=""
  COL_ERR=""
  COL_RESET=""
fi

log() { printf "%s[INFO]%s %s\n" "$COL_INFO" "$COL_RESET" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$COL_WARN" "$COL_RESET" "$*" >&2; }
die() {
  printf "%s[ERROR]%s %s\n" "$COL_ERR" "$COL_RESET" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1. Please install it first."
}

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
require_cmd curl

# ---------------------------------------------------------------------------
# Download awx
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
log "Downloading awx from ${RAW_BASE}/awx ..."
curl -sSL "${RAW_BASE}/awx" -o "$AWX_DEST"
chmod +x "$AWX_DEST"
log "Installed: ${AWX_DEST}"

# ---------------------------------------------------------------------------
# PATH check
# ---------------------------------------------------------------------------
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    warn "${INSTALL_DIR} is not in your PATH."
    warn "Add the following line to your shell config:"
    warn "  export PATH=\"\$PATH:${INSTALL_DIR}\""
    ;;
esac

# ---------------------------------------------------------------------------
# Shell integration
# awx must be sourced (not just executed) so that AWS_PROFILE and kubeconfig
# changes propagate to the calling shell session.
# ---------------------------------------------------------------------------
_detect_shell_rc() {
  local shell_name
  shell_name="$(basename "${SHELL:-bash}")"
  case "$shell_name" in
    zsh) printf "%s/.zshrc" "$HOME" ;;
    bash) printf "%s/.bashrc" "$HOME" ;;
    *) printf "%s/.profile" "$HOME" ;;
  esac
}

SHELL_RC="${SHELL_RC:-$(_detect_shell_rc)}"
SOURCE_LINE="source \"${AWX_DEST}\""

if [[ "${NO_MODIFY_SHELL_RC:-}" == "true" ]]; then
  log "Skipping shell integration (NO_MODIFY_SHELL_RC=true)"
  log "To enable sourcing manually, add to your shell config: ${SOURCE_LINE}"
elif grep -qF "$SOURCE_LINE" "$SHELL_RC" 2>/dev/null; then
  log "Shell integration already present in ${SHELL_RC}"
else
  printf "\n# awx — AWS profile & EKS context switcher\n%s\n" "$SOURCE_LINE" >>"$SHELL_RC"
  log "Added shell integration to ${SHELL_RC}"
  log "Reload your shell: source ${SHELL_RC}"
fi

# ---------------------------------------------------------------------------
# Optional: Zsh completions
# ---------------------------------------------------------------------------
_install_completions() {
  local shell_name comp_dest
  shell_name="$(basename "${SHELL:-bash}")"
  comp_dest=""

  if [[ -n "${COMPLETIONS_DIR:-}" ]]; then
    comp_dest="${COMPLETIONS_DIR}/_awx"
  elif [[ "$shell_name" == "zsh" ]]; then
    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
      mkdir -p "${HOME}/.oh-my-zsh/completions"
      comp_dest="${HOME}/.oh-my-zsh/completions/_awx"
    else
      warn "Zsh completions not auto-installed."
      warn "Set COMPLETIONS_DIR and re-run, then add to .zshrc:"
      warn "  fpath=(\${COMPLETIONS_DIR} \$fpath); autoload -Uz compinit && compinit"
      return 0
    fi
  else
    return 0
  fi

  log "Downloading completions to ${comp_dest} ..."
  mkdir -p "$(dirname "$comp_dest")"
  curl -sSL "${RAW_BASE}/completions/_awx" -o "$comp_dest"
  log "Completions installed: ${comp_dest}"
}

_install_completions

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log ""
log "Installation complete!"
log "Run 'source ${SHELL_RC}' (or open a new terminal), then try: awx help"
