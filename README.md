<div align="center">
  <img src="awx.png" alt="awx" width="300"/>

# awx

![Bats Tests](https://github.com/cschindlbeck/awx/actions/workflows/test.yaml/badge.svg)
![pre-commit](https://github.com/cschindlbeck/awx/actions/workflows/pre-commit.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

_Fast AWS Profile & EKS Context Switching for DevOps and Cloud Engineers_
</div>

## Overview

`awx` is a minimal Bash CLI to streamline AWS SSO login, profile switching, and EKS kubeconfig management for multi-account AWS setups with EKS clusters.

## Features

- Fuzzy, interactive AWS profile selection via [`fzf`](https://github.com/junegunn/fzf)
- Non-interactive mode: `awx use --profile X --cluster Y` for scripts and automation
- Profile shortcut: `awx profile-name` as an alias for `awx use --profile profile-name`
- **`awx -`** — Toggle back to the previous AWS profile and EKS cluster (like `cd -` / `git checkout -`)
- Zsh tab completion for commands, subcommands, and AWS profile names
- SSO login automation; minimal credential hassle
- Automatically updates current [`kubeconfig`](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) and **skips redundant updates** when the target context already exists (requires `kubectl`)
- Shows your current AWS identity as confirmation
- Friendly and clear error output with robust logging
- **`awx profiles`** — Lists all configured AWS profiles with `ACTIVE`/`EXPIRED` session status, without triggering SSO login
- **EKS cluster caching** — cluster lists are cached per profile (default TTL: 8 hours) to reduce AWS API calls
- ASCII art banner in help output (suppress with `AWX_NO_ASCII=true`)
- **`awx update`** — Self-update to the latest version from GitHub with a single command

## Usage
`awx` is a versatile script for managing AWS profiles and EKS kubeconfig contexts. Below are the primary commands and their purposes:

```sh
# Interactive mode (prompts with fuzzy finder)
awx                                          # Select AWS profile and cluster
awx use                                      # Same as awx
awx profile-name                             # Shortcut: set profile, then select cluster

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
awx profiles                                 # List all configured AWS profiles with ACTIVE/EXPIRED session status
awx update                                   # Update awx to the latest version from GitHub
```

### Toggle to previous environment

Switch back to the last used profile/cluster:

```bash
awx -
```

Running `awx -` again toggles back to the original environment. State is persisted across shell sessions in `~/.local/state/awx/env`.

### Example Workflow
```sh
$ awx
[INFO] Using profile: client-A (region: eu-central-1)
[INFO] Updating kubeconfig for cluster: cluster1-client-A
[INFO] Kubeconfig updated successfully

# On a repeated call when the context already exists:
$ awx
[INFO] Using profile: client-A (region: eu-central-1)
[INFO] Kubeconfig context already exists for cluster: cluster1-client-A, switching to context: client-A
```

## Installation

### Quick Install (recommended)

Install `awx` with a single command:

```bash
curl -sSL https://raw.githubusercontent.com/cschindlbeck/awx/main/install.sh | bash
```

The script will:
- Download `awx` to `~/.local/bin/awx`
- Add a `source` line to your shell config (`~/.zshrc` or `~/.bashrc`)
- Auto-install Zsh completions if Oh My Zsh is detected

Then reload your shell and verify:

```bash
source ~/.zshrc   # or ~/.bashrc
awx help
```

To update `awx` at any time after installation:

```bash
awx update
```

**Environment overrides** (all optional):

| Variable             | Default             | Purpose                                              |
|----------------------|---------------------|------------------------------------------------------|
| `INSTALL_DIR`        | `~/.local/bin`      | Directory to install the `awx` script                |
| `SHELL_RC`           | auto-detected       | Shell config file to add the `source` line to        |
| `COMPLETIONS_DIR`    | auto-detected       | Directory for Zsh completion file                    |
| `BRANCH`             | `main`              | GitHub branch to fetch from                          |
| `NO_MODIFY_SHELL_RC` | `false`             | Set to `true` to skip shell config modification      |

Example: install to a custom directory without modifying the shell config:

```bash
INSTALL_DIR=~/bin NO_MODIFY_SHELL_RC=true \
  curl -sSL https://raw.githubusercontent.com/cschindlbeck/awx/main/install.sh | bash
```

### Manual Install

#### 1. Install Dependencies
- [AWS CLI](https://aws.amazon.com/cli/)
- [fzf](https://github.com/junegunn/fzf)
- [jq](https://jqlang.org/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) _(optional but recommended — enables fast context switching without a full `aws eks update-kubeconfig` call)_

#### 2. Clone and Set Up
```sh
git clone https://github.com/cschindlbeck/awx.git
cd awx
chmod +x awx

# Option 1: Source awx script
# Add one of the following lines to your ~/.zshrc file:
# Using full path: source /path/to/awx
# or using relative path (if in repo): source $(pwd)/awx

# Option 2: Use with oh-my-zsh (or similar setup)
ln -s $(pwd)/awx ~/.oh-my-zsh/custom/awx.zsh

# Option 3: Source awx via .zshrc
# Add the following line to your ~/.zshrc file:
source $(pwd)/awx
```

#### 3. Shell Completion (Zsh)

Tab-completes commands, subcommands, and AWS profile names.

**Plain zsh** (add to `~/.zshrc`):
```zsh
fpath=(/path/to/awx/completions $fpath)
autoload -Uz compinit && compinit
```

**Oh My Zsh:**
```zsh
mkdir -p ~/.oh-my-zsh/completions
cp completions/_awx ~/.oh-my-zsh/completions/
# Restart your shell or run: exec zsh
```

## Testing and Quality

This project uses automated tests and pre-commit hooks that run in CI to ensure code quality and correct behavior.
**All contributors should run both locally before pushing or submitting a pull request.**

A `Makefile` provides a single, discoverable interface for the most common development workflows:

| Command        | Description                              |
|----------------|------------------------------------------|
| `make help`    | List all available targets               |
| `make test`    | Run all bats tests                       |
| `make lint`    | Run pre-commit hooks on all files        |
| `make check`   | Run tests **and** lint                   |
| `make install` | Symlink `awx` to `~/.local/bin`          |
| `make dev`     | Check development dependency status      |
| `make clean`   | Remove pre-commit cache and temp files   |

### 1. Automated Tests (bats)
- The main suite is written in `bats-core`. To use:

  **On macOS:**
  ```bash
  brew install bats-core
  ```

  **On Linux/other platforms (manual install):**
  ```bash
  curl -fsSL https://github.com/bats-core/bats-core/archive/refs/heads/master.zip -o bats.zip
  unzip bats.zip && cd bats-core-master && ./install.sh ~/bats-local && cd ..
  rm -rf bats.zip bats-core-master
  export PATH=$HOME/bats-local/bin:$PATH
  ```

- To run all tests via Make:
  ```bash
  make test
  ```
- Or run bats directly:
  ```bash
  bats tests
  ```
- Run an individual test file:
  ```bash
  bats tests/whoami.bats
  ```

Sample bats output:
```text
1..4
ok 1 awx whoami with valid AWS_PROFILE
not ok 2 awx whoami with missing AWS_PROFILE
...
```

### 2. Pre-commit Hooks
Automated quality checks, formatting, and linting are enforced by [pre-commit](https://pre-commit.com/).

- To run pre-commit hooks via Make:
  ```sh
  make lint
  ```
- Or run pre-commit directly:
  ```sh
  pre-commit run --all-files
  ```
- These hooks run automatically on commit/pull request via GitHub Actions. **You must pass these checks for your contributions to be accepted.**

**Best practice: Always run `make check` before committing or opening a PR.**

## Tips & Behavior
- If required tools (`aws`, `fzf`, or `jq`) are missing, `awx` will tell you exactly what to install.
- `kubectl` is an optional but recommended dependency. When present, `awx` skips `aws eks update-kubeconfig` if the target context (named after the profile) already exists in your kubeconfig, and instead calls `kubectl config use-context` directly — significantly reducing latency on repeated calls. Without `kubectl`, a full `aws eks update-kubeconfig` is always run.
- `kubeconfig` is updated *per profile*; back up your old file if you need persistent custom setups.
- Make sure your AWS SSO setup is complete before using `awx use` for the first time.
- Defaults to region from `AWS_REGION`, falling back to `eu-central-1` if unset.
- EKS cluster results are cached per profile under `$XDG_CACHE_HOME/awx/` (falls back to `~/.cache/awx/`). The default TTL is 8 hours (480 minutes) and can be overridden with `AWX_CACHE_TTL=<minutes>`.

## Contributing
Contributions, issues, and PRs are welcome!

To develop locally:
1. Fork & clone.
2. Install dependencies (see above).
3. Run `make dev` to verify your local toolchain.
4. Make changes on a new branch.
5. Run `make check` before opening a PR (runs tests and lint together).
