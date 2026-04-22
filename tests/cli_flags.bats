#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
setup() {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Default mock: aws always succeeds (profile selection / STS / kubeconfig)
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
# Minimal aws mock
case "$*" in
  *"configure list-profiles"*) echo "mock-profile" ;;
  *"configure get sso_start_url"*) echo "https://mock.awsapps.com/start" ;;
  *"sts get-caller-identity"*) echo '{"UserId":"MOCK","Account":"123456789012","Arn":"arn:aws:sts::123456789012:assumed-role/mock/mock"}' ;;
  *"eks list-clusters"*) echo '{"clusters":["mock-cluster"]}' ;;
  *"eks update-kubeconfig"*) echo "Updated context mock-profile in ~/.kube/config" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x mock/bin/aws

  # Default mock: jq passes through
  cat >mock/bin/jq <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
  chmod +x mock/bin/jq
}

teardown() {
  rm -rf mock
}

# ---------------------------------------------------------------------------
# Test 1: --profile flag skips interactive fzf profile selection
# ---------------------------------------------------------------------------
@test "awx use --profile X sets profile non-interactively" {
  # fzf is NOT mocked — if it were called it would fail (not in PATH)
  # The test succeeds only if fzf is never invoked for profile selection.
  run ./awx use --profile mock-profile

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]
}

# ---------------------------------------------------------------------------
# Test 2: --profile and --cluster fully non-interactive
# ---------------------------------------------------------------------------
@test "awx use --profile X --cluster Y is fully non-interactive" {
  # fzf is NOT mocked — test passes only if fzf is never called.
  run ./awx use --profile mock-profile --cluster mock-cluster

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]
  [[ "${output}" =~ "Updating kubeconfig for cluster: mock-cluster" ]]
}

# ---------------------------------------------------------------------------
# Test 3: awx <profile> shortcut behaves like awx use --profile <profile>
# ---------------------------------------------------------------------------
@test "awx <profile> shortcut sets profile non-interactively" {
  run ./awx mock-profile

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]
}

# ---------------------------------------------------------------------------
# Test 4: Unknown flag exits with an error
# ---------------------------------------------------------------------------
@test "awx use --invalid-flag exits non-zero with error" {
  run ./awx use --invalid-flag

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Unknown flag" ]] || [[ "${output}" =~ "ERROR" ]]
}

# ---------------------------------------------------------------------------
# Test 5: awx use with no flags still uses fzf interactively (regression)
# ---------------------------------------------------------------------------
@test "awx use without flags falls back to interactive fzf" {
  # Mock fzf to return a profile
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
echo "mock-profile"
EOF
  chmod +x mock/bin/fzf

  run ./awx use

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]
}

# ---------------------------------------------------------------------------
# Test 6: awx --profile X (top-level flag, no 'use' subcommand)
# Regression test: previously treated --profile as the profile name itself
# ---------------------------------------------------------------------------
@test "awx --profile X (top-level flag) sets profile non-interactively" {
  run ./awx --profile mock-profile

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]
  ! [[ "${output}" =~ "Using profile: --profile" ]]
}
