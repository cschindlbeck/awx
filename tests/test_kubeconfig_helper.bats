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

@test "_eks_update_kubeconfig skips aws update-kubeconfig when context already exists" {
  # Override kubectl mock to report the context as existing and capture use-context calls
  rm -f /tmp/last_kubectl_use_context
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    if [[ "$1 $2" == "config use-context" ]]; then
      echo "kubectl $*" >/tmp/last_kubectl_use_context
      return 0
    fi
    return 1
  }
  export -f kubectl

  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  # aws should NOT have been called
  [ ! -f /tmp/last_aws_call ]
}

@test "_eks_update_kubeconfig calls kubectl use-context when context already exists" {
  rm -f /tmp/last_kubectl_use_context
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    if [[ "$1 $2" == "config use-context" ]]; then
      echo "kubectl $*" >/tmp/last_kubectl_use_context
      return 0
    fi
    return 1
  }
  export -f kubectl

  _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  [ -f /tmp/last_kubectl_use_context ]
  [ "$(cat /tmp/last_kubectl_use_context)" = "kubectl config use-context test-profile" ]
}

@test "_eks_update_kubeconfig logs skip message when context already exists" {
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    if [[ "$1 $2" == "config use-context" ]]; then
      return 0
    fi
    return 1
  }
  export -f kubectl

  run _eks_update_kubeconfig "$AWS_PROFILE" "test-cluster" "us-west-2"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "switching to context" ]]
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

# Kubectl mock for the blue/green scenario: the profile-named context exists but
# points to a different cluster than the one requested.
_mock_kubectl_profile_context_points_to_blue() {
  rm -f /tmp/last_kubectl_use_context
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      echo "test-profile"
      return 0
    fi
    if [[ "$1 $2" == "config view" ]]; then
      echo "arn:aws:eks:us-west-2:123456789012:cluster/cluster_blue"
      return 0
    fi
    if [[ "$1 $2" == "config use-context" ]]; then
      echo "kubectl $*" >/tmp/last_kubectl_use_context
      return 0
    fi
    return 1
  }
  export -f kubectl
}

@test "_eks_update_kubeconfig reuses profile context when it points to the selected cluster" {
  _mock_kubectl_profile_context_points_to_blue

  _eks_update_kubeconfig "$AWS_PROFILE" "cluster_blue" "us-west-2"
  [ ! -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_kubectl_use_context)" = "kubectl config use-context test-profile" ]
}

@test "_eks_update_kubeconfig creates cluster-specific context when profile context points to another cluster" {
  _mock_kubectl_profile_context_points_to_blue

  _eks_update_kubeconfig "$AWS_PROFILE" "cluster_green" "us-west-2"
  [ -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_aws_call)" = "aws --profile test-profile eks update-kubeconfig --region us-west-2 --name cluster_green --alias test-profile-cluster_green" ]
}

@test "_eks_update_kubeconfig switches to existing cluster-specific context for the other cluster" {
  rm -f /tmp/last_kubectl_use_context
  kubectl() {
    if [[ "$*" == "config get-contexts -o name" ]]; then
      printf "test-profile\ntest-profile-cluster_green\n"
      return 0
    fi
    if [[ "$1 $2" == "config view" ]]; then
      echo "arn:aws:eks:us-west-2:123456789012:cluster/cluster_blue"
      return 0
    fi
    if [[ "$1 $2" == "config use-context" ]]; then
      echo "kubectl $*" >/tmp/last_kubectl_use_context
      return 0
    fi
    return 1
  }
  export -f kubectl

  _eks_update_kubeconfig "$AWS_PROFILE" "cluster_green" "us-west-2"
  [ ! -f /tmp/last_aws_call ]
  [ "$(cat /tmp/last_kubectl_use_context)" = "kubectl config use-context test-profile-cluster_green" ]
}
