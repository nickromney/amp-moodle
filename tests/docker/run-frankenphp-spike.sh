#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=tests/docker/lib.sh
source "${SCRIPT_DIR}/lib.sh"

RESULTS_DIR=""
KEEP_RESOURCES=false
REBUILD_IMAGE=false
APP_PORT="${APP_PORT:-18480}"

IMAGE_TAG="amp-moodle-frankenphp:php8.4-moodle5013"
DB_IMAGE="mariadb:11.8"
NETWORK_NAME="amp-moodle-frankenphp-net"
DB_CONTAINER="amp-moodle-frankenphp-db"
APP_CONTAINER="amp-moodle-frankenphp-app"
ROOT_PASSWORD="rootpass"
DB_NAME="moodle"
DB_USER="moodle"
DB_PASSWORD="moodlepass"
ADMIN_PASSWORD="Adminpass123!"
ADMIN_EMAIL="demo@moodle.test"
SITE_URL="http://localhost:${APP_PORT}"

function usage() {
  cat <<EOF
Build and verify the experimental FrankenPHP + Moodle container path.

Usage:
  tests/docker/run-frankenphp-spike.sh [options]

Options:
  --results-dir DIR     Write logs and results to DIR
  --keep-resources      Keep containers and network after the run
  --rebuild-image       Force a Docker rebuild of the FrankenPHP image
  --port PORT           Publish the app container on PORT (default: ${APP_PORT})
  -h, --help            Show this help text
EOF
}

function cleanup_resources() {
  if [[ "${KEEP_RESOURCES}" == "true" ]]; then
    return 0
  fi

  docker_cleanup_container "${APP_CONTAINER}"
  docker_cleanup_container "${DB_CONTAINER}"
  "${DOCKER_CMD}" network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
}

function wait_for_mariadb() {
  local attempts=60
  while (( attempts > 0 )); do
    if "${DOCKER_CMD}" exec "${DB_CONTAINER}" mariadb-admin ping -h127.0.0.1 -uroot "-p${ROOT_PASSWORD}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 1
  done

  echo "Error: MariaDB did not become ready in time." >&2
  return 1
}

function wait_for_http() {
  local attempts=60
  while (( attempts > 0 )); do
    if curl -fsSI "${SITE_URL}" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep 1
  done

  echo "Error: FrankenPHP did not start serving ${SITE_URL} in time." >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir)
      RESULTS_DIR="${2:?missing value for --results-dir}"
      shift 2
      ;;
    --keep-resources)
      KEEP_RESOURCES=true
      shift
      ;;
    --rebuild-image)
      REBUILD_IMAGE=true
      shift
      ;;
    --port)
      APP_PORT="${2:?missing value for --port}"
      SITE_URL="http://localhost:${APP_PORT}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
done

docker_require
docker_require_tools awk curl date mktemp sed

if [[ -z "${RESULTS_DIR}" ]]; then
  RESULTS_DIR="$(mktemp -d "/tmp/amp-moodle-frankenphp-$(date +%Y%m%d-%H%M%S)-XXXX")"
else
  mkdir -p "${RESULTS_DIR}"
fi

trap cleanup_resources EXIT

RESULTS_TSV="${RESULTS_DIR}/results.tsv"
printf 'status\turl\ttable_count\tartifacts\n' >"${RESULTS_TSV}"

BUILD_LOG="${RESULTS_DIR}/build.log"
DB_LOG="${RESULTS_DIR}/mariadb.log"
APP_LOG="${RESULTS_DIR}/frankenphp.log"
INSTALL_LOG="${RESULTS_DIR}/install.log"
HTTP_HEAD_LOG="${RESULTS_DIR}/http_head.txt"
LOGIN_SNIPPET="${RESULTS_DIR}/login_snippet.html"
DB_SETUP_LOG="${RESULTS_DIR}/database_setup.txt"
PHP_SETTINGS_LOG="${RESULTS_DIR}/php_settings.txt"
status="FAIL"
table_count="0"

