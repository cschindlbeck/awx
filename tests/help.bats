#!/usr/bin/env bats

@test "awx help displays the help message" {
  # Execute the help command
  run ./awx help

  # Assert the output contains help message
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: awx [command]"* ]]
  [[ "$output" == *"use [--profile P] [--cluster C]"* ]]
  [[ "$output" == *"whoami"* ]]
  [[ "$output" == *"eks list"* ]]
  [[ "$output" == *"eks update"* ]]
  [[ "$output" == *"help | -h"* ]]
}

@test "awx -h displays the help message" {
  # Execute the -h command
  run ./awx -h

  # Assert the output contains help message
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: awx [command]"* ]]
  [[ "$output" == *"use [--profile P] [--cluster C]"* ]]
  [[ "$output" == *"whoami"* ]]
  [[ "$output" == *"eks list"* ]]
  [[ "$output" == *"eks update"* ]]
  [[ "$output" == *"help | -h"* ]]
}
