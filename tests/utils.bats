#!/usr/bin/env bats

setup() {
  export AWX_CACHE_DIR="$(mktemp -d)"
  export AWX_STATE_DIR="$(mktemp -d)"
  export AWX_SSO_CACHE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -rf "${AWX_STATE_DIR:-}"
  rm -rf "${AWX_SSO_CACHE_DIR:-}"
  rm -rf mock
}

@test "awx current with AWS_PROFILE set" {
  export AWS_PROFILE="test-profile"
  export AWS_REGION="eu-west-1"
  run ./awx current
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Profile: test-profile" ]]
  [[ "${output}" =~ "Region: eu-west-1" ]]
}

@test "awx current with AWS_PROFILE unset" {
  unset AWS_PROFILE
  export AWS_REGION="eu-west-1"
  run ./awx current
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Profile: <unset>" ]]
}

@test "awx current with kubectl context available" {
  export AWS_PROFILE="test-profile"
  export AWS_REGION="eu-central-1"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config current-context" ]]; then
  echo "test-cluster"
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/kubectl

  run ./awx current
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "test-cluster" ]]
}

@test "awx clear unsets environment variables" {
  source ./awx
  export AWS_PROFILE="test-profile"
  export AWS_REGION="eu-central-1"
  export AWS_DEFAULT_REGION="eu-central-1"

  awx_clear

  [[ -z "${AWS_PROFILE:-}" ]]
  [[ -z "${AWS_REGION:-}" ]]
  [[ -z "${AWS_DEFAULT_REGION:-}" ]]
}

@test "awx clear removes cache and state directories" {
  touch "$AWX_CACHE_DIR/some_cache_file"
  touch "$AWX_STATE_DIR/some_state_file"

  run ./awx clear

  [ "$status" -eq 0 ]
  [[ ! -d "$AWX_CACHE_DIR" ]]
  [[ ! -d "$AWX_STATE_DIR" ]]
}

@test "awx refresh without AWS_PROFILE returns error" {
  unset AWS_PROFILE
  run ./awx refresh
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "AWS_PROFILE not set" ]]
}

@test "awx refresh with SSO profile clears cache and logs in" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  touch "$AWX_SSO_CACHE_DIR/botocore-client-id.json"
  touch "$AWX_SSO_CACHE_DIR/abcd1234.json"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == "sso login"* ]]; then
  exit 0
elif [[ "$*" == sts* ]]; then
  echo '{"UserId":"X","Account":"123","Arn":"arn:aws:iam::123:user/x"}'
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/jq

  export AWS_PROFILE="test-profile"

  run ./awx refresh

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Cleared SSO token cache" ]]
  [[ "${output}" =~ "SSO session refreshed for profile: test-profile" ]]
}

@test "awx refresh with failed SSO login" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == "sso login"* ]]; then
  echo "SSO login failed" >&2
  exit 1
fi
exit 1
EOM
  chmod +x mock/bin/aws

  export AWS_PROFILE="test-profile"

  run ./awx refresh

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "AWS SSO login failed" ]]
}
