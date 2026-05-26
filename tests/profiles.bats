#!/usr/bin/env bats

setup() {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"
}

teardown() {
  rm -rf mock
}

@test "awx profiles shows ACTIVE for profile with valid session" {
  # Mock aws: list-profiles returns one profile; sts succeeds
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  echo "my-profile"
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 0
fi
EOF
  chmod +x mock/bin/aws

  run ./awx profiles
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "my-profile".*"ACTIVE" ]]
}

@test "awx profiles shows EXPIRED for profile with invalid session" {
  # Mock aws: list-profiles returns one profile; sts fails (expired)
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  echo "expired-profile"
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 1
fi
EOF
  chmod +x mock/bin/aws

  run ./awx profiles
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "expired-profile".*"EXPIRED" ]]
}

@test "awx profiles outputs one line per profile" {
  # Mock aws: list-profiles returns two profiles; first active, second expired
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  printf "profile-a\nprofile-b\n"
elif [[ "$*" == *"sts get-caller-identity"* && "$*" == *"--profile profile-a"* ]]; then
  exit 0
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 1
fi
EOF
  chmod +x mock/bin/aws

  run ./awx profiles
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | grep -c 'ACTIVE\|EXPIRED')" -eq 2 ]
}

@test "awx profiles fails fast when aws CLI is missing" {
  PATH_BACKUP="$PATH"
  export PATH="/usr/bin:/bin"
  run ./awx profiles
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: aws" ]]
  export PATH="$PATH_BACKUP"
}

@test "awx profiles shows remaining duration for SSO profile with valid cache" {
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  echo "sso-profile"
elif [[ "$*" == *"configure get sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 0
fi
EOF
  chmod +x mock/bin/aws

  future_iso="$(date -v+5H -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -d "+5 hours" -u +%Y-%m-%dT%H:%M:%SZ)"
  export AWX_SSO_CACHE_DIR="$(mktemp -d)"
  cat > "$AWX_SSO_CACHE_DIR/cache.json" <<EOF
{
  "startUrl": "https://my-sso.awsapps.com/start",
  "expiresAt": "$future_iso"
}
EOF

  run ./awx profiles
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "sso-profile" ]]
  [[ "${output}" =~ "ACTIVE" ]]
  [[ "${output}" =~ "remaining" ]]
}

@test "awx profiles shows ACTIVE without duration for SSO profile with no cache" {
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  echo "sso-profile"
elif [[ "$*" == *"configure get sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 0
fi
EOF
  chmod +x mock/bin/aws

  export AWX_SSO_CACHE_DIR="$(mktemp -d)"

  run ./awx profiles
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "ACTIVE" ]]
  ! [[ "${output}" =~ "remaining" ]]
}

@test "awx profiles shows ACTIVE without duration for malformed cache" {
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  echo "sso-profile"
elif [[ "$*" == *"configure get sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 0
fi
EOF
  chmod +x mock/bin/aws

  export AWX_SSO_CACHE_DIR="$(mktemp -d)"
  echo "not valid json" > "$AWX_SSO_CACHE_DIR/cache.json"

  run ./awx profiles
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "ACTIVE" ]]
  ! [[ "${output}" =~ "remaining" ]]
}

@test "format_duration formats hours and minutes" {
  result=$(bash -c 'source ./awx 2>/dev/null; format_duration 18720')
  [ "$result" = "5h 12m" ]
}

@test "format_duration formats minutes only" {
  result=$(bash -c 'source ./awx 2>/dev/null; format_duration 2520')
  [ "$result" = "42m" ]
}

@test "format_duration formats less than 1 minute" {
  result=$(bash -c 'source ./awx 2>/dev/null; format_duration 30')
  [ "$result" = "<1m" ]
}

@test "format_duration formats hours only" {
  result=$(bash -c 'source ./awx 2>/dev/null; format_duration 3600')
  [ "$result" = "1h" ]
}
