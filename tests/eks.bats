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
  export AWX_EKS_RETRIES=1       # Single attempt to keep test fast
  export AWX_EKS_RETRY_DELAY=0   # No sleep between retries

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Failed to parse AWS EKS clusters" ]]

  # Cleanup
  rm -rf mock
}

@test "awx eks list with expired SSO session" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws CLI to simulate an expired session
  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == sts* ]]; then
  echo '{ "access_key": "EXPIRED" }'
  exit 1
elif [[ "$*" == sso* ]]; then
  echo "SSO login triggered" >&2
  exit 0
elif [[ "$*" == configure* ]]; then
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

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-a" ]]
  [[ "${output}" =~ "SSO session expired" ]]
  [[ "${output}" =~ "SSO login triggered" ]]

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
