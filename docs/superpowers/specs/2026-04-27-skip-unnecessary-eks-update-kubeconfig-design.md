# Design: Skip Unnecessary `aws eks update-kubeconfig` Executions

**Date:** 2026-04-27
**Issue:** [#43](https://github.com/cschindlbeck/awx/issues/43)
**Status:** Approved

---

## Problem

`aws eks update-kubeconfig` is the slowest step in the `awx` workflow. It makes AWS API calls, resolves SSO credentials, parses the kubeconfig file, and merges changes. In many cases (e.g., repeated `awx use` calls for the same profile/cluster), the context already exists and points to the correct cluster, making the operation redundant.

---

## Goal

Skip `aws eks update-kubeconfig` when the kubeconfig context for the active profile already points to the target cluster. Provide a `--force` flag to bypass the skip when needed.

---

## Design Decisions

| Question | Decision |
|---|---|
| Skip condition | Context `$profile` exists in kubeconfig AND its cluster field matches `$cluster` (ARN suffix or exact) |
| kubectl dependency | Add `kubectl` as a required dependency (via `require_cmd`) |
| Force escape hatch | Add `--force` flag to `awx use` and `awx eks update` |
| `awx_prev` behavior | Uses `_eks_ensure_kubeconfig` without `--force` (skip if already correct) |

---

## Architecture

### New Functions

#### `_kubeconfig_context_matches <profile> <cluster>`

Pure read function. Uses `kubectl config view -o jsonpath` to inspect the kubeconfig cluster entry for the named context. Returns 0 if the context `$profile` exists and its cluster field ends with `/$cluster` or equals `$cluster`. Returns 1 otherwise.

```bash
_kubeconfig_context_matches() {
  local profile="$1"
  local cluster="$2"
  local ctx_cluster
  ctx_cluster="$(kubectl config view \
    -o jsonpath="{.contexts[?(@.name==\"${profile}\")].context.cluster}" \
    2>/dev/null || true)"
  # ARN format: arn:aws:eks:region:account:cluster/cluster-name
  [[ "$ctx_cluster" == *"/${cluster}" || "$ctx_cluster" == "${cluster}" ]]
}
```

#### `_eks_ensure_kubeconfig <profile> <cluster> [region] [--force]`

Decision function. Checks if the kubeconfig is already correct and skips if so, otherwise delegates to `_eks_update_kubeconfig`. Falls back gracefully if `kubectl` is unavailable.

```bash
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

### Modified Functions

**`awx_use`**: Add `--force` flag parsing in the `while` loop. Pass it to `_eks_ensure_kubeconfig`.

**`awx_eks update`**: Add `--force` flag parsing. Pass it to `_eks_ensure_kubeconfig`.

**`awx_prev`**: Switch from `_eks_update_kubeconfig` to `_eks_ensure_kubeconfig` (no `--force`).

**`check_deps`**: Add `require_cmd kubectl`.

**`show_help`**: Document `--force` for `use` and `eks update`.

### Unchanged

`_eks_update_kubeconfig` remains a pure "always-update" primitive — no behavioral changes. Existing tests in `test_kubeconfig_helper.bats` are unaffected.

---

## Error Handling

- If `kubectl` is not in PATH: `[WARN]` is logged and `_eks_update_kubeconfig` runs (safe fallback).
- If `kubectl config view` returns an error: the jsonpath result is empty → treated as "no match" → update runs.
- `--force` always runs the update regardless of kubeconfig state.

---

## Tests

New file: `tests/kubeconfig_performance.bats`

| # | Test | Assertion |
|---|---|---|
| 1 | Context exists and cluster matches | `aws eks update-kubeconfig` NOT called |
| 2 | Context exists but cluster differs | `aws eks update-kubeconfig` IS called |
| 3 | Context does not exist | `aws eks update-kubeconfig` IS called |
| 4 | `--force` flag bypasses skip | Update IS called even when context matches |
| 5 | `kubectl` unavailable | `[WARN]` logged, update IS called |

Existing tests in `test_kubeconfig_helper.bats` are unchanged.

---

## README Changes

- Add `kubectl` to the "Prerequisites" / "Dependencies" section.
- Add `--force` flag to usage examples for `awx use` and `awx eks update`.
- Add a note about the skip optimization under a "Performance" or "Features" section.

---

## Acceptance Criteria (from issue #43)

- [x] `update-kubeconfig` is skipped if the target cluster context already exists and matches
- [x] No redundant AWS API calls when not needed
- [x] `awx use` feels faster on repeated operations
- [x] Behavior unchanged when cluster changes
- [x] No regression in kubeconfig correctness
- [x] Logging clearly indicates when update is skipped
