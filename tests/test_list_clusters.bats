#!/usr/bin/env bats

setup() {
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"
  export AWX_EKS_RETRIES=1
  export AWX_EKS_RETRY_DELAY=0

  # Provide a stub fzf so check_deps passes when fzf is not installed
  printf '#!/bin/bash\necho mock-cluster\n' >mock/bin/fzf
  chmod +x mock/bin/fzf
}

teardown() {
  rm -rf "${AWX_CACHE_DIR:-}"
  rm -rf mock
}

@test "temp file is removed after list_clusters returns successfully" {
  local test_tmpdir
  test_tmpdir="$(mktemp -d)"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["test-cluster"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  TMPDIR="$test_tmpdir" run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "test-cluster" ]]

  # No temp files should remain in the controlled TMPDIR after success
  local remaining
  remaining="$(find "$test_tmpdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$remaining" -eq 0 ]

  rm -rf "$test_tmpdir"
}

@test "temp file is removed after list_clusters fails" {
  local test_tmpdir
  test_tmpdir="$(mktemp -d)"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sts* ]]; then
  echo '{ "UserId": "test", "Account": "123", "Arn": "arn:aws:iam::123:user/test" }'
else
  echo 'MALFORMED OUTPUT' >&2
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  cat >mock/bin/jq <<'EOM'
#!/bin/bash
exit 1
EOM
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  TMPDIR="$test_tmpdir" run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Failed to parse AWS EKS clusters" ]]

  # No temp files should remain in the controlled TMPDIR after failure
  local remaining
  remaining="$(find "$test_tmpdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$remaining" -eq 0 ]

  rm -rf "$test_tmpdir"
}

@test "two parallel list_clusters invocations use distinct temp files and do not interfere" {
  local test_tmpdir
  test_tmpdir="$(mktemp -d)"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sts* ]]; then
  echo '{ "UserId": "test", "Account": "123", "Arn": "arn:aws:iam::123:user/test" }'
else
  echo '{ "clusters": ["cluster-a"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  # Each parallel invocation needs its own cache directory to ensure neither
  # hits a cache-hit fast-path (which skips mktemp) due to the other's write.
  local cache1 cache2 outdir
  cache1="$(mktemp -d)"
  cache2="$(mktemp -d)"
  outdir="$(mktemp -d)"

  # Run two invocations in parallel, capturing output to files outside test_tmpdir
  TMPDIR="$test_tmpdir" AWX_CACHE_DIR="$cache1" ./awx eks list >"$outdir/out1" 2>&1 &
  local pid1="$!"
  TMPDIR="$test_tmpdir" AWX_CACHE_DIR="$cache2" ./awx eks list >"$outdir/out2" 2>&1 &
  local pid2="$!"

  wait "$pid1"; local status1="$?"
  wait "$pid2"; local status2="$?"

  [ "$status1" -eq 0 ]
  [ "$status2" -eq 0 ]
  [[ "$(cat "$outdir/out1")" =~ "cluster-a" ]]
  [[ "$(cat "$outdir/out2")" =~ "cluster-a" ]]

  # All temp files should be cleaned up after both invocations finish
  local remaining
  remaining="$(find "$test_tmpdir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$remaining" -eq 0 ]

  rm -rf "$test_tmpdir" "$cache1" "$cache2" "$outdir"
}
