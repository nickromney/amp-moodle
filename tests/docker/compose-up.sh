#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

# shellcheck source=tests/docker/lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=tests/docker/tls-preflight.sh
source "${SCRIPT_DIR}/tls-preflight.sh"

docker_require
docker_require_tools python3 curl openssl

cd "${PROJECT_ROOT}"

AMP_DOCKER_BIND_HOST="${AMP_DOCKER_BIND_HOST:-127.0.0.1}"
SITE_HOST="${MOODLE_SITE_HOST:-moodle.test.127.0.0.1.sslip.io}"
EXISTING_HTTP_PORT=""
EXISTING_HTTPS_PORT=""

if [[ -n "$(${COMPOSE_CMD} ps -q --status running moodle-test-debian 2>/dev/null || true)" ]]; then
  EXISTING_HTTP_PORT="$(docker_published_host_port "$(${COMPOSE_CMD} port moodle-test-debian 80 2>/dev/null || true)" || true)"
  EXISTING_HTTPS_PORT="$(docker_published_host_port "$(${COMPOSE_CMD} port moodle-test-debian 8443 2>/dev/null || true)" || true)"
fi

if [[ -n "${EXISTING_HTTP_PORT}" ]]; then
  AMP_DOCKER_HTTP_PORT="${EXISTING_HTTP_PORT}"
else
  AMP_DOCKER_HTTP_PORT="$(docker_allocate_host_port "${AMP_DOCKER_BIND_HOST}" "${AMP_DOCKER_HTTP_PORT:-8080}")"
fi

if [[ -n "${EXISTING_HTTPS_PORT}" ]]; then
  AMP_DOCKER_HTTPS_PORT="${EXISTING_HTTPS_PORT}"
else
  AMP_DOCKER_HTTPS_PORT="$(docker_allocate_host_port "${AMP_DOCKER_BIND_HOST}" "${AMP_DOCKER_HTTPS_PORT:-8443}" "${AMP_DOCKER_HTTP_PORT}")"
fi

export AMP_DOCKER_BIND_HOST AMP_DOCKER_HTTP_PORT AMP_DOCKER_HTTPS_PORT

SITE_URL="https://${SITE_HOST}:${AMP_DOCKER_HTTPS_PORT}"

${COMPOSE_CMD} up -d postgres-db moodle-test-debian

echo "Waiting for ${SITE_URL} ..."
tls_preflight_wait_for_https "${SITE_URL}" "${TLS_PREFLIGHT_WAIT_ATTEMPTS:-1800}"
tls_preflight_check_url "${SITE_URL}"

echo "Publishing Moodle on ${SITE_URL}"
if [[ "${AMP_DOCKER_HTTPS_PORT}" != "443" ]]; then
  echo "Port 443 is not this stack; https://${SITE_HOST} will hit whatever already owns ${AMP_DOCKER_BIND_HOST}:443." >&2
fi
