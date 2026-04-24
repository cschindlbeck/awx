#!/usr/bin/env bats

setup() {
  export AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"  # start empty
  mkdir -p "$(dirname "$AWX_STATE_FILE")"
}

teardown() {
  rm -f "${AWX_STATE_FILE:-}"
  rm -rf mock
}

@test "state file is created after awx use with profile and cluster" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn:aws:iam::123:user/x"}'
elif [[ "$*" == eks\ list-clusters* ]]; then echo '{"clusters":["test-cluster"]}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "test-profile"
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx use

  [ "$status" -eq 0 ]
  [ -f "$AWX_STATE_FILE" ]
  head -1 "$AWX_STATE_FILE" | grep -q "test-profile"
}

@test "awx - toggles between two environments" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  chmod +x mock/bin/jq

  # Seed state file: current=prod-profile,prod-cluster  previous=dev-profile,dev-cluster
  printf "prod-profile,prod-cluster\ndev-profile,dev-cluster\n" >"$AWX_STATE_FILE"
  export AWS_PROFILE="prod-profile"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx -

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]
  # After toggle, state should be swapped
  grep -q "dev-profile" <(head -1 "$AWX_STATE_FILE")
  grep -q "prod-profile" <(sed -n '2p' "$AWX_STATE_FILE")
}

@test "awx - twice returns to original environment" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  chmod +x mock/bin/aws

  printf "prod-profile,prod-cluster\ndev-profile,dev-cluster\n" >"$AWX_STATE_FILE"
  export AWS_PROFILE="prod-profile"

  # First toggle: should switch to dev
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx -
  [ "$status" -eq 0 ]

  # Second toggle: should switch back to prod
  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx -
  [ "$status" -eq 0 ]

  grep -q "prod-profile" <(head -1 "$AWX_STATE_FILE")
  [[ "$(head -1 "$AWX_STATE_FILE")" == "prod-profile,prod-cluster" ]]
  [[ "$(sed -n '2p' "$AWX_STATE_FILE")" == "dev-profile,dev-cluster" ]]
}

@test "awx - with no state file exits non-zero with message" {
  rm -f "$AWX_STATE_FILE"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No previous environment recorded" ]]
}

@test "awx - with empty previous env exits non-zero with message" {
  printf "prod-profile,prod-cluster\n\n" >"$AWX_STATE_FILE"
  export AWS_PROFILE="prod-profile"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No previous environment recorded" ]]
}

@test "awx - with profile-only previous env switches profile and warns" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
fi
EOM
  chmod +x mock/bin/aws

  printf "prod-profile,prod-cluster\ndev-profile,\n" >"$AWX_STATE_FILE"
  export AWS_PROFILE="prod-profile"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]
  [[ "${output}" =~ "No cluster stored" ]]
}
