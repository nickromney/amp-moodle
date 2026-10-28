#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME" && pwd)"
  IMAGE='dunglas/frankenphp:1.13.2-php8.4.27-bookworm@sha256:49369ff211d81dc30a15890d58c0651d639aef0d9c0a9b91bcc6f387a77bd7a2'
}

@test "spike Dockerfile has one reviewed FrankenPHP base" {
  stages="$(awk 'toupper($1) == "FROM" { print }' "$ROOT/tests/docker/frankenphp/Dockerfile")"
  [ "$stages" = "FROM $IMAGE" ]
}

@test "spike builds from the reviewed Dockerfile even when an image is cached" {
  cat > "$BATS_TEST_TMPDIR/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
if [ "$1" = build ]; then exit 7; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/docker"
  run env DOCKER_CMD="$BATS_TEST_TMPDIR/docker" DOCKER_CALLS="$BATS_TEST_TMPDIR/calls" \
    /bin/bash "$ROOT/tests/docker/run-frankenphp-spike.sh" --results-dir "$BATS_TEST_TMPDIR/results"
  [ "$status" -ne 0 ]
  run grep -F "build -f $ROOT/tests/docker/frankenphp/Dockerfile -t amp-moodle-frankenphp:php8.4-moodle5022 $ROOT" "$BATS_TEST_TMPDIR/calls"
  [ "$status" -eq 0 ]
  run grep -E '^run ' "$BATS_TEST_TMPDIR/calls"
  [ "$status" -eq 1 ]
}
