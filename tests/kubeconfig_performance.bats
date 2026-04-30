#!/usr/bin/env bats

# Tests for kubeconfig update optimization:
# aws eks update-kubeconfig is skipped when the target context already exists.

setup() {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  mkdir -p "$(dirname "$AWX_STATE_FILE")"

  export UPDATE_KUBECONFIG_CALLED=0
  mkdir -p mock/bin

  # aws mock: handles SSO checks and captures update-kubeconfig calls
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sts* ]]; then
  echo '{"UserId":"X","Account":"123","Arn":"arn:aws:iam::123:user/x"}'
elif [[ "$*" == *eks\ list-clusters* ]]; then
  echo '{"clusters":["perf-cluster"]}'
elif [[ "$*" == *eks\ update-kubeconfig* ]]; then
  echo "update-kubeconfig-called" >>/tmp/awx_update_kubeconfig_calls
  exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "perf-profile"
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  rm -f /tmp/awx_update_kubeconfig_calls
  export PATH="$(pwd)/mock/bin:$PATH"
}

teardown() {
  rm -f "${AWX_STATE_FILE:-}" /tmp/awx_update_kubeconfig_calls
  rm -rf mock
}

@test "update-kubeconfig is skipped when context already exists" {
  # Mock kubectl to report context as already existing
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "perf-profile"
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/kubectl

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster perf-cluster

  [ "$status" -eq 0 ]
  # update-kubeconfig must not have been called
  [ ! -f /tmp/awx_update_kubeconfig_calls ]
  [[ "${output}" =~ "already up-to-date" ]]
}

@test "update-kubeconfig is called when context does not exist" {
  # Mock kubectl to report no matching context
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "other-context"
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/kubectl

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster perf-cluster

  [ "$status" -eq 0 ]
  [ -f /tmp/awx_update_kubeconfig_calls ]
  call_count="$(wc -l </tmp/awx_update_kubeconfig_calls | tr -d ' ')"
  [ "$call_count" -eq 1 ]
}

@test "update-kubeconfig is called when kubectl is unavailable" {
  # No kubectl mock -> command not found -> skip-check is bypassed
  rm -f mock/bin/kubectl

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster perf-cluster

  [ "$status" -eq 0 ]
  [ -f /tmp/awx_update_kubeconfig_calls ]
}

@test "repeated awx use skips update-kubeconfig on second call" {
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  # Report context as present after first update
  if [[ -f /tmp/awx_update_kubeconfig_calls ]]; then
    echo "perf-profile"
  fi
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/kubectl

  # First call: context absent -> update runs
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster perf-cluster
  [ "$status" -eq 0 ]
  [ -f /tmp/awx_update_kubeconfig_calls ]
  first_count="$(wc -l </tmp/awx_update_kubeconfig_calls | tr -d ' ')"
  [ "$first_count" -eq 1 ]

  # Second call: context now present -> update skipped
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster perf-cluster
  [ "$status" -eq 0 ]
  second_count="$(wc -l </tmp/awx_update_kubeconfig_calls | tr -d ' ')"
  [ "$second_count" -eq 1 ]
  [[ "${output}" =~ "already up-to-date" ]]
}

@test "awx - toggle calls update-kubeconfig for previous cluster context" {
  # No kubectl mock so update always runs
  rm -f mock/bin/kubectl

  printf "prod-profile,prod-cluster\ndev-profile,dev-cluster\n" >"$AWX_STATE_FILE"
  export AWS_PROFILE="prod-profile"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx -

  [ "$status" -eq 0 ]
  [ -f /tmp/awx_update_kubeconfig_calls ]
}

@test "skip logic uses profile alias as context name" {
  # The alias passed to update-kubeconfig is the profile name, so context == profile
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  # Only the profile-named context matches
  echo "perf-profile"
  exit 0
fi
exit 1
EOM
  chmod +x mock/bin/kubectl

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use --profile perf-profile --cluster different-cluster-name

  [ "$status" -eq 0 ]
  # Context is matched by profile name, not cluster name
  [ ! -f /tmp/awx_update_kubeconfig_calls ]
  [[ "${output}" =~ "already up-to-date" ]]
}
