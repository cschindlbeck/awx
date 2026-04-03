#!/usr/bin/env bats

@test "awx help displays the help message" {
  # Execute the help command
  run ./awx help

  # Assert the output contains help message
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: awx [command]"* ]]
  [[ "$output" == *"use           Select AWS profile using fuzzy finder"* ]]
  [[ "$output" == *"whoami        Display current AWS identity"* ]]
  [[ "$output" == *"eks list      List EKS clusters for the active profile"* ]]
  [[ "$output" == *"eks update    Update kubeconfig for a specific EKS cluster"* ]]
  [[ "$output" == *"help | -h     Show this help message"* ]]
}

@test "awx -h displays the help message" {
  # Execute the -h command
  run ./awx -h

  # Assert the output contains help message
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: awx [command]"* ]]
  [[ "$output" == *"use           Select AWS profile using fuzzy finder"* ]]
  [[ "$output" == *"whoami        Display current AWS identity"* ]]
  [[ "$output" == *"eks list      List EKS clusters for the active profile"* ]]
  [[ "$output" == *"eks update    Update kubeconfig for a specific EKS cluster"* ]]
  [[ "$output" == *"help | -h     Show this help message"* ]]
}
