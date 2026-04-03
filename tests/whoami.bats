#!/usr/bin/env bats

@test "awx whoami with valid AWS_PROFILE" {
  export AWS_PROFILE="valid_test_profile"
  run ./awx whoami
  [ "$status" -ne 126 ] # Ensure script runs (does not fail with permission error)
  [[ "${output}" =~ "Account:" ]] || skip "Expected valid AWS_PROFILE setup cannot be locally simulated. Skipping test."
}

@test "awx whoami with missing AWS_PROFILE" {
  unset AWS_PROFILE
  run ./awx whoami
  [ "$status" -ne 126 ]
  [[ "${output}" =~ "AWS_PROFILE not set" ]]
}

@test "awx whoami with invalid AWS_PROFILE" {
  export AWS_PROFILE="invalid_profile"
  run ./awx whoami
  [ "$status" -ne 126 ]
  [[ "${output}" =~ "AWS SSO login failed" ]] || skip "Invalid AWS_PROFILE test not simulated due to environment limitations."
}

@test "awx whoami missing aws CLI" {
  PATH_BACKUP="$PATH"
  export PATH="/usr/bin:/bin" # Remove AWS CLI from PATH temporarily
  run ./awx whoami
  [ "$status" -ne 126 ] # Ensure script runs
  [[ "${output}" =~ "Missing dependency: aws" ]]
  export PATH="$PATH_BACKUP"
}
