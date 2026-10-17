# AGENTS.md

## Overview
This repository contains a Bash CLI script (`awx`). The script manages AWS profiles and EKS kubeconfig files. The project is small. It has one file and few dependencies. A `Makefile` gives one interface for the common development tasks (test, lint, install). This guide tells all coding agents how to validate changes, how to write code, and which Bash practices to follow.

---

## 🚀 Build, Lint, and Test Commands

### Makefile (recommended)
Use the `Makefile` as the main interface for development tasks:

| Command        | Description                              |
|----------------|------------------------------------------|
| `make help`    | List all available targets               |
| `make test`    | Run all bats tests                       |
| `make lint`    | Run pre-commit hooks on all files        |
| `make check`   | Run tests **and** lint                   |
| `make install` | Symlink `awx` to `~/.local/bin`          |
| `make dev`     | Check development dependency status      |
| `make clean`   | Remove pre-commit cache and temp files   |

### Pre-commit GitHub Actions (GHA)
- The [pre-commit](https://pre-commit.com/) GitHub Actions workflow checks formatting and lint on each commit and pull request.
- The [`pre-commit`](.github/workflows/pre-commit.yml) workflow must pass. It runs hooks for code formatting, shell style, and basic static checks.
- Before you push, run `make lint` or `pre-commit run --all-files`.
- You must run this command before you commit or push any change.
- Fix all pre-commit errors before you submit a PR.

### Building
- **No build step is necessary.** Put the single `awx` executable script in the project root. You can run it directly.
- If necessary, give it execute permission:
  ```bash
  chmod +x awx
  ```

### Linting & Shell Style Checking
The project has no linter configuration files. We recommend that you check shell scripts with these tools (run them manually):
- **ShellCheck static analysis**
  ```bash
  shellcheck awx
  ```
- **Bash strict mode** is on in the script (`set -euo pipefail`). New code must keep strict mode. Do not make it weaker.

### Testing (Automated Framework)
Manual validation is useful. The project also uses the `bats-core` test framework for automated command checks.

### Running Tests with `bats`
1. Install the `bats-core` framework:
   ```bash
   curl -fsSL https://github.com/bats-core/bats-core/archive/refs/heads/master.zip -o bats.zip
   unzip bats.zip && cd bats-core-master && ./install.sh ~/bats-local && cd ..
   rm -rf bats.zip bats-core-master
   export PATH=$HOME/bats-local/bin:$PATH
   ```
2. Go to the project root and run all tests:
   ```bash
   bats tests
   ```
   Sample output:
   ```text
   1..4
   ok 1 awx whoami with valid AWS_PROFILE
   not ok 2 awx whoami with missing AWS_PROFILE
   ```
3. To run one test file, give the file name:
   ```bash
   bats tests/whoami.bats
   ```

The tests give repeatable coverage of edge cases, missing dependencies, and standard commands.

#### Simulating Error Paths
- Unset environment variables: `unset AWS_PROFILE`
- Move or remove dependencies: `mv $(which fzf) ~/fzf.tmp`

---

## 🖋️ Coding and Code Style Guidelines

### General Principles
- **DRY Principle**: Follow "Don't Repeat Yourself". This reduces duplicate code and makes maintenance easier.
- **Bash-only**: Write all project logic in Bash. Do not use other languages (Python, JS, etc.).
- **Minimal dependencies**: The hard requirements are the common CLIs `aws`, `fzf`, and `jq`. `kubectl` is optional. It gives fast context changes. Do not add new dependencies without a reason.
- **One-file approach**: Do not split the code into new files or scripts, unless a requirement says so.
- **Error-first logic**: Fail early (use `die`). Guard each critical external call.

### Formatting and Structure
- **Indentation**: 2 spaces (no tabs).
- **Quoting**: Always use double quotes for strings and variables (for example, "$var"). Use single quotes only for literals.
- **Function Names**: Use lowercase with underscores (for example, `log`, `require_cmd`).
- **Variable Names**: Use lowercase with underscores. Exported environment variables use uppercase (for example, `AWS_PROFILE`, `DEFAULT_REGION`).
- **Constants**: Use all-uppercase for exported or global configuration variables (for example, `DEFAULT_REGION`).
- **Logging/Errors**: Always use the standard `log`, `warn`, or `error`/`die` functions. Do not write to stderr directly with `echo`.
- **Strict Mode**: Begin scripts with `set -euo pipefail`. Relax it only for a good reason. Explain the reason in a comment.
- **Functions**: Use POSIX-compliant function definitions when possible:
  ```bash
  my_func() {
    # ...
  }
  ```
- **No trailing whitespace** at the end of lines.

### Imports & Sourcing
- This project does **not** use external includes or sourcing. All code must stay in the one script file.

### Error Handling
- Each error condition must cause an immediate and clear error message (use `die` or `error`).
- If a user runs a subcommand without the required context (for example, `AWS_PROFILE` is not set), the command must fail with a message and a nonzero exit code.
- Always check the exit status of critical commands, especially external CLI calls.
- Always check for required dependencies at script entry.
- Use `|| die "..."` after each command that must not fail.

### README

Update the README after you complete each feature (do not use em dashes).
Add new features to the section Features.
Update the usage section when the CLI usage changes.

---

## 📝 Git Workflow

### Branch Naming Convention
- **Feature branches**: `feat-<featureName>` (for example, `feat-add-eks-support`)
- **Bug fix branches**: `fix-<bugName>` (for example, `fix-profile-loading`)
- **Never commit directly to the `main` or `dev`** branches

### Commit Message Format
All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation changes only
- `style`: Changes that do not affect the meaning of the code (whitespace, formatting, missing semicolons, etc.)
- `refactor`: A code change that does not fix a bug and does not add a feature
- `perf`: A code change that improves performance
- `test`: Add or update tests

**Examples:**
- `feat(eks): add cluster update command`
- `fix(profile): resolve AWS_PROFILE not persisting`
- `docs: update installation instructions`
- `refactor: consolidate profile selection logic`

### Workflow Steps
1. Create a new branch from `main` or `dev` (use the one with the most recent common root). Use the naming convention above.
2. Make your changes.
3. Run `make dev` to check your local toolchain.
4. Make sure that all pre-commit checks pass: `make lint` (or `pre-commit run --all-files`).
5. Commit with a descriptive message that follows Conventional Commits.
6. Push your branch and create a pull request.
7. Do not merge without approval from the maintainers.

---

## 🏷️ Naming Conventions
- **Functions**: all lower_snake_case (for example, `list_clusters`, `select_profile`).
- **Variables**: lower_snake_case for locals, UPPER_SNAKE_CASE for environment or exported values.
- **Subcommands**: `use`, `whoami`, `eks list`, `eks update`.

---

## 🛑 What Not To Do
- Do **not** break the single-file structure of the `awx` script without an explicit reason.
- Do **not** relax Bash strict mode.
- Do **not** depend on shell features that are not in Bash or POSIX.
- Do **not** add new language runtimes (Python, Node, etc.) to the core toolchain.

---

## 🤖 Automated Agent Responsibility Checklist
- [ ] Run `shellcheck awx`. Fix all warnings and errors.
- [ ] Make sure that the code follows strict mode (`set -euo pipefail`). Do not make it weaker.
- [ ] Keep the function and variable naming conventions
- [ ] Validate each feature with the given tests in tests/
- [ ] Keep the logging consistent across all output. Expand it where necessary.
- [ ] Keep all code in one file, unless there is a reason
- [ ] Document each new command-line option in the usage output and in this file
- [ ] Do not add silent failures. Show all error conditions.
- [ ] Make sure that all dependencies (aws, fzf, jq) are required and checked. `kubectl` is optional. The script must work correctly when `kubectl` is not installed.
- [ ] Run `pre-commit run --all-files` after each change in bash/shell scripts
- [ ] Update README.md and AGENTS.md after each feature addition

---

## 📜 License reminder
This project is open-source under the MIT license. All agents must respect this license. All contributions must be compatible with the MIT license conditions.
