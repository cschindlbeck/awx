#!/usr/bin/env bats

setup() {
  unset AWX_PROVIDER
  rm -rf mock
}

teardown() {
  unset AWX_PROVIDER
  rm -rf mock
}

@test "_detect_provider returns azure when AWX_PROVIDER=azure" {
  source ./awx
  AWX_PROVIDER="azure"
  result="$(_detect_provider)"
  [ "$result" = "azure" ]
}

@test "_detect_provider returns aws when AWX_PROVIDER=aws" {
  source ./awx
  AWX_PROVIDER="aws"
  result="$(_detect_provider)"
  [ "$result" = "aws" ]
}

@test "_detect_provider auto-detects azure when kubeconfig exec is kubelogin" {
  source ./awx
  unset AWX_PROVIDER
  kubectl() {
    if [[ "$*" == *"contexts[0].context.user"* ]]; then
      echo "azure-user"
      return 0
    fi
    if [[ "$*" == *"users[?("* ]]; then
      echo "kubelogin"
      return 0
    fi
    return 1
  }
  export -f kubectl
  result="$(_detect_provider)"
  [ "$result" = "azure" ]
}

@test "_detect_provider auto-detects aws when kubeconfig exec is aws" {
  source ./awx
  unset AWX_PROVIDER
  kubectl() {
    if [[ "$*" == *"contexts[0].context.user"* ]]; then
      echo "aws-user"
      return 0
    fi
    if [[ "$*" == *"users[?("* ]]; then
      echo "aws"
      return 0
    fi
    return 1
  }
  export -f kubectl
  result="$(_detect_provider)"
  [ "$result" = "aws" ]
}

@test "_detect_provider defaults to aws when kubectl is absent" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  source ./awx
  unset AWX_PROVIDER
  result="$(PATH="$tmpdir" _detect_provider 2>/dev/null)"
  rm -rf "$tmpdir"
  [ "$result" = "aws" ]
}
