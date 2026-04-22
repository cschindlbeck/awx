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
