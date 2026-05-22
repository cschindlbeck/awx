.PHONY: help test lint check install uninstall dev clean

INSTALL_DIR ?= $(HOME)/.local/bin
SCRIPT      := awx
SCRIPT_PATH := $(abspath $(SCRIPT))

help: ## List all available targets with descriptions
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*## "}; {printf "  make %-12s %s\n", $$1, $$2}'

test: ## Run all bats tests
	bats tests/

lint: ## Run pre-commit hooks on all files
	pre-commit run --all-files

check: test lint ## Run tests and lint

install: ## Install awx into $(INSTALL_DIR)
	@test -f "$(SCRIPT)" || { echo "ERROR: $(SCRIPT) not found"; exit 1; }
	chmod +x "$(SCRIPT)"
	mkdir -p "$(INSTALL_DIR)"
	ln -sf "$(SCRIPT_PATH)" "$(INSTALL_DIR)/$(SCRIPT)"

	@echo ""
	@echo "Installed:"
	@echo "  $(INSTALL_DIR)/$(SCRIPT) -> $(SCRIPT_PATH)"

	@if echo "$$PATH" | tr ':' '\n' | grep -Fxq "$(INSTALL_DIR)"; then \
		echo ""; \
		echo "PATH check: OK"; \
	else \
		echo ""; \
		echo "WARNING: $(INSTALL_DIR) is not in your PATH"; \
		echo ""; \
		echo "Add this to your shell config (~/.zshrc or ~/.bashrc):"; \
		echo '  export PATH="$(INSTALL_DIR):$$PATH"'; \
	fi

	@shell_config=""; \
	if [ -f "$(HOME)/.zshrc" ]; then \
		shell_config="$(HOME)/.zshrc"; \
	elif [ -f "$(HOME)/.bashrc" ]; then \
		shell_config="$(HOME)/.bashrc"; \
	fi; \
	if [ -n "$$shell_config" ]; then \
		if grep -qF 'source "$(INSTALL_DIR)/$(SCRIPT)"' "$$shell_config" || grep -qF "source $(INSTALL_DIR)/$(SCRIPT)" "$$shell_config"; then \
			echo ""; \
			echo "Shell integration: OK (source line detected in $$shell_config)"; \
		else \
			echo ""; \
			echo "REQUIRED: awx must be sourced to set AWS_PROFILE in your shell."; \
			echo ""; \
			echo "Add this line to $$shell_config:"; \
			echo ""; \
			echo '  source "$(INSTALL_DIR)/$(SCRIPT)"'; \
			echo ""; \
			echo "Then reload your shell:"; \
			echo ""; \
			echo "  source $$shell_config"; \
		fi; \
	fi

uninstall: ## Remove installed symlink
	rm -f "$(INSTALL_DIR)/$(SCRIPT)"
	@echo "Removed: $(INSTALL_DIR)/$(SCRIPT)"

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
