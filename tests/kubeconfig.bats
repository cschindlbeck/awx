#!/usr/bin/env bats

setup() {
  mkdir -p test-config
  export KUBECONFIG="$(pwd)/test-config/kubeconfig"
  export AWS_PROFILE="test-profile"
  export DEFAULT_REGION="us-west-2"
}

teardown() {
  rm -rf test-config mock
}

@test "awx updates kubeconfig with valid cluster" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":["test-cluster"]}'
elif [[ "$*" == *"eks update-kubeconfig"* ]]; then
  touch "$KUBECONFIG"
  exit 0
else
  echo "unexpected aws invocation: $*" >&2
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  run ./awx eks update

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Kubeconfig updated successfully" ]]
  [[ -f $KUBECONFIG ]]
}

@test "awx fails without valid profile" {
  unset AWS_PROFILE

  run ./awx eks update

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "AWS_PROFILE not set" ]]
}

@test "awx fails without valid cluster" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"eks list-clusters"* ]]; then
  echo "{ \"clusters\": [] }"
fi
EOM
  chmod +x mock/bin/aws

  run ./awx eks update

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No EKS cluster selected" ]]
  [[ ! -f $KUBECONFIG ]]
}

@test "awx handles aws command failure on kubeconfig" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":["test-cluster"]}'
elif [[ "$*" == *"eks update-kubeconfig"* ]]; then
  echo "DEBUG OUTPUT: aws invoked" >&2
  echo "ARGS: $*" >&2
  exit 1
else
  echo "unexpected aws invocation: $*" >&2
  exit 1
fi
EOM

  chmod +x mock/bin/aws

  run ./awx eks update 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Failed to update kubeconfig for cluster" ]]
  [[ ! -f $KUBECONFIG ]]
}
