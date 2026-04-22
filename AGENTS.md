# AGENTS.md

## Overview
This repository contains a Bash CLI script (`awx`) for lightweight AWS profile and EKS kubeconfig management. There are no formal unit tests or build/lint automation; the repo is designed to be a minimal, single-file, dependency-light solution. This guide describes manual validation steps, code contribution style, and Bash best practices for all agentic coding agents contributing here.

---

## 🚀 Build, Lint, and Test Commands

### Pre-commit GitHub Actions (GHA)
- Automated formatting and lint checks are enforced via [pre-commit](https://pre-commit.com/) GitHub Actions on commits and pull requests.
- The [`pre-commit`](.github/workflows/pre-commit.yml) workflow must pass: it runs hooks for code formatting, shell style, and basic static checks across all supported Python versions (for relevant hooks).
- To check your changes locally, [install pre-commit](https://pre-commit.com/#install) and run `pre-commit run --all-files` before pushing.
- Developers are required to execute this command before committing or pushing any changes.
- All contributors are expected to resolve pre-commit issues before submitting PRs.

### Building
- **No build step required.** Place/modify the single `awx` executable script in the project root. It is directly runnable.
- Grant execute permission if necessary:
  ```bash
  chmod +x awx
  ```

### Linting & Shell Style Checking
While there are no explicit linter configs, you are encouraged to validate shell scripts with the following tools (run manually):
- **ShellCheck static analysis**
  ```bash
  shellcheck awx
  ```
- **Bash strict mode** is enforced within the script (`set -euo pipefail`). All new code must preserve and not weaken strict mode discipline.

### Testing (Automated Framework)
While manual validation is always valuable, the project now incorporates a `bats-core` test framework for automated command verification.

### Running Tests with `bats`
1. Ensure you have the `bats-core` framework installed:
   ```bash
   curl -fsSL https://github.com/bats-core/bats-core/archive/refs/heads/master.zip -o bats.zip
   unzip bats.zip && cd bats-core-master && ./install.sh ~/bats-local && cd ..
   rm -rf bats.zip bats-core-master
   export PATH=$HOME/bats-local/bin:$PATH
   ```
2. Navigate to the project root and run all tests:
   ```bash
   bats tests
   ```
   Sample output:
   ```text
   1..4
   ok 1 awx whoami with valid AWS_PROFILE
   not ok 2 awx whoami with missing AWS_PROFILE
   ```
3. For individual tests, specify the filename explicitly:
   ```bash
   bats tests/whoami.bats
   ```

This framework ensures reproducible test coverage across edge cases, missing dependencies, and standard command validations.

#### Simulating Error Paths
- Unset environment variables: `unset AWS_PROFILE`
- Move/remove dependencies: `mv $(which fzf) ~/fzf.tmp`

---

## 🖋️ Coding and Code Style Guidelines

### General Principles
- **DRY Principle**: Adhere to "Don't Repeat Yourself" to reduce code duplication and ensure maintainability.
- **Bash-only**: All project logic is in Bash, with no external syntax (Python, JS, etc.)
- **Minimal dependencies**: Only common CLIs (`aws`, `fzf`, `jq`) are depended on—do not add new dependencies without justification.
- **One-file approach**: Unless explicitly required, do not split code into new files/scripts.
- **Error-first logic**: Fail early (using `die`); every critical external call is guarded.

### Formatting and Structure
- **Indentation**: 2 spaces (no tabs).
- **Quoting**: Always use double quotes for strings and variables (e.g., "$var"). Single quotes only for literals.
- **Function Names**: Lowercase with underscores (e.g., `log`, `require_cmd`).
- **Variable Names**: Lowercase with underscores, except exported environment variables, which are uppercase (e.g., `AWS_PROFILE`, `DEFAULT_REGION`).
- **Constants**: Use all-uppercase for exported or global configuration variables (e.g., `DEFAULT_REGION`).
- **Logging/Errors**: Always use standardized `log`, `warn`, or `error`/`die` functions. Do not echo to stderr directly.
- **Strict Mode**: Begin scripts with `set -euo pipefail` unless there is a good reason to relax it (which should be justified in comments).
- **Functions**: Use POSIX-compliant function definitions whenever possible:
  ```bash
  my_func() {
    # ...
  }
  ```
- **No trailing whitespace** at the end of lines.

### Imports & Sourcing
- This project does **not** use external includes or sourcing; all code should exist within the one script file.

### Error Handling
- All error conditions should trigger immediate and clear error messages (using `die` or `error`).
- If a subcommand is called without required context (e.g., `AWS_PROFILE` is not set), fail with message and nonzero exit code.
- Always check exit status of critical commands, especially external CLI calls.
- Always check for required dependencies at script entry.
- Use `|| die "..."` after any command that must not fail.

### README

Update the README after each feature completion.
Add new features to the section Features.
Update usage if CLI usage changed or improved.

---

## 🏷️ Naming Conventions
- **Functions**: all lower_snake_case (e.g. `list_clusters`, `select_profile`).
- **Variables**: lower_snake_case for locals, UPPER_SNAKE_CASE for env or exported values.
- **Subcommands**: `use`, `whoami`, `eks list`, `eks update`.

---

## 🛑 What Not To Do
- Do **not** add language-specific automation support (Makefile, tox, npm, etc.) unless project expands its scope.
- Do **not** break single-file nature without express reason.
- Do **not** relax Bash strict mode.
- Do **not** add dependency on shell features beyond bash POSIX compatibility.

---

## 🤖 Automated Agent Responsibility Checklist
- [ ] Run `shellcheck awx`, resolve warnings and errors
- [ ] Validate strict mode conformance (`set -euo pipefail`), do not weaken
- [ ] Preserve function/variable naming conventions
- [ ] Validate each feature with the given tests in tests/
- [ ] Preserve/expand logging consistency across all output
- [ ] Keep all code in a single file unless justified
- [ ] Document all new command-line options in usage output and this file
- [ ] Do not introduce silent failures: all error conditions are surfaced
- [ ] Confirm that all dependencies (aws, fzf, jq) are required and checked
- [ ] Run pre-commit run --all-files after each change in bash/shell scripts
- [ ] Update README.md and AGENTS.md after each feature addition

---

## 📜 License reminder
This project is open-source under MIT. All agents must respect this license, and all contributions must be compatible with MIT license conditions.
