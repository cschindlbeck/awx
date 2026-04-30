#!/usr/bin/env bats

setup() {
  rm -f /tmp/last_aws_call
  export DEFAULT_REGION="us-west-2"
  export AWS_PROFILE="test-profile"

  # Provide a mock aws binary that captures the exact invocation so tests can
  # assert on the arguments passed to `aws eks update-kubeconfig`.
  mkdir -p mock/bin
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
echo "aws $*" >/tmp/last_aws_call
exit 0
EOM
  chmod +x mock/bin/aws
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock kubectl: no existing contexts by default (simulates empty kubeconfig)
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      return 0
    fi
    return 1
  }
  export -f kubectl

  source ./awx
}

teardown() {
  rm -rf mock
}

@test "_eks_update_kubeconfig uses correct parameters" {
  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  [ -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_aws_call)" = "aws --profile test-profile eks update-kubeconfig --region us-west-2 --name test-cluster --alias test-profile" ]
}

@test "_eks_update_kubeconfig uses DEFAULT_REGION if no region specified" {
  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster"
  [ -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_aws_call)" = "aws --profile test-profile eks update-kubeconfig --region us-west-2 --name test-cluster --alias test-profile" ]
}

@test "_eks_update_kubeconfig skips update when context already exists" {
  # Override kubectl mock to report the context as existing
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    return 1
  }
  export -f kubectl

  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  # aws should NOT have been called
  [ ! -f /tmp/last_aws_call ]
}

@test "_eks_update_kubeconfig logs skip message when context already exists" {
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    return 1
  }
  export -f kubectl

  run _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "already up-to-date" ]]
}

@test "_eks_update_kubeconfig runs update when context does not exist" {
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "other-context"
      return 0
    fi
    return 1
  }
  export -f kubectl

  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  [ -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_aws_call)" = "aws --profile test-profile eks update-kubeconfig --region us-west-2 --name test-cluster --alias test-profile" ]
}
