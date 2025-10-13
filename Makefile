# Root Makefile for public-cloud-experiments
# Provides common commands across all projects

# Colors
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Auto-detect projects
# Find Python projects (have pyproject.toml)
PYTHON_PROJECTS := $(shell find . -name "pyproject.toml" \
	-not -path "*/.*" \
	-not -path "*/node_modules/*" \
	-not -path "*/.venv/*" \
	-not -path "*/.terraform/*" \
	2>/dev/null | xargs -I {} dirname {})

# Find TypeScript projects (have tsconfig.json)
TYPESCRIPT_PROJECTS := $(shell find . -name "tsconfig.json" \
	-not -path "*/.*" \
	-not -path "*/node_modules/*" \
	-not -path "*/.terraform/*" \
	2>/dev/null | xargs -I {} dirname {})

# Find Terraform projects (have *.tf files)
TERRAFORM_PROJECTS := $(shell find . -name "*.tf" \
	-not -path "*/.*" \
	-not -path "*/.terraform/*" \
	-not -path "*/.terragrunt-cache/*" \
	2>/dev/null | xargs -I {} dirname {} | sort -u)

.DEFAULT_GOAL := help

##@ Help

.PHONY: help
help: ## Show this help message
	@echo "$(GREEN)Public Cloud Experiments - Common Commands$(NC)"
	@echo ""
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$|^##@.*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; /^##@/ {printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "Project-specific Makefiles:"
	@echo "  terraform/claranet-tfwrapper/Makefile"
	@echo "  terraform/terragrunt/Makefile"

.PHONY: show-projects
show-projects: ## Show all auto-detected projects
	@echo "$(GREEN)Auto-detected Projects$(NC)"
	@echo ""
	@echo "$(YELLOW)Python Projects ($(words $(PYTHON_PROJECTS)))$(NC)"
	@for dir in $(PYTHON_PROJECTS); do echo "  - $$dir"; done
	@echo ""
	@echo "$(YELLOW)TypeScript Projects ($(words $(TYPESCRIPT_PROJECTS)))$(NC)"
	@for dir in $(TYPESCRIPT_PROJECTS); do echo "  - $$dir"; done
	@echo ""
	@echo "$(YELLOW)Terraform Projects ($(words $(TERRAFORM_PROJECTS)))$(NC)"
	@for dir in $(TERRAFORM_PROJECTS); do echo "  - $$dir"; done | head -10
	@if [ $(words $(TERRAFORM_PROJECTS)) -gt 10 ]; then \
		echo "  ... and $(shell expr $(words $(TERRAFORM_PROJECTS)) - 10) more"; \
	fi

##@ Pre-commit and Security

.PHONY: precommit
precommit: python-fmt python-lint python-test typescript-check typescript-lint ## Run formatting, linting, testing, and pre-commit hooks
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@echo "$(YELLOW)Note: This runs on ALL files. Git commit hook runs on staged files only.$(NC)"
	@pre-commit run --all-files
	@echo "$(YELLOW)Checking untracked markdown files for emojis...$(NC)"
	@git ls-files --others --exclude-standard '*.md' '*.markdown' | xargs -r .git-hooks/check-emojis.sh || true
	@echo "$(GREEN)✓ All pre-commit checks passed$(NC)"

.PHONY: precommit-check
precommit-check: ## Run pre-commit hooks (always succeeds, for review)
	@echo "$(YELLOW)Running all pre-commit hooks...$(NC)"
	@pre-commit run --all-files || true

.PHONY: precommit-install
precommit-install: ## Install pre-commit hooks
	@echo "$(YELLOW)Installing pre-commit hooks...$(NC)"
	@pre-commit install
	@echo "$(GREEN)✓ Pre-commit hooks installed$(NC)"

.PHONY: security-setup
security-setup: ## Run security setup script (macOS)
	@./setup-security.sh

.PHONY: gitleaks
gitleaks: ## Run gitleaks secret scanner
	@echo "$(YELLOW)Scanning for secrets with gitleaks...$(NC)"
	@gitleaks detect --verbose

