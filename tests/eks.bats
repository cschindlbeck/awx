#!/usr/bin/env bats

@test "awx eks list with valid clusters" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws CLI to produce expected output for eks list-clusters and region
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["test-cluster"] }'
fi
EOM
  chmod +x mock/bin/aws

  # Mock jq to just output JSON path
  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "test-cluster" ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list with no clusters" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws CLI for both region and empty cluster list
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": [] }'
fi
EOM
  chmod +x mock/bin/aws

  # Have mock jq print the realistic output
  echo -e "#!/bin/bash\necho '[WARN] No EKS clusters found for profile: valid_profile'" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" == *No\ EKS\ clusters\ found* ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list without aws CLI" {
  PATH_BACKUP="$PATH"
  PATH="/usr/bin:/bin"

  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: aws" ]]

  export PATH="$PATH_BACKUP"
}

@test "awx eks list with malformed AWS output" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws CLI to produce malformed output
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo 'MALFORMED OUTPUT'
fi
EOM
  chmod +x mock/bin/aws

  # Mock jq to fail parsing
  cat >mock/bin/jq <<'EOM'
#!/bin/bash
exit 1
EOM
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"
  export AWX_EKS_RETRIES=1     # Single attempt to keep test fast
  export AWX_EKS_RETRY_DELAY=0 # No sleep between retries

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Failed to parse AWS EKS clusters" ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list with expired SSO session" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Use a counter file so STS fails on the first call (expired), then succeeds
  # after sso login completes (simulating normal credential propagation).
  local sts_counter_file
  sts_counter_file="$(mktemp)"
  echo "0" >"$sts_counter_file"

  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == sts* ]]; then
  count=\$(cat "$sts_counter_file")
  if [[ "\$count" -eq 0 ]]; then
    echo '{ "access_key": "EXPIRED" }' >&2
    echo \$((count + 1)) >"$sts_counter_file"
    exit 1
  fi
  echo '{ "UserId": "AIDEXAMPLE", "Account": "123456789", "Arn": "arn:aws:iam::123456789:user/test" }'
  exit 0
elif [[ "\$*" == sso* ]]; then
  echo "SSO login triggered" >&2
  exit 0
elif [[ "\$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["cluster-a"] }'
fi
EOM
  chmod +x mock/bin/aws

  # Mock jq to output JSON
  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  rm -f "$sts_counter_file"

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-a" ]]
  [[ "${output}" =~ "SSO session expired" ]]
  [[ "${output}" =~ "SSO login triggered" ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list fails when SSO session never stabilizes after login" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws: STS always fails (browser never confirmed), SSO login succeeds, no static credentials
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == sts* ]]; then
  exit 1
elif [[ "$*" == sso* ]]; then
  exit 0
elif [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["cluster-a"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"
  # Use only 2 STS retries so the test finishes quickly
  export AWX_STS_RETRIES=2

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "SSO session not ready after login" ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list with DEBUG flag" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws CLI to produce output
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["cluster-debug"] }'
fi
EOM
  chmod +x mock/bin/aws

  # Mock jq to output JSON
  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  export AWS_PROFILE="valid_profile"
  export DEBUG="true"

  run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "AWS RAW RESPONSE" ]]
  [[ "${output}" =~ "cluster-debug" ]]

  # Cleanup
  rm -rf mock
}
