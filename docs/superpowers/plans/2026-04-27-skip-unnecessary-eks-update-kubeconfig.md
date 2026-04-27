# Skip Unnecessary `aws eks update-kubeconfig` Executions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Avoid redundant `aws eks update-kubeconfig` calls when the kubeconfig context for the active profile already points to the correct cluster, and add a `--force` flag to bypass the skip.

**Architecture:** Add two new functions (`_kubeconfig_context_matches`, `_eks_ensure_kubeconfig`) between the existing `_eks_update_kubeconfig` and its callers. All three call sites (`awx_use`, `awx_prev`, `awx_eks update`) switch to the new wrapper. `kubectl` becomes a required dependency.

**Tech Stack:** Bash, bats-core (tests), kubectl (new dependency), aws CLI, jq, fzf.

**Spec:** `docs/superpowers/specs/2026-04-27-skip-unnecessary-eks-update-kubeconfig-design.md`

---

## File Map

| File | Action | What changes |
|---|---|---|
| `awx` | Modify | Add `_kubeconfig_context_matches`, `_eks_ensure_kubeconfig`; update `check_deps`, `awx_use`, `awx_prev`, `awx_eks`, `show_help` |
| `tests/kubeconfig_performance.bats` | Create | 5 new bats tests for the skip/update logic |
| `README.md` | Modify | Add `kubectl` to prerequisites; document `--force` flag; add skip-optimization note |

---

## Task 1: Create `tests/kubeconfig_performance.bats` with all failing tests

**Files:**
- Create: `tests/kubeconfig_performance.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/kubeconfig_performance.bats << 'ENDOFFILE'
#!/usr/bin/env bats

setup() {
  CALL_LOG="$(mktemp)"
  export CALL_LOG
  export DEFAULT_REGION="eu-central-1"
  export AWS_PROFILE="test-profile"
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws: capture update-kubeconfig calls; return success for STS and configure
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"update-kubeconfig"* ]]; then
  echo "called" >>"$CALL_LOG"
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{"UserId":"TEST","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
fi
EOF
  chmod +x mock/bin/aws

  # fzf and jq stubs (not invoked by _eks_ensure_kubeconfig directly, but needed for sourcing)
  printf '#!/usr/bin/env bash\nexit 0\n' >mock/bin/fzf
  printf '#!/usr/bin/env bash\ncat\n' >mock/bin/jq
  chmod +x mock/bin/fzf mock/bin/jq
}

teardown() {
  rm -f "$CALL_LOG"
  rm -rf mock
}

@test "_eks_ensure_kubeconfig skips update when context already matches cluster" {
  # kubectl returns ARN whose suffix matches the cluster name
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/test-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "already up-to-date" ]]
  [ ! -s "$CALL_LOG" ]  # update-kubeconfig must NOT have been called
}

@test "_eks_ensure_kubeconfig runs update when context exists but points to a different cluster" {
  # kubectl returns ARN for a DIFFERENT cluster
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/other-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called
}

@test "_eks_ensure_kubeconfig runs update when context does not exist" {
  # kubectl returns empty (context not found)
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called
}

@test "_eks_ensure_kubeconfig --force bypasses skip even when context already matches" {
  # kubectl returns matching ARN — but --force should still trigger the update
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/test-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1" "--force"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called despite match
}

@test "_eks_ensure_kubeconfig warns and runs update when kubectl is not available" {
  # No kubectl in mock/bin — ensure it is absent from PATH mock
  # (mock/bin/kubectl deliberately not created)

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1" 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "kubectl" ]]  # warn message must mention kubectl
  [ -s "$CALL_LOG" ]              # update-kubeconfig MUST have been called as fallback
}
ENDOFFILE
chmod +x tests/kubeconfig_performance.bats
```

- [ ] **Step 2: Run the tests to confirm they fail (functions not yet defined)**

```bash
bats tests/kubeconfig_performance.bats
```

Expected: all 5 tests fail with errors like `_eks_ensure_kubeconfig: command not found` or similar. If bats is not installed: `brew install bats-core` (macOS) or see README.

---

## Task 2: Add `_kubeconfig_context_matches` and `_eks_ensure_kubeconfig` to `awx`

**Files:**
- Modify: `awx` (after line 196, after `_eks_update_kubeconfig`)

- [ ] **Step 1: Open `awx` and locate the end of `_eks_update_kubeconfig` (currently ends at line 196)**

The block to find:
```bash
_eks_update_kubeconfig() {
  local profile="$1"
  local cluster="$2"
  local region="${3:-$DEFAULT_REGION}"

  log "Updating kubeconfig for cluster: $cluster"
  AWS_PAGER="" aws --profile "$profile" eks update-kubeconfig \
    --region "$region" --name "$cluster" --alias "$profile" ||
    die "Failed to update kubeconfig for cluster: $cluster"
  log "Kubeconfig updated successfully"
}
```