.PHONY: gitleaks-protect
gitleaks-protect: ## Run gitleaks on staged files (pre-commit check)
	@echo "$(YELLOW)Checking staged files for secrets...$(NC)"
	@gitleaks protect --staged --verbose

.PHONY: trivy-scan
trivy-scan: ## Scan all container images for vulnerabilities using Trivy (HIGH,CRITICAL)
	@echo "$(YELLOW)Scanning container images with Trivy...$(NC)"
	@mkdir -p $(HOME)/trivy-scans
	@for image in \
		subnet-calculator-api-fastapi-azure-function:latest \
		subnet-calculator-api-fastapi-container-app:latest \
		subnet-calculator-frontend-python-flask:latest \
		subnet-calculator-frontend-html-static:latest \
		subnet-calculator-frontend-typescript-vite:latest; do \
		echo "$(YELLOW)Scanning $$image...$(NC)"; \
		podman save -o $(HOME)/trivy-scans/image.tar localhost/$$image && \
		podman run --rm \
			-v $(HOME)/trivy-scans:/scans:ro \
			-v $(HOME)/.cache/trivy:/root/.cache/trivy \
			aquasec/trivy:latest image --input /scans/image.tar --severity HIGH,CRITICAL || exit 1; \
	done
	@rm -rf $(HOME)/trivy-scans
	@echo "$(GREEN)✓ All images scanned (no HIGH or CRITICAL vulnerabilities)$(NC)"

.PHONY: trivy-scan-all
trivy-scan-all: ## Scan all container images for vulnerabilities (all severities)
	@echo "$(YELLOW)Scanning container images with Trivy (all severities)...$(NC)"
	@mkdir -p $(HOME)/trivy-scans
	@for image in \
		subnet-calculator-api-fastapi-azure-function:latest \
		subnet-calculator-api-fastapi-container-app:latest \
		subnet-calculator-frontend-python-flask:latest \
		subnet-calculator-frontend-html-static:latest \
		subnet-calculator-frontend-typescript-vite:latest; do \
		echo "$(YELLOW)Scanning $$image...$(NC)"; \
		podman save -o $(HOME)/trivy-scans/image.tar localhost/$$image && \
		podman run --rm \
			-v $(HOME)/trivy-scans:/scans:ro \
			-v $(HOME)/.cache/trivy:/root/.cache/trivy \
			aquasec/trivy:latest image --input /scans/image.tar; \
	done
	@rm -rf $(HOME)/trivy-scans
	@echo "$(GREEN)✓ All images scanned$(NC)"

##@ Formatting and Cleaning

.PHONY: fmt
fmt: ## Format all code (Terraform, Python, etc.)
	@echo "$(YELLOW)Formatting all code...$(NC)"
	@if command -v tofu &>/dev/null; then \
		tofu fmt -recursive terraform/; \
	elif command -v terraform &>/dev/null; then \
		terraform fmt -recursive terraform/; \
	fi
	@if command -v uv &>/dev/null; then \
		for dir in $(PYTHON_PROJECTS); do \
			if [ -f "$$dir/pyproject.toml" ]; then \
				echo "$(YELLOW)Formatting $$dir...$(NC)"; \
				if (cd "$$dir" && uv run ruff --version >/dev/null 2>&1); then \
					(cd "$$dir" && uv run ruff format . 2>/dev/null) || true; \
				else \
					echo "$(YELLOW)  Skipping (no ruff installed)$(NC)"; \
				fi; \
			fi; \
		done; \
	fi
	@echo "$(GREEN)✓ Formatting complete$(NC)"

.PHONY: clean
clean: ## Clean all cached files (.terraform, __pycache__, etc.)
	@echo "$(YELLOW)Cleaning cached files...$(NC)"
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -name "*.pyc" -delete 2>/dev/null || true
	@find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".mypy_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@find . -name ".ruff_cache" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "$(GREEN)✓ Cleaned$(NC)"

