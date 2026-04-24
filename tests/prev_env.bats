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