- [ ] **Step 2: Insert both new functions immediately after `_eks_update_kubeconfig`**

Add after the closing `}` of `_eks_update_kubeconfig`:

```bash
# Returns 0 if the kubeconfig context <profile> already points to <cluster>.
# Handles both plain cluster names and ARN format
# (arn:aws:eks:<region>:<account>:cluster/<name>).
_kubeconfig_context_matches() {
  local profile="$1"
  local cluster="$2"
  local ctx_cluster
  ctx_cluster="$(kubectl config view \
    -o jsonpath="{.contexts[?(@.name==\"${profile}\")].context.cluster}" \
    2>/dev/null || true)"
  [[ "$ctx_cluster" == *"/${cluster}" || "$ctx_cluster" == "${cluster}" ]]
}

# Skip update-kubeconfig when the context is already correct.
# Usage: _eks_ensure_kubeconfig <profile> <cluster> [region] [--force]
_eks_ensure_kubeconfig() {
  local profile="$1"
  local cluster="$2"
  local region="${3:-$DEFAULT_REGION}"
  local force="false"
  [[ "${4:-}" == "--force" ]] && force="true"

  if [[ "$force" != "true" ]]; then
    if ! command -v kubectl >/dev/null 2>&1; then
      warn "kubectl not found; skipping kubeconfig check, running update"
    elif _kubeconfig_context_matches "$profile" "$cluster"; then
      log "Kubeconfig already up-to-date for cluster: $cluster (skipping update)"
      return 0
    fi
  fi

  _eks_update_kubeconfig "$profile" "$cluster" "$region"
}
```

- [ ] **Step 3: Run the new tests to verify they pass**

```bash
bats tests/kubeconfig_performance.bats
```

Expected: all 5 tests pass.

- [ ] **Step 4: Run the existing helper tests to confirm no regression**

```bash
bats tests/test_kubeconfig_helper.bats
```

Expected: both tests pass (`_eks_update_kubeconfig` is unchanged).

- [ ] **Step 5: Commit**

```bash
git add awx tests/kubeconfig_performance.bats
git commit -m "feat: add _eks_ensure_kubeconfig to skip redundant update-kubeconfig calls"
```

---

## Task 3: Add `kubectl` to `check_deps`

**Files:**
- Modify: `awx` (the `check_deps` function, currently lines 72-76)

- [ ] **Step 1: Locate `check_deps` and add `kubectl`**

Find:
```bash
check_deps() {
  require_cmd aws
  require_cmd fzf
  require_cmd jq
}
```

Replace with:
```bash
check_deps() {
  require_cmd aws
  require_cmd fzf
  require_cmd jq
  require_cmd kubectl
}
```

- [ ] **Step 2: Run the full test suite to confirm no regressions**

```bash
bats tests
```

Expected: all tests pass. (The bats tests that call `awx use` or `awx eks list` through the full command path mock all binaries including kubectl via PATH, so they should still pass.)

- [ ] **Step 3: Commit**

```bash
git add awx
git commit -m "feat: add kubectl as required dependency"
```

---

## Task 4: Update `awx_use` — switch to `_eks_ensure_kubeconfig` with `--force`

**Files:**
- Modify: `awx` (the `awx_use` function, currently lines 198-243)

- [ ] **Step 1: Add `local force="false"` and `--force` flag parsing to `awx_use`**

Find the start of `awx_use`:
```bash
awx_use() {
  local profile=""
  local cluster=""

  # Parse optional flags; fall back to interactive when absent
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ -n "${2:-}" ]] || die "--profile requires a value"
        profile="$2"
        shift 2
        ;;
      --cluster)
        [[ -n "${2:-}" ]] || die "--cluster requires a value"
        cluster="$2"
        shift 2
        ;;
      *) die "Unknown flag: $1" ;;
    esac
  done
```

Replace with:
```bash
awx_use() {
  local profile=""
  local cluster=""
  local force="false"

  # Parse optional flags; fall back to interactive when absent
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)
        [[ -n "${2:-}" ]] || die "--profile requires a value"
        profile="$2"
        shift 2
        ;;
      --cluster)
        [[ -n "${2:-}" ]] || die "--cluster requires a value"
        cluster="$2"
        shift 2
        ;;
      --force)
        force="true"
        shift
        ;;
      *) die "Unknown flag: $1" ;;
    esac
  done
```

- [ ] **Step 2: Replace the `_eks_update_kubeconfig` call in `awx_use` with `_eks_ensure_kubeconfig`**

Find (near the end of `awx_use`):
```bash
  _eks_update_kubeconfig "$profile" "$cluster" "$DEFAULT_REGION"
  _awx_state_write "$profile" "$cluster"
```

