#!/usr/bin/env bats

# All tests run zsh in a subprocess — bats itself runs in bash.
# Each test stubs compadd/_describe to capture completions.

ZSH_HELPER='
# Stub compadd to print each word to stdout
compadd() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -*) ;;  # skip option flags like -J -V -a
      *) printf "%s\n" "$arg" ;;
    esac
  done
}

# Stub _describe to print each description-less word
_describe() {
  shift  # skip description string
  local arr=("${(@P)1}")  # dereference array name
  local item
  for item in "${arr[@]}"; do
    printf "%s\n" "${item%%:*}"
  done
}

# Stub _arguments to trigger the state machine ourselves
_arguments() { return 0; }
'

COMPLETION_FILE="$(pwd)/completions/_awx"

# ---------------------------------------------------------------------------
# Test 1: completion script loads without errors
# ---------------------------------------------------------------------------
@test "completion script loads without zsh errors" {
  run zsh -c "source '$COMPLETION_FILE' && echo OK"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "OK" ]]
}

# ---------------------------------------------------------------------------
# Test 2: main commands appear in suggestions
# ---------------------------------------------------------------------------
@test "completion suggests main commands at position 1" {
  run zsh -c "
$ZSH_HELPER
source '$COMPLETION_FILE'
words=(awx '')
CURRENT=2
state=command
_awx
"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "use" ]]
  [[ "${output}" =~ "whoami" ]]
  [[ "${output}" =~ "eks" ]]
  [[ "${output}" =~ "logout" ]]
  [[ "${output}" =~ "help" ]]
}

# ---------------------------------------------------------------------------
# Test 3: profile names appear in suggestions (via mocked aws)
# ---------------------------------------------------------------------------
@test "completion suggests profile names at position 1" {
  local mock_dir
  mock_dir="$(pwd)/mock/bin"
  mkdir -p "$mock_dir"
  printf '#!/bin/sh\necho "dev-profile"\necho "prod-profile"\n' >"$mock_dir/aws"
  chmod +x "$mock_dir/aws"

  run zsh -c "
export PATH='${mock_dir}:\$PATH'
$ZSH_HELPER
source '$COMPLETION_FILE'
words=(awx '')
CURRENT=2
state=command
_awx
"
  rm -rf mock

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]
  [[ "${output}" =~ "prod-profile" ]]
}

# ---------------------------------------------------------------------------
# Test 4: awx eks suggests list and update
# ---------------------------------------------------------------------------
@test "completion suggests list and update after awx eks" {
  run zsh -c "
$ZSH_HELPER
source '$COMPLETION_FILE'
words=(awx eks '')
CURRENT=3
state=args
_awx
"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "list" ]]
  [[ "${output}" =~ "update" ]]
}

# ---------------------------------------------------------------------------
# Test 5: awx use suggests --profile and --cluster flags
# ---------------------------------------------------------------------------
@test "completion suggests --profile and --cluster after awx use" {
  run zsh -c "
$ZSH_HELPER
# Override _arguments to print the flags it would complete
_arguments() {
  for arg in \"\$@\"; do
    [[ \"\$arg\" == --* ]] && printf '%s\n' \"\${arg%%[:[]*}\"
  done
}
source '$COMPLETION_FILE'
words=(awx use '')
CURRENT=3
state=args
_awx
"
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "--profile" ]]
  [[ "${output}" =~ "--cluster" ]]
}

# ---------------------------------------------------------------------------
# Test 6: awx --profile suggests profile names
# ---------------------------------------------------------------------------
@test "completion suggests profile names after awx --profile" {
  local mock_dir
  mock_dir="$(pwd)/mock/bin"
  mkdir -p "$mock_dir"
  printf '#!/bin/sh\necho "dev-profile"\necho "prod-profile"\n' >"$mock_dir/aws"
  chmod +x "$mock_dir/aws"

  run zsh -c "
export PATH='${mock_dir}:\$PATH'
$ZSH_HELPER
source '$COMPLETION_FILE'
words=(awx --profile '')
CURRENT=3
state=args
_awx
"
  rm -rf mock

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]
  [[ "${output}" =~ "prod-profile" ]]
}
