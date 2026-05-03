#!/usr/bin/env bats

# Tests for the `awx update` self-update subcommand.
# A mock curl is used so no real network requests are made.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  TEST_TMP="$(mktemp -d)"

  # Mock curl: copies the local awx script to the -o destination, simulating
  # a successful download of the latest version.
  MOCK_BIN="${TEST_TMP}/mock_bin"
  mkdir -p "$MOCK_BIN"

  cat >"${MOCK_BIN}/curl" <<MOCK
#!/usr/bin/env bash
# Minimal curl mock: handles \`curl -sSL <url> -o <dest>\` used by awx_update.
# -sSL are flags with no arguments; URL is the first positional argument.
url=""
dest=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) dest="\$2"; shift 2 ;;
    -*) shift ;;
    *)  [[ -z "\$url" ]] && url="\$1"; shift ;;
  esac
done
cp "${REPO_ROOT}/awx" "\$dest"
MOCK
  chmod +x "${MOCK_BIN}/curl"

  # Work on a copy of awx so we never modify the real script during tests.
  AWX_COPY="${TEST_TMP}/awx"
  cp "${REPO_ROOT}/awx" "$AWX_COPY"
  chmod +x "$AWX_COPY"
}

teardown() {
  rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# awx update replaces the script with the downloaded version
# ---------------------------------------------------------------------------
@test "awx update downloads latest awx and replaces itself" {
  run env PATH="${MOCK_BIN}:${PATH}" \
    AWX_UPDATE_URL="https://raw.githubusercontent.com/cschindlbeck/awx/main/awx" \
    bash "$AWX_COPY" update

  [ "$status" -eq 0 ]
  [[ "$output" =~ "updated successfully" ]]
  # The file should still exist and be executable
  [ -x "$AWX_COPY" ]
}

# ---------------------------------------------------------------------------
# awx update reports a useful message about reloading the shell
# ---------------------------------------------------------------------------
@test "awx update tells the user to reload the shell" {
  run env PATH="${MOCK_BIN}:${PATH}" \
    AWX_UPDATE_URL="https://raw.githubusercontent.com/cschindlbeck/awx/main/awx" \
    bash "$AWX_COPY" update

  [ "$status" -eq 0 ]
  [[ "$output" =~ "Reload your shell" ]]
}

# ---------------------------------------------------------------------------
# awx update fails with a clear error when curl is not available
# ---------------------------------------------------------------------------
@test "awx update fails with clear error when curl is missing" {
  local no_curl_bin="${TEST_TMP}/no_curl_bin"
  mkdir -p "$no_curl_bin"

  run env PATH="$no_curl_bin" /bin/bash "$AWX_COPY" update

  [ "$status" -ne 0 ]
  [[ "$output" =~ "curl" ]]
}

# ---------------------------------------------------------------------------
# awx update fails if the target file is not writable
# ---------------------------------------------------------------------------
@test "awx update fails when target file is not writable" {
  chmod -w "$AWX_COPY"

  run env PATH="${MOCK_BIN}:${PATH}" \
    AWX_UPDATE_URL="https://raw.githubusercontent.com/cschindlbeck/awx/main/awx" \
    bash "$AWX_COPY" update

  [ "$status" -ne 0 ]
  [[ "$output" =~ "Cannot write" ]]

  chmod +w "$AWX_COPY"
}
