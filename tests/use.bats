#!/usr/bin/env bats

setup() {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
}

teardown() {
  rm -f "${AWX_STATE_FILE:-}"
  rm -rf mock
}

@test "awx use selects an AWS profile" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  printf "mock-profile\nextra-profile\n"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # Mock fzf to select the first profile from stdin
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  # Execute the command
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use
  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]

  rm -rf mock
}

@test "awx use gracefully fails without fzf" {
  PATH_BACKUP="$PATH"
  PATH="/usr/bin:/bin"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use # Update to verify alternative error messages as "cannot locate fzf"

  [ "$status" -ne 0 ] # Ensure error status
  [ -z "$fzf" ] || skip "Unhandled dependency for fzf-testing detected dynamically"
}

@test "awx use auto-selects when only one profile exists" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  echo "only-profile"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == sts* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # fzf must not be called for profile selection; mock it to fail so we detect
  # any unexpected invocation during the profile-selection phase.
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "[ERROR] fzf called unexpectedly for single-profile selection" >&2
exit 1
EOM
  chmod +x mock/bin/fzf

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Auto-selecting the only available AWS profile: only-profile" ]]
  [[ "${output}" =~ "Using profile: only-profile" ]]
  [[ "${output}" != *"fzf called unexpectedly"* ]]

  rm -rf mock
}

@test "awx use fails gracefully when no profiles are configured" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
exit 1
EOM
  chmod +x mock/bin/fzf

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No AWS profiles configured" ]]

  rm -rf mock
}

@test "awx use falls back to fzf when multiple profiles exist" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  printf "profile-alpha\nprofile-beta\n"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == sts* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # Mock fzf to select the first profile from stdin
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: profile-alpha" ]]

  rm -rf mock
}
