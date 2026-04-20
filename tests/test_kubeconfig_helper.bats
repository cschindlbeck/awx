#!/usr/bin/env bats

setup() {
  rm -f /tmp/last_aws_call
  export DEFAULT_REGION="us-west-2"
  export AWS_PROFILE="test-profile"

  # Mock aws to capture the invocation instead of executing it
  aws() {
    echo "aws $*" > /tmp/last_aws_call
  }
  export -f aws

  source ./awx
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
