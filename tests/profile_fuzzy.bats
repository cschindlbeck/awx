#!/usr/bin/env bats

# ---------------------------------------------------------------------------
# Tests for graceful fuzzy profile fallback on partial/invalid profile input.
# ---------------------------------------------------------------------------

setup() {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Default mock aws: supports list-profiles, SSO, STS, EKS
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"configure list-profiles"*) printf "mock-alpha\nmock-beta\ndevProfile\n" ;;
  *"configure get sso_start_url"*) echo "https://mock.awsapps.com/start" ;;
  *"sts get-caller-identity"*) echo '{"UserId":"MOCK","Account":"123456789012","Arn":"arn:aws:sts::123456789012:assumed-role/mock/mock"}' ;;
  *"eks list-clusters"*) echo '{"clusters":["mock-cluster"]}' ;;
  *"eks update-kubeconfig"*) echo "Updated context" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x mock/bin/aws

  cat >mock/bin/jq <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
  chmod +x mock/bin/jq

  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
}

teardown() {
  rm -rf mock
  rm -f "${AWX_STATE_FILE:-}"
}

# ---------------------------------------------------------------------------
# Test 1: Exact match — proceeds normally without fzf
# ---------------------------------------------------------------------------
@test "exact profile match proceeds without fzf" {
  # fzf is stubbed to satisfy check_deps but must NOT be invoked for profile
  # selection — if it were, the mock would emit a detectable message and the
  # assertion on "Using profile: mock-alpha" would still hold, but the presence
  # of "fzf-invoked" in the output would reveal the unwanted call.
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
echo "fzf-invoked"
exit 1
EOF
  chmod +x mock/bin/fzf

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile mock-alpha

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-alpha" ]]
  ! [[ "${output}" =~ "fzf-invoked" ]]
}

# ---------------------------------------------------------------------------
# Test 2: Partial match shortcut — fzf opened with filtered results
# ---------------------------------------------------------------------------
@test "partial profile shortcut opens fzf with filtered results" {
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
# Receive filtered list on stdin and return first match
echo "mock-alpha"
EOF
  chmod +x mock/bin/fzf

  # Shortcut syntax triggers fuzzy resolve; --profile is always exact
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx mock-al

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-alpha" ]]
}

# ---------------------------------------------------------------------------
# Test 3: No match — warn and exit gracefully
# ---------------------------------------------------------------------------
@test "no matching profile shows warning and exits gracefully" {
  # fzf must exist for check_deps but must NOT be called (no match → early exit)
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
echo "fzf-invoked"
exit 1
EOF
  chmod +x mock/bin/fzf

  # Shortcut syntax triggers fuzzy resolve
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx zzz-nonexistent

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No matching AWS profile found for 'zzz-nonexistent'" ]]
  ! [[ "${output}" =~ "fzf-invoked" ]]
}

# ---------------------------------------------------------------------------
# Test 4: Case-insensitive partial matching
# ---------------------------------------------------------------------------
@test "profile matching is case-insensitive" {
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
echo "mock-alpha"
EOF
  chmod +x mock/bin/fzf

  # Shortcut syntax triggers fuzzy resolve; --profile is always exact
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx MOCK-AL

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-alpha" ]]
}

# ---------------------------------------------------------------------------
# Test 5: Shortcut syntax (awx <partial-profile>) also uses fuzzy fallback
# ---------------------------------------------------------------------------
@test "profile shortcut with partial name triggers fuzzy fallback" {
  cat >mock/bin/fzf <<'EOF'
#!/usr/bin/env bash
echo "devProfile"
EOF
  chmod +x mock/bin/fzf

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx dev

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: devProfile" ]]
}
