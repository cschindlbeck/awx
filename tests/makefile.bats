#!/usr/bin/env bats

# Tests for the Makefile targets.
# Requires: make, bats, pre-commit to be available in PATH.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  cd "$REPO_ROOT"
}

# ---------------------------------------------------------------------------
# make help
# ---------------------------------------------------------------------------
@test "make help lists available targets" {
  run make help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "test" ]]
  [[ "$output" =~ "lint" ]]
  [[ "$output" =~ "check" ]]
  [[ "$output" =~ "install" ]]
  [[ "$output" =~ "dev" ]]
  [[ "$output" =~ "clean" ]]
}

# ---------------------------------------------------------------------------
# make test
# ---------------------------------------------------------------------------
@test "make test target is defined and calls bats" {
  # Use dry-run to verify the target exists and would invoke bats
  # (avoids recursive bats → make test → bats loop)
  run make -n test
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bats" ]]
}

# ---------------------------------------------------------------------------
# make lint
# ---------------------------------------------------------------------------
@test "make lint runs pre-commit hooks" {
  command -v pre-commit >/dev/null 2>&1 || skip "pre-commit not installed"
  run make lint
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# make check
# ---------------------------------------------------------------------------
@test "make check target depends on test and lint" {
  # Dry-run to verify the target exists and depends on test and lint
  run make -n check
  [ "$status" -eq 0 ]
  [[ "$output" =~ "bats" ]]
  [[ "$output" =~ "pre-commit" ]]
}

# ---------------------------------------------------------------------------
# make install / idempotency
# ---------------------------------------------------------------------------
@test "make install creates a symlink in INSTALL_DIR" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  run make install INSTALL_DIR="$tmp_dir"
  [ "$status" -eq 0 ]
  [ -L "$tmp_dir/awx" ]
  rm -rf "$tmp_dir"
}

@test "make install is idempotent (running twice does not fail)" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  run make install INSTALL_DIR="$tmp_dir"
  [ "$status" -eq 0 ]
  run make install INSTALL_DIR="$tmp_dir"
  [ "$status" -eq 0 ]
  [ -L "$tmp_dir/awx" ]
  rm -rf "$tmp_dir"
}

@test "make install symlink points to awx script" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  run make install INSTALL_DIR="$tmp_dir"
  [ "$status" -eq 0 ]
  local target
  target="$(readlink "$tmp_dir/awx")"
  [[ "$target" == *"/awx" ]]
  rm -rf "$tmp_dir"
}

# ---------------------------------------------------------------------------
# make dev
# ---------------------------------------------------------------------------
@test "make dev reports dependency status without error" {
  run make dev
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Checking development dependencies" ]]
}

# ---------------------------------------------------------------------------
# make clean
# ---------------------------------------------------------------------------
@test "make clean succeeds without errors" {
  run make clean
  [ "$status" -eq 0 ]
}
