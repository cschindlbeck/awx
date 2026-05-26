#!/usr/bin/env bats

setup() {
  export KUBECONFIG="$(pwd)/test-config/kubeconfig"
  export AWS_PROFILE="test-profile"
}

teardown() {
  rm -rf test-config mock
}

@test "awx ctx selects and switches to a context via fzf" {
  mkdir -p mock/bin test-config
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == *"get-contexts"* ]]; then
  echo "dev-cluster"
  echo "prod-cluster"
elif [[ "$*" == *"use-context"* ]]; then
  echo "Switched to context $3"
else
  echo "unexpected kubectl invocation: $*" >&2
  exit 1
fi
EOM
  chmod +x mock/bin/kubectl

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  run ./awx ctx

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Switched to context: dev-cluster" ]]
}

@test "awx ctx warns when no contexts available" {
  mkdir -p mock/bin test-config
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == *"get-contexts"* ]]; then
  exit 0
fi
EOM
  chmod +x mock/bin/kubectl

  run ./awx ctx

  [ "$status" -eq 1 ]
  [[ "${output}" =~ "No kubeconfig contexts available" ]]
}

@test "awx ctx fails when kubectl is missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  ln -s "$(command -v bash)" "$tmpdir/bash"
  PATH="$tmpdir" run ./awx ctx
  rm -rf "$tmpdir"

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: kubectl" ]]
}
