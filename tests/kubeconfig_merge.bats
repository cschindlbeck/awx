#!/usr/bin/env bats

setup() {
  mkdir -p test-config
  export KUBECONFIG="$(pwd)/test-config/kubeconfig"
  export AWS_PROFILE="test-profile"

  # Seed a minimal dest kubeconfig
  cat >"$KUBECONFIG" <<'EOF'
apiVersion: v1
kind: Config
current-context: existing-context
clusters:
- cluster:
    server: https://existing.example.com
  name: existing-cluster
contexts:
- context:
    cluster: existing-cluster
    user: existing-user
  name: existing-context
users:
- name: existing-user
  user: {}
EOF
}

teardown() {
  rm -rf test-config mock
}

_make_src_kubeconfig() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path" <<'EOF'
apiVersion: v1
kind: Config
current-context: kyma-context
clusters:
- cluster:
    server: https://kyma.example.com
  name: kyma-cluster
contexts:
- context:
    cluster: kyma-cluster
    user: kyma-user
  name: kyma-context
users:
- name: kyma-user
  user: {}
EOF
}

_mock_kubectl_merge() {
  mkdir -p mock/bin
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == *"config view"* && "$*" == *"--flatten"* ]]; then
  echo "apiVersion: v1"
  echo "kind: Config"
  echo "current-context: existing-context"
  echo "clusters: []"
  echo "contexts: []"
  echo "users: []"
elif [[ "$*" == *"get-contexts"* ]]; then
  echo "existing-context"
  echo "kyma-context"
elif [[ "$*" == *"use-context"* ]]; then
  echo "Switched to context $3"
fi
EOM
  chmod +x mock/bin/kubectl
  export PATH="$(pwd)/mock/bin:$PATH"
}

@test "awx kubeconfig merge merges src into dest successfully" {
  _make_src_kubeconfig test-config/src_config
  _mock_kubectl_merge

  run ./awx kubeconfig merge test-config/src_config

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "merged" ]]
  [[ "${output}" =~ "successfully" ]]
}

@test "awx kubeconfig merge fails when src file does not exist" {
  mkdir -p mock/bin
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
EOM
  chmod +x mock/bin/kubectl
  export PATH="$(pwd)/mock/bin:$PATH"

  run ./awx kubeconfig merge /nonexistent/path/config

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "not found" ]]
}

@test "awx kubeconfig fails when no subcommand given" {
  mkdir -p mock/bin
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
EOM
  chmod +x mock/bin/kubectl
  export PATH="$(pwd)/mock/bin:$PATH"

  run ./awx kubeconfig

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing kubeconfig subcommand" ]]
}

@test "awx kubeconfig fails with unknown subcommand" {
  mkdir -p mock/bin
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
EOM
  chmod +x mock/bin/kubectl
  export PATH="$(pwd)/mock/bin:$PATH"

  run ./awx kubeconfig frobnicate

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Unknown kubeconfig subcommand" ]]
}

@test "awx kubeconfig merge warns and no-ops when src and dest are the same file" {
  _mock_kubectl_merge

  run ./awx kubeconfig merge "$KUBECONFIG"

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "same file" ]]
  # Dest file unchanged (original content still present)
  grep -q "existing-context" "$KUBECONFIG"
}

@test "awx kubeconfig merge fails when kubectl is missing" {
  _make_src_kubeconfig test-config/src_config
  local tmpdir
  tmpdir="$(mktemp -d)"
  ln -s "$(command -v bash)" "$tmpdir/bash"
  PATH="$tmpdir" run ./awx kubeconfig merge test-config/src_config
  rm -rf "$tmpdir"

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: kubectl" ]]
}

@test "awx kubeconfig merge creates dest when it does not exist yet" {
  _make_src_kubeconfig test-config/src_config
  _mock_kubectl_merge
  rm -f "$KUBECONFIG"

  run ./awx kubeconfig merge test-config/src_config

  [ "$status" -eq 0 ]
  [[ -f "$KUBECONFIG" ]]
}

@test "awx kubeconfig merge with --switch invokes context picker afterward" {
  _make_src_kubeconfig test-config/src_config
  _mock_kubectl_merge

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  run ./awx kubeconfig merge test-config/src_config --switch

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "merged" ]]
  [[ "${output}" =~ "Switched to context" ]]
}

@test "awx kubeconfig merge expands tilde in path" {
  _make_src_kubeconfig test-config/src_config
  _mock_kubectl_merge

  # Copy src_config to $HOME/awx_test_src_config for the tilde test
  local home_config="$HOME/awx_test_src_config"
  cp test-config/src_config "$home_config"

  run ./awx kubeconfig merge "~/awx_test_src_config"
  local exit_status="$status"
  rm -f "$home_config"

  [ "$exit_status" -eq 0 ]
  [[ "${output}" =~ "merged" ]]
}

@test "awx kubeconfig merge leaves dest untouched when kubectl fails" {
  _make_src_kubeconfig test-config/src_config
  mkdir -p mock/bin
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == *"config view"* ]]; then
  exit 1
fi
EOM
  chmod +x mock/bin/kubectl
  export PATH="$(pwd)/mock/bin:$PATH"

  local before
  before="$(cat "$KUBECONFIG")"

  run ./awx kubeconfig merge test-config/src_config

  [ "$status" -ne 0 ]
  # Dest file is unchanged
  [ "$(cat "$KUBECONFIG")" = "$before" ]
  # No stray temp files left behind
  local stray_count
  stray_count="$(find "$(dirname "$KUBECONFIG")" -name ".awx_kubeconfig_merge.*" | wc -l)"
  [ "$stray_count" -eq 0 ]
}
