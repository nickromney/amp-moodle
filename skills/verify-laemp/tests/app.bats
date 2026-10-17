#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # Bats isolates each test case in a subshell.

setup() {
  APP_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  CONTROL="$APP_ROOT/skills/verify-laemp/scripts/control.sh"
}

@test "copied CLI help works without starting installer code" {
  export VERIFY_RUN_ID="help-test-${BATS_TEST_NUMBER}"
  export VERIFY_BASE_DIR="$BATS_TEST_TMPDIR/state"
  export VERIFY_EVIDENCE_ROOT="$BATS_TEST_TMPDIR/evidence"

  run /bin/bash "$CONTROL" --execute help
  [ "$status" -eq 0 ]
  [ -f "$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/help.txt" ]
  [ ! -e "$VERIFY_BASE_DIR/$VERIFY_RUN_ID/state" ]
  grep -q -- "Usage:" "$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/help.txt"
}

@test "installer verify blocks before LAEMP code on an unsupported host" {
  export VERIFY_RUN_ID="host-test-${BATS_TEST_NUMBER}"
  export VERIFY_BASE_DIR="$BATS_TEST_TMPDIR/state"
  export VERIFY_EVIDENCE_ROOT="$BATS_TEST_TMPDIR/evidence"

  if [ "$(uname -s)" = "Linux" ] && grep -Eq '^ID=(ubuntu|debian)$' /etc/os-release; then
    skip "supported Ubuntu/Debian host; the root executor owns installer execution"
  fi
  run /bin/bash "$CONTROL" --execute verify
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCKED"* ]]
  [ -f "$VERIFY_EVIDENCE_ROOT/$VERIFY_RUN_ID/blocker.txt" ]
  [ ! -e "$VERIFY_BASE_DIR/$VERIFY_RUN_ID/state/source/laemp.sh" ]
}
