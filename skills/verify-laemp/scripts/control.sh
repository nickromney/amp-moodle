#!/usr/bin/env bash
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="laemp"
VK_DESCRIPTION="Exercise LAEMP's real CLI help and unsupported-database refusal without provisioning a host."
VK_DEFAULT_BASE_DIR="${TMPDIR:-/tmp}/verify-laemp-state"
VK_DEFAULT_EVIDENCE_ROOT="${TMPDIR:-/tmp}/verify-laemp-evidence"
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

vk_commands_help() {
  cat <<'HELP'
  launch    verify actual host support before preparing the LAEMP CLI
  doctor    run the copied CLI help path and retain its output
  help      run the safe CLI help path from a temporary copy
  cleanup   remove only this run's source state; retain evidence
HELP
}
vk_sample_commands() { printf '%s\n' verify launch doctor help cleanup; }
vk_paths() {
  case "$VK_RUN_ID" in
    ''|*[!A-Za-z0-9_-]*) vk_err "VERIFY_RUN_ID may contain only letters, digits, underscore, and hyphen"; return 2 ;;
  esac
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
  APP_COPY="$STATE/source/laemp.sh"
}

vk_plan() {
  case "$1" in
    verify) vk_plan_line "check actual Ubuntu/Debian support before starting installer code; on supported hosts execute --help and unsupported database refusal in an isolated copy" ;;
    launch) vk_plan_line "check actual host support before preparing the isolated CLI under $STATE" ;;
    doctor) vk_plan_line "execute the copied LAEMP --help path and capture its output at $EVIDENCE/help.txt" ;;
    help) vk_plan_line "copy current laemp.sh to temporary state and run only its --help path; retain output under $EVIDENCE" ;;
    cleanup) vk_plan_line "remove $STATE and preserve evidence at $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

cmd_launch() {
  mkdir -p "$STATE" "$EVIDENCE"
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"
  if ! /bin/bash "$VK_SKILL_DIR/scripts/preflight.sh" > "$EVIDENCE/preflight.log" 2>&1; then
    cat "$EVIDENCE/preflight.log" >&2
    cp "$EVIDENCE/preflight.log" "$EVIDENCE/blocker.txt"
    vk_fail "LAEMP host preflight blocked this installer run; see $EVIDENCE/blocker.txt"
    return 1
  fi
  mkdir -p "$(dirname "$APP_COPY")"
  cp "$VK_ROOT/laemp.sh" "$APP_COPY"
  vk_say "ready run=$VK_RUN_ID isolated_cli=$APP_COPY evidence=$EVIDENCE"
}

cmd_doctor() {
  [ -f "$APP_COPY" ] || { vk_fail "isolated LAEMP source is missing; launch first"; return 1; }
  bash "$APP_COPY" --help > "$EVIDENCE/help.txt" 2>&1 || {
    vk_fail "LAEMP --help failed; see $EVIDENCE/help.txt"
    return 1
  }
  vk_expect_contains "$EVIDENCE/help.txt" "Usage:"
  vk_expect_contains "$EVIDENCE/help.txt" "--moodle"
  vk_say "LAEMP help path passed; output retained at $EVIDENCE/help.txt"
}

cmd_help() {
  mkdir -p "$(dirname "$APP_COPY")" "$EVIDENCE"
  cp "$VK_ROOT/laemp.sh" "$APP_COPY"
  if ! bash "$APP_COPY" --help > "$EVIDENCE/help.txt" 2>&1; then
    rm -rf "${STATE:?}"
    rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
    vk_fail "LAEMP --help failed; see $EVIDENCE/help.txt"
    return 1
  fi
  vk_expect_contains "$EVIDENCE/help.txt" "Usage:"
  vk_expect_contains "$EVIDENCE/help.txt" "--moodle"
  rm -rf "${STATE:?}"
  rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  vk_say "LAEMP help path passed; evidence retained at $EVIDENCE/help.txt"
}

cmd_cleanup() {
  rm -rf "${STATE:?}"
  rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  vk_clear_current
  vk_say "removed run state; evidence retained at $EVIDENCE"
}

vk_verify_recipes() {
  local status
  if bash "$APP_COPY" -d verify-kit-invalid-database > "$EVIDENCE/invalid-database.txt" 2>&1; then
    vk_fail "unsupported database input unexpectedly succeeded"
    return 1
  else
    status=$?
  fi
  [ "$status" -eq 1 ] || { vk_fail "unsupported database input exited $status instead of 1"; return 1; }
  vk_expect_contains "$EVIDENCE/invalid-database.txt" "Unsupported database type: verify-kit-invalid-database"
  vk_expect_contains "$EVIDENCE/invalid-database.txt" "Usage:"
}

vk_dispatch() {
  local cmd="$1"
  shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    help) cmd_help ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}

vk_main "$@"
