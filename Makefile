.PHONY: help test lint check install dev clean

INSTALL_DIR ?= $(HOME)/.local/bin
SCRIPT      := awx

help: ## List all available targets with descriptions
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*## "}; {printf "  make %-10s - %s\n", $$1, $$2}'

test: ## Run all bats tests
	bats tests/

lint: ## Run pre-commit hooks on all files
	pre-commit run --all-files

check: test lint ## Run tests and lint

install: ## Install (symlink) the awx script to $(INSTALL_DIR)
	chmod +x $(SCRIPT)
	mkdir -p $(INSTALL_DIR)
	ln -sf "$(PWD)/$(SCRIPT)" "$(INSTALL_DIR)/$(SCRIPT)"
	@echo "Installed: $(INSTALL_DIR)/$(SCRIPT) -> $(PWD)/$(SCRIPT)"

dev: ## Set up local development environment
	@echo "Checking development dependencies..."
	@command -v bats >/dev/null 2>&1 \
		&& echo "  [ok] bats" \
		|| echo "  [missing] bats  -> install bats-core: https://github.com/bats-core/bats-core"
	@command -v pre-commit >/dev/null 2>&1 \
		&& echo "  [ok] pre-commit" \
		|| echo "  [missing] pre-commit -> install: https://pre-commit.com/#install"
	@command -v aws >/dev/null 2>&1 \
		&& echo "  [ok] aws" \
		|| echo "  [missing] aws -> install: https://aws.amazon.com/cli/"
	@command -v fzf >/dev/null 2>&1 \
		&& echo "  [ok] fzf" \
		|| echo "  [missing] fzf -> install: https://github.com/junegunn/fzf"
	@command -v jq >/dev/null 2>&1 \
		&& echo "  [ok] jq" \
		|| echo "  [missing] jq -> install: https://jqlang.org/"
	@echo "Done. Install any [missing] tools listed above before contributing."

clean: ## Remove pre-commit cache and temporary files
	@pre-commit clean 2>/dev/null || true
	@find . -name '*.tmp' -delete 2>/dev/null || true
	@echo "Clean complete."
