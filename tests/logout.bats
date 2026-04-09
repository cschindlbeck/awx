#!/usr/bin/env bats

@test "awx logout with active session" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock AWS CLI to simulate a successful logout
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == "sso logout"* ]]; then
  echo "Logout successful"
  exit 0
else
  echo "Unknown command: $*" >&2
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  export AWS_PROFILE="valid_profile"

  run ./awx logout

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "ogged out of SSO session and cleared AWS_PROFILE for profile: valid_profile" ]]

  # Cleanup
  rm -rf mock
}

@test "awx logout without active session" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock AWS CLI to simulate no active session
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == "sso logout"* ]]; then
  echo "No active session to log out from" >&2
  exit 1
else
  echo "Unknown command: $*" >&2
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  export AWS_PROFILE="valid_profile"

  run ./awx logout

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Failed to log out of SSO session for profile: valid_profile" ]]

  # Cleanup
  rm -rf mock
}
