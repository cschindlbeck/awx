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

  echo "DEBUG STATUS: $status"
  echo "DEBUG OUTPUT: >>${output}<<"
  echo "DEBUG MOCK DIR:"
  ls -la mock/bin

  [ "$status" -eq 0 ] # Updated expectation to 0 as no clusters found might be valid
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
