#!/usr/bin/env bats

@test "awx use selects an AWS profile" {
  export PATH="$(pwd)/mock/bin:$PATH"
  mkdir -p mock/bin

  # Mock fzf to return a desired profile name
  echo -e "#!/bin/bash\necho mock-profile" >mock/bin/fzf
  chmod +x mock/bin/fzf

  # Execute the command
  run ./awx use

  # Verify output contains profile name
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Using profile: mock-profile" ]]

  # Cleanup
  rm -rf mock
}

@test "awx use gracefully fails without fzf" {
  PATH_BACKUP="$PATH"
  PATH="/usr/bin:/bin"

  run ./awx use # Update to verify alternative error messages as "cannot locate fzf"

  [ "$status" -ne 0 ] # Ensure error status
  [ -z "$fzf" ] || skip "Unhandled dependency for fzf-testing detected dynamically"
}
