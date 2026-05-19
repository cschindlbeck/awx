#!/usr/bin/env bats

setup() {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"
  export AWX_STS_RETRIES=2
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"
}

teardown() {
  rm -f "${AWX_STATE_FILE:-}"
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -rf mock
  rm -f "/tmp/awx_use_reauth_$$"
}

@test "awx use triggers sso login when session is expired" {
  local state_file="/tmp/awx_use_reauth_$$"
  rm -f "$state_file"

  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *"list-profiles"* ]]; then
  echo "expired-profile"
elif [[ "\$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "\$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "\$*" == *"sts get-caller-identity"* ]]; then
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "\$*" == *"sso login"* ]]; then
  exit 0
elif [[ "\$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":[]}'
  exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "SSO session expired" ]]
  [[ "${output}" =~ "Using profile: expired-profile" ]]
}

@test "awx use does not trigger sso login when session is valid" {
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  echo "valid-profile"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "$*" == *"sso login"* ]]; then
  echo "UNEXPECTED_SSO_LOGIN" >&2
  exit 1
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":[]}'
  exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  run ./awx use 2>&1

  [ "$status" -eq 0 ]
  [[ ! "${output}" =~ "UNEXPECTED_SSO_LOGIN" ]]
  [[ ! "${output}" =~ "SSO session expired" ]]
  [[ "${output}" =~ "Using profile: valid-profile" ]]
}

@test "awx prev triggers sso login when session is expired" {
  local state_file="/tmp/awx_use_reauth_$$"
  rm -f "$state_file"

  # Set up state file with previous environment
  mkdir -p "$(dirname "$AWX_STATE_FILE")"
  printf "current-profile,current-cluster\nprev-profile,prev-cluster\n" >"$AWX_STATE_FILE"

  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "\$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "\$*" == *"sts get-caller-identity"* ]]; then
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "\$*" == *"sso login"* ]]; then
  exit 0
elif [[ "\$*" == *"eks update-kubeconfig"* ]]; then
  exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  export AWS_PROFILE="current-profile"

  run ./awx - 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "SSO session expired" ]]
  [[ "${output}" =~ "Switched to profile: prev-profile" ]]
}
