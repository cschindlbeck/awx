#!/usr/bin/env bats

setup() {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_STS_RETRIES=2
  # Resolve the real jq binary before mock/bin is on PATH
  REAL_JQ="$(command -v jq 2>/dev/null || echo "")"
  if [[ -z "$REAL_JQ" ]]; then
    # Fallback: find jq outside mock/bin
    for _p in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do
      [[ -x "$_p" ]] && REAL_JQ="$_p" && break
    done
  fi
  export REAL_JQ
}

teardown() {
  rm -rf mock
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -f "${AWX_STATE_FILE:-}"
  rm -f "/tmp/awx_sts_test_state_$$" "/tmp/awx_sts_missing_$$" "/tmp/awx_sts_switch_$$"
}

# Helper: write a warm (fresh) EKS cluster cache for a profile
_make_warm_cache() {
  local profile="$1"
  local cluster="${2:-cached-cluster}"
  local safe_profile="${profile//[^a-zA-Z0-9._-]/_}"
  mkdir -p "$AWX_CACHE_DIR"
  printf '{"clusters":["%s"]}' "$cluster" >"${AWX_CACHE_DIR}/clusters_${safe_profile}.json"
  touch "${AWX_CACHE_DIR}/clusters_${safe_profile}.json"
}

# Helper: write a jq wrapper that calls the real jq binary
_make_jq_mock() {
  printf '#!/bin/bash\nexec "%s" "$@"\n' "$REAL_JQ" >mock/bin/jq
  chmod +x mock/bin/jq
}

@test "expired SSO with valid EKS cache triggers re-auth and serves cache" {
  _make_warm_cache "sso-profile" "cached-cluster"
  _make_jq_mock

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
  exit 0
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  # First call fails (session expired), subsequent calls succeed after sso login
  state_file="/tmp/awx_sts_test_state_${PPID}"
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "$*" == *"sso login"* ]]; then
  exit 0
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "cached-cluster"
EOM
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cached-cluster" ]]
  [[ "${output}" =~ "SSO session expired" ]]
}

@test "missing SSO cache file triggers sso login and fetches clusters live" {
  # No EKS cache — will go through live API path after re-auth
  _make_jq_mock

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
  exit 0
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  state_file="/tmp/awx_sts_missing_${PPID}"
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    echo "failed to read cached SSO token file" >&2
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "$*" == *"sso login"* ]]; then
  exit 0
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":["live-cluster"]}'
  exit 0
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "live-cluster"
EOM
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "live-cluster" ]]
}

@test "SSO login fails after expired session exits with clear error and no retry loop" {
  _make_warm_cache "sso-profile" "cached-cluster"
  _make_jq_mock

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
  exit 0
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 1
elif [[ "$*" == *"sso login"* ]]; then
  echo "SSO login failed" >&2
  exit 1
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "cached-cluster"
EOM
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "AWS SSO login failed" ]] || [[ "${output}" =~ "Session unavailable" ]]
}

@test "valid SSO session with warm EKS cache serves cache without triggering sso login" {
  _make_warm_cache "sso-profile" "cached-cluster"
  _make_jq_mock

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
  exit 0
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  # Session is valid — STS succeeds immediately
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "$*" == *"sso login"* ]]; then
  echo "UNEXPECTED_SSO_LOGIN_CALL" >&2
  exit 1
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "cached-cluster"
EOM
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cached-cluster" ]]
  [[ ! "${output}" =~ "UNEXPECTED_SSO_LOGIN_CALL" ]]
}

@test "profile switching after SSO recovery succeeds for a second profile" {
  _make_warm_cache "profile-b" "cluster-b"
  _make_jq_mock

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
  exit 0
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  state_file="/tmp/awx_sts_switch_${PPID}"
  if [[ ! -f "$state_file" ]]; then
    touch "$state_file"
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "$*" == *"sso login"* ]]; then
  exit 0
elif [[ "$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":["cluster-b"]}'
  exit 0
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "cluster-b"
EOM
  chmod +x mock/bin/fzf

  export AWS_PROFILE="profile-b"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-b" ]]
}
