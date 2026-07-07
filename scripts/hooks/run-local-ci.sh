#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/hooks/lib.sh
source "${SCRIPT_DIR}/lib.sh"

hook_parse_execute_flag "$@"

if hook_skip_requested; then
  hook_print_skip_and_exit
fi

if [[ "${AMP_MOODLE_LOCAL_CI_IN_PROGRESS:-}" == "1" ]]; then
  hook_warn "AMP_MOODLE_LOCAL_CI_IN_PROGRESS=1; skipping run-local-ci.sh to avoid recursive local CI"
  exit 0
fi

cd "${HOOKS_REPO_ROOT}"

cat <<'EOF'
amp-moodle pre-push local CI gate

Running:
  shellcheck -x on tracked shell scripts
  make test-smoke-bats
  make test-cli-bats

Skip only when you have a reason:
  LEFTHOOK=0 git push
  AMP_MOODLE_SKIP_HOOKS=1 git push
  git push --no-verify
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
elif ! make test-smoke-bats; then
  failed_gate="make test-smoke-bats"
elif ! make test-cli-bats; then
  failed_gate="make test-cli-bats"
fi

if [[ -n "${failed_gate}" ]]; then
  hook_fail "pre-push gate failed: ${failed_gate}"
  exit 1
fi

hook_ok "pre-push gate passed"