Replace with:
```bash
  _eks_ensure_kubeconfig "$profile" "$cluster" "$DEFAULT_REGION" "${force:+--force}"
  _awx_state_write "$profile" "$cluster"
```

- [ ] **Step 3: Run the full test suite**

```bash
bats tests
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add awx
git commit -m "feat: awx_use uses _eks_ensure_kubeconfig with --force support"
```

---

## Task 5: Update `awx_prev` — switch to `_eks_ensure_kubeconfig`

**Files:**
- Modify: `awx` (the `awx_prev` function, currently lines 307-348)

- [ ] **Step 1: Replace the `_eks_update_kubeconfig` call in `awx_prev`**

Find (near the end of `awx_prev`):
```bash
  if [[ -n "$prev_cluster" ]]; then
    _eks_update_kubeconfig "$prev_profile" "$prev_cluster" "$DEFAULT_REGION"
  else
    warn "No cluster stored for previous environment; kubeconfig not updated"
  fi
```

Replace with:
```bash
  if [[ -n "$prev_cluster" ]]; then
    _eks_ensure_kubeconfig "$prev_profile" "$prev_cluster" "$DEFAULT_REGION"
  else
    warn "No cluster stored for previous environment; kubeconfig not updated"
  fi
```

- [ ] **Step 2: Run the full test suite**

```bash
bats tests
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add awx
git commit -m "feat: awx_prev uses _eks_ensure_kubeconfig to skip redundant updates"
```

---

## Task 6: Update `awx_eks update` — switch to `_eks_ensure_kubeconfig` with `--force`

**Files:**
- Modify: `awx` (the `update)` branch inside `awx_eks`, currently lines 280-283)

- [ ] **Step 1: Replace the `update)` branch in `awx_eks`**

Find:
```bash
    update)
      cluster="$(select_cluster_for_profile "$profile")" || die "No EKS cluster selected"
      _eks_update_kubeconfig "$profile" "$cluster" "$DEFAULT_REGION"
      _awx_state_write "$profile" "$cluster"
      ;;
```

Replace with:
```bash
    update)
      local force="false"
      [[ "${2:-}" == "--force" ]] && force="true"
      cluster="$(select_cluster_for_profile "$profile")" || die "No EKS cluster selected"
      _eks_ensure_kubeconfig "$profile" "$cluster" "$DEFAULT_REGION" "${force:+--force}"
      _awx_state_write "$profile" "$cluster"
      ;;
```

- [ ] **Step 2: Run the full test suite**

```bash
bats tests
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add awx
git commit -m "feat: awx_eks update uses _eks_ensure_kubeconfig with --force support"
```

---

## Task 7: Update `show_help` to document `--force` and `kubectl`

**Files:**
- Modify: `awx` (the `show_help` function, currently lines 350-361)

- [ ] **Step 1: Replace `show_help`**

Find:
```bash
show_help() {
  echo "Usage: awx [command]"
  echo "Commands:"
  echo "  use [--profile P] [--cluster C]  Select AWS profile/cluster (interactive fallback)"
  echo "  <profile>                         Shortcut: set profile and update kubeconfig"
  echo "  whoami                            Display current AWS identity"
  echo "  eks list                          List EKS clusters for the active profile"
  echo "  eks update                        Update kubeconfig for a specific EKS cluster"
  echo "  logout                            Logout of the current AWS SSO session"
  echo "  -                                 Toggle back to previous AWS profile/cluster (like cd -)"
  echo "  help | -h                         Show this help message"
}
```

Replace with:
```bash
show_help() {
  echo "Usage: awx [command]"
  echo "Commands:"
  echo "  use [--profile P] [--cluster C] [--force]  Select AWS profile/cluster (interactive fallback)"
  echo "  <profile>                                   Shortcut: set profile and update kubeconfig"
  echo "  whoami                                      Display current AWS identity"
  echo "  eks list                                    List EKS clusters for the active profile"
  echo "  eks update [--force]                        Update kubeconfig for a specific EKS cluster"
  echo "  logout                                      Logout of the current AWS SSO session"
  echo "  -                                           Toggle back to previous AWS profile/cluster (like cd -)"
  echo "  help | -h                                   Show this help message"
  echo ""
  echo "Flags:"
  echo "  --force  Skip kubeconfig-up-to-date check and always run update-kubeconfig"
}
```

- [ ] **Step 2: Run tests**

```bash
bats tests
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add awx
git commit -m "docs: update show_help to document --force flag"
```

---

## Task 8: Run `shellcheck` and `pre-commit`

**Files:** none — validation only

- [ ] **Step 1: Run shellcheck**

```bash
shellcheck awx
```

