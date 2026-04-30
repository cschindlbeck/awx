#!/usr/bin/env bats

@test "log output contains no escape codes when stdout is piped" {
  # Run awx in a context where stdout is not a TTY (piped), so no colour codes
  result="$(bash -c 'source ./awx; log "test message"' 2>/dev/null)"
  [[ "$result" == "[INFO] test message" ]]
}

@test "warn output contains no escape codes when stderr is piped" {
  result="$(bash -c 'source ./awx; warn "test warning"' 2>&1 >/dev/null)"
  [[ "$result" == "[WARN] test warning" ]]
}

@test "error output contains no escape codes when stderr is piped" {
  result="$(bash -c 'source ./awx; error "test error"' 2>&1 >/dev/null)"
  [[ "$result" == "[ERROR] test error" ]]
}

@test "colour variables are empty strings when stdout is not a TTY" {
  result="$(bash -c 'source ./awx; printf "%s" "$COL_INFO"')"
  [[ -z "$result" ]]

  result="$(bash -c 'source ./awx; printf "%s" "$COL_WARN"')"
  [[ -z "$result" ]]

  result="$(bash -c 'source ./awx; printf "%s" "$COL_ERR"')"
  [[ -z "$result" ]]

  result="$(bash -c 'source ./awx; printf "%s" "$COL_RESET"')"
  [[ -z "$result" ]]
}
