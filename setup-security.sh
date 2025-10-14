#!/usr/bin/env bash
# Setup script for local security tooling
set -euo pipefail

echo "🔒 Setting up local security tooling..."
echo ""

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "⚠️  This script is designed for macOS. Adjust for your platform."
  exit 1
fi

# Install pre-commit
if ! command -v pre-commit &> /dev/null; then
  echo "→ Installing pre-commit..."
  brew install pre-commit
else
  echo "✓ pre-commit already installed"
fi

# Install gitleaks
if ! command -v gitleaks &> /dev/null; then
  echo "→ Installing gitleaks..."
  brew install gitleaks
else
  echo "✓ gitleaks already installed"
fi

# Install tflint
if ! command -v tflint &> /dev/null; then
  echo "→ Installing tflint..."
  brew install tflint
else
  echo "✓ tflint already installed"
fi

# Install tfsec
if ! command -v tfsec &> /dev/null; then
  echo "→ Installing tfsec..."
  brew install tfsec
else
  echo "✓ tfsec already installed"
fi

echo ""
echo "→ Installing pre-commit hooks..."
pre-commit install

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Test secret scanning:  gitleaks detect --verbose"
echo "  2. Run all pre-commit:    pre-commit run --all-files"
echo "  3. Check formatting:      make fmt-check"
echo "  4. Run linting:           make lint"
echo ""
echo "Pre-commit hooks will now run automatically on git commit."
