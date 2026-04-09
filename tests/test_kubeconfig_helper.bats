#!/usr/bin/env bats

setup() {
  rm -f /tmp/last_aws_call /tmp/test_debug.log
  export DEFAULT_REGION="us-west-2"
  export AWS_PROFILE="test-profile"
  echo "Setup: DEFAULT_REGION=$DEFAULT_REGION" >> /tmp/test_debug.log
  echo "Setup: AWS_PROFILE=$AWS_PROFILE" >> /tmp/test_debug.log
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