Expected: no errors or warnings. If warnings appear (e.g., SC2001, SC2016), fix them before proceeding.

- [ ] **Step 2: Run pre-commit**

```bash
pre-commit run --all-files
```

Expected: all hooks pass. Fix any failures, then re-run until clean.

- [ ] **Step 3: Commit any pre-commit auto-fixes**

```bash
git add awx
git commit -m "fix: apply shellcheck and pre-commit formatting fixes"
```

(Skip this step if there were no auto-fixes.)

---

## Task 9: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `kubectl` to the prerequisites list (currently lines 71-74)**

Find:
```markdown
### 1. Install Dependencies
- [AWS CLI](https://aws.amazon.com/cli/)
- [fzf](https://github.com/junegunn/fzf)
- [jq](https://jqlang.org/)
```

Replace with:
```markdown
### 1. Install Dependencies
- [AWS CLI](https://aws.amazon.com/cli/)
- [fzf](https://github.com/junegunn/fzf)
- [jq](https://jqlang.org/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) (required for kubeconfig context inspection)
```

- [ ] **Step 2: Add `--force` to the usage examples (currently around lines 38-49)**

Find:
```markdown
# Non-interactive mode (for scripts and automation)
awx use --profile my-profile                 # Set profile without prompts
awx use --profile my-profile --cluster myc   # Fully non-interactive
awx --profile my-profile                     # Top-level flag (equivalent to above)

# Other commands
awx whoami                                   # Show current AWS identity
awx eks list                                 # List available EKS clusters for active profile
awx eks update                               # Update kubeconfig for a specific cluster
awx help or -h                               # Show detailed usage instructions
awx logout                                   # Logout of the current AWS SSO session
```

Replace with:
```markdown
# Non-interactive mode (for scripts and automation)
awx use --profile my-profile                 # Set profile without prompts
awx use --profile my-profile --cluster myc   # Fully non-interactive
awx --profile my-profile                     # Top-level flag (equivalent to above)
awx use --profile my-profile --force         # Force kubeconfig update even if already current

# Other commands
awx whoami                                   # Show current AWS identity
awx eks list                                 # List available EKS clusters for active profile
awx eks update                               # Update kubeconfig for a specific cluster (skips if current)
awx eks update --force                       # Force kubeconfig update regardless of current state
awx help or -h                               # Show detailed usage instructions
awx logout                                   # Logout of the current AWS SSO session
```

- [ ] **Step 3: Add a "Performance" note to the Features section (after line 26)**

Find:
```markdown
- Automatically updates current [`kubeconfig`](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
```

Replace with:
```markdown
- Automatically updates current [`kubeconfig`](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) — skips the update when the context already points to the correct cluster, avoiding redundant AWS API calls
```

- [ ] **Step 4: Update the Tips section to mention `--force` (around line 162)**

Find:
```markdown
- If required tools (`aws`, `fzf`, or `jq`) are missing, `awx` will tell you exactly what to install.
```

Replace with:
```markdown
- If required tools (`aws`, `fzf`, `jq`, or `kubectl`) are missing, `awx` will tell you exactly what to install.
- `awx use` and `awx eks update` skip `update-kubeconfig` when the kubeconfig context already points to the correct cluster. Use `--force` to override this and force a full update.
```

- [ ] **Step 5: Run the full test suite one final time**

```bash
bats tests
```

Expected: all tests pass.

- [ ] **Step 6: Commit README changes**

```bash
git add README.md
git commit -m "docs: add kubectl dependency and --force flag documentation to README"
```

---

## Self-Review Checklist

- [x] **Spec coverage:** All acceptance criteria from issue #43 are covered:
  - Skip when context already exists → Task 2 (`_eks_ensure_kubeconfig` + tests 1, 3)
  - No redundant API calls → Task 2
  - `awx use` faster on repeat → Tasks 4, 5, 6
  - Behavior unchanged when cluster changes → test 2
  - No regression → Task 3 (`check_deps`), Task 8 (full suite)
  - Logging indicates skip → Task 2 (`log "Kubeconfig already up-to-date..."`)
- [x] **Placeholder scan:** No TBD, TODO, or vague steps. All code is complete.
- [x] **Type consistency:** `_eks_ensure_kubeconfig` signature is identical across Tasks 2, 4, 5, 6. `${force:+--force}` expansion produces `--force` or empty string — matches `[[ "${4:-}" == "--force" ]]` guard in the function.
- [x] **ARN matching:** `_kubeconfig_context_matches` uses `*"/${cluster}"` glob — covers both `arn:...:cluster/name` and plain `name` forms.
- [x] **kubectl in check_deps:** Added in Task 3; tests that mock all binaries via PATH include kubectl mock in `setup()` of `kubeconfig_performance.bats`.
