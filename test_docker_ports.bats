#!/usr/bin/env bats

setup() {
  # shellcheck source=tests/docker/lib.sh
  source ./tests/docker/lib.sh
  BUSY_PORT=""
  SERVER_PID=""
}

teardown() {
  if [[ -n "${SERVER_PID}" ]]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
}

@test "docker_allocate_host_port skips a busy loopback port" {
  if ! command -v python3 >/dev/null 2>&1; then
    skip "python3 is required"
  fi

  BUSY_PORT="$((21000 + (RANDOM % 1000)))"
  python3 -m http.server "${BUSY_PORT}" --bind 127.0.0.1 >/dev/null 2>&1 &
  SERVER_PID=$!
  sleep 0.3

  allocated="$(docker_allocate_host_port 127.0.0.1 "${BUSY_PORT}" 2>/dev/null)"

  [[ "${allocated}" =~ ^[0-9]+$ ]]
  [ "${allocated}" != "${BUSY_PORT}" ]
}

@test "docker_published_host_port extracts the host port from a compose mapping" {
  run docker_published_host_port "127.0.0.1:10443"
  [ "${status}" -eq 0 ]
  [ "${output}" = "10443" ]

  run docker_published_host_port ""
  [ "${status}" -eq 1 ]
}