docker_cleanup_container "${APP_CONTAINER}"
docker_cleanup_container "${DB_CONTAINER}"
"${DOCKER_CMD}" network rm "${NETWORK_NAME}" >/dev/null 2>&1 || true
"${DOCKER_CMD}" network create "${NETWORK_NAME}" >/dev/null

if [[ "${REBUILD_IMAGE}" == "true" ]] || ! docker_image_exists "${IMAGE_TAG}"; then
  "${DOCKER_CMD}" build \
    -f "${SCRIPT_DIR}/frankenphp/Dockerfile" \
    -t "${IMAGE_TAG}" \
    "${PROJECT_ROOT}" 2>&1 | tee "${BUILD_LOG}"
else
  printf 'Reusing existing image %s\n' "${IMAGE_TAG}" | tee "${BUILD_LOG}"
fi

"${DOCKER_CMD}" run -d \
  --name "${DB_CONTAINER}" \
  --network "${NETWORK_NAME}" \
  -e MARIADB_ROOT_PASSWORD="${ROOT_PASSWORD}" \
  "${DB_IMAGE}" >/dev/null

wait_for_mariadb

"${DOCKER_CMD}" exec "${DB_CONTAINER}" sh -lc \
  "mariadb -uroot -p${ROOT_PASSWORD} <<'SQL'
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SHOW CREATE DATABASE ${DB_NAME}\\G
SQL" | tee "${DB_SETUP_LOG}"

"${DOCKER_CMD}" run -d \
  --name "${APP_CONTAINER}" \
  --network "${NETWORK_NAME}" \
  -e SERVER_NAME=:80 \
  -p "${APP_PORT}:80" \
  "${IMAGE_TAG}" >/dev/null

wait_for_http

"${DOCKER_CMD}" exec "${APP_CONTAINER}" sh -lc \
  "php -i | sed -n '/^max_input_vars =>/p;/^memory_limit =>/p'" | tee "${PHP_SETTINGS_LOG}"

if "${DOCKER_CMD}" exec "${APP_CONTAINER}" sh -lc \
  "php admin/cli/install.php \
    --lang=en \
    --wwwroot=${SITE_URL} \
    --dataroot=/app/moodledata \
    --dbtype=mariadb \
    --dbhost=${DB_CONTAINER} \
    --dbname=${DB_NAME} \
    --dbuser=${DB_USER} \
    --dbpass=${DB_PASSWORD} \
    --fullname='Moodle' \
    --shortname='Moodle' \
    --adminuser=admin \
    --adminpass='${ADMIN_PASSWORD}' \
    --adminemail='${ADMIN_EMAIL}' \
    --non-interactive \
    --agree-license" 2>&1 | tee "${INSTALL_LOG}"; then
  curl -fsSI "${SITE_URL}" | tee "${HTTP_HEAD_LOG}"
  curl -fsSL "${SITE_URL}/login/index.php" | sed -n '1,40p' | tee "${LOGIN_SNIPPET}"
  table_count=$(
    "${DOCKER_CMD}" exec "${DB_CONTAINER}" sh -lc \
      "mariadb -u${DB_USER} -p${DB_PASSWORD} ${DB_NAME} -Nse \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '${DB_NAME}' AND table_name LIKE 'mdl_%';\""
  )

  if [[ -n "${table_count}" ]] && [[ "${table_count}" -ge 400 ]] && grep -q '200 OK' "${HTTP_HEAD_LOG}" && grep -q 'Log in to the site' "${LOGIN_SNIPPET}"; then
    status="PASS"
  fi
fi

"${DOCKER_CMD}" logs "${DB_CONTAINER}" >"${DB_LOG}" 2>&1 || true
"${DOCKER_CMD}" logs "${APP_CONTAINER}" >"${APP_LOG}" 2>&1 || true

printf '%s\t%s\t%s\t%s\n' "${status}" "${SITE_URL}" "${table_count}" "${RESULTS_DIR}" >>"${RESULTS_TSV}"

cat "${RESULTS_TSV}"

if [[ "${status}" != "PASS" ]]; then
  echo "FrankenPHP spike failed. Artifacts: ${RESULTS_DIR}" >&2
  exit 1
fi

echo "FrankenPHP spike passed. Artifacts: ${RESULTS_DIR}"
