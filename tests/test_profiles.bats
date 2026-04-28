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
  [[ "${output}" =~ "my-profile" ]]
  [[ "${output}" =~ "ACTIVE" ]]
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
  [[ "${output}" =~ "expired-profile" ]]
  [[ "${output}" =~ "EXPIRED" ]]
}

@test "awx profiles outputs one line per profile" {
  # Mock aws: list-profiles returns two profiles; first active, second expired
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"configure list-profiles"* ]]; then
  printf "profile-a\nprofile-b\n"
elif [[ "$*" == *"sts get-caller-identity"* && "$*" == *"profile-a"* ]]; then
  exit 0
else
  exit 1
fi
EOF
  chmod +x mock/bin/aws

  run ./awx profiles
  [ "$status" -eq 0 ]
  [ "$(echo "${output}" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "awx profiles fails fast when aws CLI is missing" {
  PATH_BACKUP="$PATH"
  export PATH="/usr/bin:/bin"
  run ./awx profiles
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: aws" ]]
  export PATH="$PATH_BACKUP"
}