.PHONY: clean-git
clean-git: ## Remove nested .git directories (dangerous - prompts first)
	@echo "$(YELLOW)Found nested .git directories:$(NC)"
	@find . -name ".git" -type d | grep -v "^\./.git$$" || echo "  None found"
	@echo ""
	@echo "$(YELLOW)WARNING: This will remove nested git repositories!$(NC)"
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		find . -name ".git" -type d | grep -v "^\./.git$$" | xargs rm -rf; \
		echo "$(GREEN)✓ Removed nested .git directories$(NC)"; \
	else \
		echo "Cancelled"; \
	fi

##@ Testing

.PHONY: test
test: python-test typescript-test ## Run all tests (Python + TypeScript)
	@echo "$(GREEN)✓ All tests passed (Python + TypeScript)$(NC)"

##@ Python Development

.PHONY: python-test
python-test: ## Run Python tests with pytest in all Python projects
	@echo "$(YELLOW)Running Python tests...$(NC)"
	@for dir in $(PYTHON_PROJECTS); do \
		if [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Testing $$dir...$(NC)"; \
			(cd "$$dir" && uv run pytest -v) || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ All tests passed$(NC)"

.PHONY: python-lint
python-lint: ## Run Python linting (ruff) in all Python projects
	@echo "$(YELLOW)Running Python linting...$(NC)"
	@for dir in $(PYTHON_PROJECTS); do \
		if [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Linting $$dir...$(NC)"; \
			(cd "$$dir" && uv sync --extra dev --quiet 2>/dev/null || uv sync --quiet) || exit 1; \
			if (cd "$$dir" && uv run ruff --version >/dev/null 2>&1); then \
				(cd "$$dir" && uv run ruff check .) || exit 1; \
			else \
				echo "$(YELLOW)  Skipping (no ruff installed)$(NC)"; \
			fi; \
		fi; \
	done

.PHONY: python-fmt
python-fmt: ## Format Python code with ruff
	@echo "$(YELLOW)Formatting Python code...$(NC)"
	@for dir in $(PYTHON_PROJECTS); do \
		if [ -f "$$dir/pyproject.toml" ]; then \
			echo "$(YELLOW)Formatting $$dir...$(NC)"; \
			(cd "$$dir" && uv sync --extra dev --quiet 2>/dev/null || uv sync --quiet) || exit 1; \
			if (cd "$$dir" && uv run ruff --version >/dev/null 2>&1); then \
				(cd "$$dir" && uv run ruff format .) || exit 1; \
				(cd "$$dir" && uv run ruff check --fix .) || exit 1; \
			else \
				echo "$(YELLOW)  Skipping (no ruff installed)$(NC)"; \
			fi; \
		fi; \
	done
	@echo "$(GREEN)✓ Python formatting complete$(NC)"

##@ TypeScript Development

.PHONY: typescript-check
typescript-check: ## Run TypeScript type checking
	@echo "$(YELLOW)Running TypeScript type checking...$(NC)"
	@for dir in $(TYPESCRIPT_PROJECTS); do \
		if [ -f "$$dir/package.json" ]; then \
			echo "$(YELLOW)Type checking $$dir...$(NC)"; \
			(cd "$$dir" && npm run type-check) || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ TypeScript type checking passed$(NC)"

.PHONY: typescript-lint
typescript-lint: ## Run Biome linting on TypeScript code
	@echo "$(YELLOW)Running Biome linting...$(NC)"
	@for dir in $(TYPESCRIPT_PROJECTS); do \
		if [ -f "$$dir/package.json" ]; then \
			echo "$(YELLOW)Linting $$dir...$(NC)"; \
			(cd "$$dir" && npm run lint) || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ Biome linting passed$(NC)"

.PHONY: typescript-test
typescript-test: ## Run Playwright tests
	@echo "$(YELLOW)Running Playwright tests...$(NC)"
	@for dir in $(TYPESCRIPT_PROJECTS); do \
		if [ -f "$$dir/package.json" ]; then \
			echo "$(YELLOW)Testing $$dir...$(NC)"; \
			(cd "$$dir" && npm test) || exit 1; \
		fi; \
	done
	@echo "$(GREEN)✓ Playwright tests passed$(NC)"
