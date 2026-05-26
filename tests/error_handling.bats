#!/usr/bin/env bats

@test "die exits with nonzero status when script is executed standalone" {
  run ./awx --bogus-flag
  [ "$status" -ne 0 ]
  [[ "${output}" == *"Unknown flag"* ]]
}

@test "die returns without exiting when sourced" {
  run bash -c 'source ./awx; die "test sourced error"; echo "ALIVE"'
  [ "$status" -eq 0 ]
  [[ "${output}" == *"test sourced error"* ]]
  [[ "${output}" == *"ALIVE"* ]]
}

@test "no unexpected shell termination when sourced with die" {
  run bash -c '
    source ./awx
    wrapper() { die "error from function"; }
    wrapper
    echo "SHELL_ALIVE"
  '
  [ "$status" -eq 0 ]
  [[ "${output}" == *"error from function"* ]]
  [[ "${output}" == *"SHELL_ALIVE"* ]]
}

@test "die in || context returns when sourced (no shell exit)" {
  run bash -c 'source ./awx; false || die "or failure"; echo "ALIVE"'
  [ "$status" -eq 0 ]
  [[ "${output}" == *"or failure"* ]]
  [[ "${output}" == *"ALIVE"* ]]
}
