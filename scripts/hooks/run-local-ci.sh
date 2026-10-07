#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

hook_parse_execute_flag "$@"

if hook_skip_requested; then
  hook_fail "skip_requested: verification did not execute"
  exit 1
fi

if [[ "${AMP_MOODLE_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_fail "recursive_gate: verification did not execute"
  exit 1
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
amp-moodle pre-push local CI gate

Running:
  shellcheck -x on tracked shell scripts
  uv run --locked make test-smoke-bats
  uv run --locked make test-cli-bats

Full acceptance requires every configured check.
Explicit skip and recursive execution requests refuse verification.
EOF

export AMP_MOODLE_LOCAL_CI_IN_PROGRESS=1
failed_gate=""
shell_files=()

while IFS= read -r file; do
  shell_files+=("${file}")
done < <(git ls-files '*.sh')

if ! command -v shellcheck >/dev/null 2>&1; then
  failed_gate="shellcheck not found"
elif ! shellcheck -x "${shell_files[@]}"; then
  failed_gate="shellcheck -x on tracked shell scripts"
elif ! uv run --locked make test-smoke-bats; then
  failed_gate="uv run --locked make test-smoke-bats"
elif ! uv run --locked make test-cli-bats; then
  failed_gate="uv run --locked make test-cli-bats"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed"
