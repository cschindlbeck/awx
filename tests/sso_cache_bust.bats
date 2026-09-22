#!/usr/bin/env bats

# Covers the recovery path where the local SSO token cache looks unexpired
# (so `aws sso login` silently no-ops) even though the session is actually
# unusable. aws_ensure_session should clear the cache and retry once before
# giving up, instead of forcing the user to run `awx logout`/`awx refresh`.

setup() {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"
  export AWX_SSO_CACHE_DIR
  AWX_SSO_CACHE_DIR="$(mktemp -d)"
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_STS_RETRIES=2

  REAL_JQ="$(command -v jq 2>/dev/null || echo "")"
  if [[ -z "$REAL_JQ" ]]; then
    for _p in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do
      [[ -x "$_p" ]] && REAL_JQ="$_p" && break
    done
  fi
  export REAL_JQ

  printf '#!/bin/bash\nexec "%s" "$@"\n' "$REAL_JQ" >mock/bin/jq
  chmod +x mock/bin/jq

  touch "$AWX_SSO_CACHE_DIR/marker.json"
}

teardown() {
  rm -rf mock
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -rf "${AWX_SSO_CACHE_DIR:-}"
  rm -f "${AWX_STATE_FILE:-}"
  rm -f "/tmp/awx_cache_bust_sts_$$"
}

@test "STS still not ready after first sso login clears SSO cache and retries until it succeeds" {
  local state_file="/tmp/awx_cache_bust_sts_$$"
  rm -f "$state_file"

  # Fails the initial check plus every attempt of the first retry loop
  # (AWX_STS_RETRIES=2 -> 3 failures total), then succeeds from the first
  # attempt of the post-cache-bust retry loop onward.
  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "\$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "\$*" == *"sts get-caller-identity"* ]]; then
  count=0
  [[ -f "$state_file" ]] && count="\$(cat "$state_file")"
  count=\$((count + 1))
  echo "\$count" >"$state_file"
  if [[ "\$count" -le 3 ]]; then
    exit 1
  fi
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
  exit 0
elif [[ "\$*" == *"sso login"* ]]; then
  exit 0
elif [[ "\$*" == *"eks list-clusters"* ]]; then
  echo '{"clusters":["recovered-cluster"]}'
  exit 0
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "SSO session still not ready" ]]
  [[ "${output}" =~ "recovered-cluster" ]]
  # The stale cache directory must actually have been removed.
  [[ ! -d "$AWX_SSO_CACHE_DIR" ]]
}

@test "STS never stabilizing even after a cache reset dies with a cache-reset-aware message" {
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == *"sts get-caller-identity"* ]]; then
  exit 1
elif [[ "$*" == *"sso login"* ]]; then
  exit 0
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "SSO session not ready after login and cache reset" ]]
  [[ ! -d "$AWX_SSO_CACHE_DIR" ]]
}
