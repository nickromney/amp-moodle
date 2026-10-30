#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/project"
  awk '/^function moodle_composer_install\(\)/,/^}/' "$ROOT/laemp.sh" > "$BATS_TEST_TMPDIR/functions.sh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CALL_LOG="$BATS_TEST_TMPDIR/calls.log"
  export COMPOSER_MARKER="$BATS_TEST_TMPDIR/composer-installed"
  export TMPDIR="$BATS_TEST_TMPDIR"
  : > "$CALL_LOG"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/bin/bash
set -eu
[[ "$1" == -fsSLo ]]
out="$2"
url="$3"
printf 'curl %s\n' "$url" >> "$CALL_LOG"
case "$url" in
  https://getcomposer.org/installer)
    [[ "${MOCK_INSTALLER_FAIL:-false}" == false ]] || exit 22
    printf 'fixture composer installer\n' > "$out"
    ;;
  https://composer.github.io/installer.sig)
    [[ "${MOCK_SIGNATURE_FAIL:-false}" == false ]] || exit 22
    printf '%s' "$MOCK_SIGNATURE" > "$out"
    ;;
  *) exit 64 ;;
esac
SH
  cat > "$BATS_TEST_TMPDIR/bin/php" <<'SH'
#!/bin/bash
printf 'php %s\n' "$*" >> "$CALL_LOG"
touch "$COMPOSER_MARKER"
SH
  cat > "$BATS_TEST_TMPDIR/bin/composer" <<'SH'
#!/bin/bash
printf 'composer %s\n' "$*" >> "$CALL_LOG"
SH
  cat > "$BATS_TEST_TMPDIR/bin/sha384sum" <<'SH'
#!/bin/bash
[[ "$1" == --check && "$2" == --status ]]
exec shasum -a 384 -c
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export MOCK_SIGNATURE="$(printf 'fixture composer installer\n' | shasum -a 384 | awk '{print $1}')"
  source "$BATS_TEST_TMPDIR/functions.sh"
  log() { :; }
  tool_exists() { [[ "$1" == composer && -f "$COMPOSER_MARKER" ]]; }
  run_command() {
    if [[ "${1:-}" == --makes-changes ]]; then shift; if [[ "${DRY_RUN_CHANGES:-false}" == true ]]; then return 0; fi; fi
    "$@"
  }
}

@test "valid signature permits Composer installer and removes private temp directory" {
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 0 ]
  grep -q '^php /' "$CALL_LOG"
  grep -q '^composer install ' "$CALL_LOG"
  [ -f "$COMPOSER_MARKER" ]
  [ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'composer-installer.*' -print -quit)" ]
}

@test "wrong digest blocks PHP invocation and cleans temporary files" {
  export MOCK_SIGNATURE="$(printf '%096d' 0)"
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 1 ]
  ! grep -q '^php ' "$CALL_LOG"
  ! grep -q '^composer ' "$CALL_LOG"
  [ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'composer-installer.*' -print -quit)" ]
}

@test "malformed signature blocks PHP invocation" {
  export MOCK_SIGNATURE='not-a-sha384-signature'
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 1 ]
  ! grep -q '^php ' "$CALL_LOG"
  ! grep -q '^composer ' "$CALL_LOG"
}

@test "missing signature response blocks PHP invocation and cleans temporary files" {
  export MOCK_SIGNATURE_FAIL=true
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 1 ]
  ! grep -q '^php ' "$CALL_LOG"
  [ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'composer-installer.*' -print -quit)" ]
}

@test "installer download failure blocks PHP invocation and cleans temporary files" {
  export MOCK_INSTALLER_FAIL=true
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 1 ]
  ! grep -q '^php ' "$CALL_LOG"
  [ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'composer-installer.*' -print -quit)" ]
}

@test "dry run performs no download or install and creates no temporary directory" {
  export DRY_RUN_CHANGES=true
  run moodle_composer_install "$BATS_TEST_TMPDIR/project"
  [ "$status" -eq 0 ]
  ! grep -q '^curl ' "$CALL_LOG"
  ! grep -q '^php ' "$CALL_LOG"
  ! grep -q '^composer ' "$CALL_LOG"
  [ -z "$(find "$TMPDIR" -maxdepth 1 -type d -name 'composer-installer.*' -print -quit)" ]
}
