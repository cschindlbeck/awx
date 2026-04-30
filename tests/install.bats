#!/usr/bin/env bats

# Tests for install.sh — the one-line installer for awx.
# These tests use a mock curl so that no real network requests are made.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
INSTALL_SCRIPT="${REPO_ROOT}/install.sh"

# ---------------------------------------------------------------------------
# Helpers: build a mock curl that copies the local awx script as the download
# ---------------------------------------------------------------------------
setup() {
  # A temp dir used as scratch space for every test
  TEST_TMP="$(mktemp -d)"

  # Minimal mock: copy the local 'awx' and completions/_awx so tests don't
  # need network access.  The mock accepts any URL and writes the matching
  # local file to the -o destination.
  MOCK_BIN="${TEST_TMP}/mock_bin"
  mkdir -p "$MOCK_BIN"

  # Write the mock with the repo root baked in so it works from any directory
  cat >"${MOCK_BIN}/curl" <<MOCK
#!/usr/bin/env bash
# Minimal curl mock: handles \`-sSL <url> -o <dest>\` used by install.sh
url=""
dest=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -sSL) url="\$2"; shift 2 ;;
    -o)   dest="\$2"; shift 2 ;;
    *)    shift ;;
  esac
done
REPO_ROOT="${REPO_ROOT}"
if [[ "\$url" == *"/awx" && "\$url" != *"/completions/"* ]]; then
  cp "\${REPO_ROOT}/awx" "\$dest"
elif [[ "\$url" == *"/completions/_awx"* ]]; then
  cp "\${REPO_ROOT}/completions/_awx" "\$dest"
else
  echo "mock curl: unknown url: \$url" >&2
  exit 1
fi
MOCK
  chmod +x "${MOCK_BIN}/curl"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# install.sh exists and is executable
# ---------------------------------------------------------------------------
@test "install.sh exists and is executable" {
  [ -f "$INSTALL_SCRIPT" ]
  [ -x "$INSTALL_SCRIPT" ]
}

# ---------------------------------------------------------------------------
# install.sh downloads awx to INSTALL_DIR
# ---------------------------------------------------------------------------
@test "install.sh installs awx to INSTALL_DIR" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  touch "$shell_rc"

  run env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    NO_MODIFY_SHELL_RC="true" \
    bash "$INSTALL_SCRIPT"

  [ "$status" -eq 0 ]
  [ -f "${install_dir}/awx" ]
  [ -x "${install_dir}/awx" ]
}

# ---------------------------------------------------------------------------
# install.sh adds source line to SHELL_RC
# ---------------------------------------------------------------------------
@test "install.sh adds source line to SHELL_RC" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  touch "$shell_rc"

  run env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    bash "$INSTALL_SCRIPT"

  [ "$status" -eq 0 ]
  grep -qF "source \"${install_dir}/awx\"" "$shell_rc"
}

# ---------------------------------------------------------------------------
# install.sh is idempotent — running twice does not duplicate source line
# ---------------------------------------------------------------------------
@test "install.sh is idempotent — source line appears exactly once after two runs" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  touch "$shell_rc"

  env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    bash "$INSTALL_SCRIPT"

  env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    bash "$INSTALL_SCRIPT"

  local count
  count="$(grep -cF "source \"${install_dir}/awx\"" "$shell_rc")"
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# NO_MODIFY_SHELL_RC=true skips shell rc modification
# ---------------------------------------------------------------------------
@test "NO_MODIFY_SHELL_RC=true skips adding source line" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  touch "$shell_rc"

  run env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    NO_MODIFY_SHELL_RC="true" \
    bash "$INSTALL_SCRIPT"

  [ "$status" -eq 0 ]
  ! grep -qF "source" "$shell_rc"
}

# ---------------------------------------------------------------------------
# install.sh exits with an error when curl is not available
# ---------------------------------------------------------------------------
@test "install.sh fails with clear error when curl is missing" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  local no_curl_bin="${TEST_TMP}/no_curl_bin"
  mkdir -p "$no_curl_bin"
  touch "$shell_rc"

  # Use an empty PATH so curl cannot be found; invoke bash by absolute path
  # so env does not need to locate it via PATH.
  run env PATH="$no_curl_bin" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    /bin/bash "$INSTALL_SCRIPT"

  [ "$status" -ne 0 ]
  [[ "$output" =~ "curl" ]]
}

# ---------------------------------------------------------------------------
# COMPLETIONS_DIR is respected when provided
# ---------------------------------------------------------------------------
@test "install.sh installs completion file when COMPLETIONS_DIR is set" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  local comp_dir="${TEST_TMP}/completions"
  touch "$shell_rc"

  run env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    NO_MODIFY_SHELL_RC="true" \
    COMPLETIONS_DIR="$comp_dir" \
    bash "$INSTALL_SCRIPT"

  [ "$status" -eq 0 ]
  [ -f "${comp_dir}/_awx" ]
}

# ---------------------------------------------------------------------------
# install.sh output includes success message
# ---------------------------------------------------------------------------
@test "install.sh prints installation-complete message on success" {
  local install_dir="${TEST_TMP}/bin"
  local shell_rc="${TEST_TMP}/.bashrc"
  touch "$shell_rc"

  run env PATH="${MOCK_BIN}:${PATH}" \
    INSTALL_DIR="$install_dir" \
    SHELL_RC="$shell_rc" \
    NO_MODIFY_SHELL_RC="true" \
    bash "$INSTALL_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Installation complete" ]]
}
