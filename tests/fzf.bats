#!/usr/bin/env bats

setup() {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"
}

teardown() {
  rm -f "${AWX_STATE_FILE:-}"
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -rf mock
}

# ---------------------------------------------------------------------------
# Profile selection: fzf must be invoked with --preview flag
# ---------------------------------------------------------------------------
@test "fzf profile selection includes --preview flag" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  printf "profile-alpha\nprofile-beta\n"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # Record the fzf invocation arguments to verify --preview is present
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "fzf_args: $*" >&2
head -n1
EOM
  chmod +x mock/bin/fzf

  run bash -c 'AWX_STATE_FILE="$AWX_STATE_FILE" AWX_CACHE_DIR="$AWX_CACHE_DIR" ./awx use 2>&1'

  [[ "${output}" =~ "--preview" ]]
  [[ "${output}" =~ "aws configure list --profile" ]]
}

# ---------------------------------------------------------------------------
# Cluster selection: fzf must be invoked with --preview flag
# ---------------------------------------------------------------------------
@test "fzf cluster selection includes --preview flag" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  printf "profile-alpha\nprofile-beta\n"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{ "clusters": ["cluster-one", "cluster-two"] }'
elif [[ "$*" == *"eks update-kubeconfig"* ]]; then
  echo "Updated kubeconfig"
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # First fzf call selects a profile; second selects a cluster.
  # Both should receive --preview; capture all args for assertion.
  _fzf_call=0
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "fzf_args: $*" >&2
head -n1
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
  chmod +x mock/bin/jq

  run bash -c 'AWX_STATE_FILE="$AWX_STATE_FILE" AWX_CACHE_DIR="$AWX_CACHE_DIR" ./awx use 2>&1'

  [[ "${output}" =~ "--preview" ]]
  [[ "${output}" =~ "aws eks describe-cluster" ]]
}

# ---------------------------------------------------------------------------
# No regression: profile selection still works with preview flag present
# ---------------------------------------------------------------------------
@test "fzf preview flag does not break profile selection" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  printf "profile-alpha\nprofile-beta\n"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  run bash -c 'AWX_STATE_FILE="$AWX_STATE_FILE" AWX_CACHE_DIR="$AWX_CACHE_DIR" ./awx use 2>&1'

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: profile-alpha" ]]
}

# ---------------------------------------------------------------------------
# No regression: cluster selection still works with preview flag present
# ---------------------------------------------------------------------------
@test "fzf preview flag does not break cluster selection" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"list-profiles"* ]]; then
  echo "only-profile"
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://sso.example.com"
elif [[ "$*" == *"sts"* ]]; then
  echo '{"Account":"123456789012","UserId":"AIDEXAMPLE","Arn":"arn:aws:iam::123456789012:user/test"}'
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{ "clusters": ["cluster-one", "cluster-two"] }'
elif [[ "$*" == *"eks update-kubeconfig"* ]]; then
  echo "Updated kubeconfig"
else
  echo '{}'
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  chmod +x mock/bin/fzf

  cat >mock/bin/jq <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
  chmod +x mock/bin/jq

  run bash -c 'AWX_STATE_FILE="$AWX_STATE_FILE" AWX_CACHE_DIR="$AWX_CACHE_DIR" ./awx use 2>&1'

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: only-profile" ]]
  [[ "${output}" =~ "Updating kubeconfig for cluster: cluster-one" ]]
}
