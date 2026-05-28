#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=tests/docker/lib.sh
source "${SCRIPT_DIR}/lib.sh"

SUPPORTED_CASES=(
  "debian-stock-nginx-mariadb-m5013|debian|stock|8.4|nginx|mariadb|5013|"
  "debian-stock-apache-mariadb-m5013|debian|stock|8.4|apache|mariadb|5013|"
  "debian-stock-nginx-pgsql-m5013|debian|stock|8.4|nginx|pgsql|5013|"
  "debian-prereqs-nginx-mariadb-m5013|debian|prereqs|8.4|nginx|mariadb|5013|"
  "debian-stock-nginx-mariadb-m5013-memcached|debian|stock|8.4|nginx|mariadb|5013|-M"
  "debian-stock-nginx-mariadb-m5013-prometheus|debian|stock|8.4|nginx|mariadb|5013|-r"
)

RESULTS_DIR=""
KEEP_FAILED_CONTAINER=false
REBUILD_IMAGES=false
RUN_PLAYWRIGHT=false
PLAYWRIGHT_SPEC="tests/e2e/moodle.spec.ts"
LABEL_FILTER=""
DISTRO_FILTER=""
IMAGE_SET_FILTER=""
PHP_FILTER=""
WEB_FILTER=""
DB_FILTER=""
MOODLE_FILTER=""
INSTALL_TIMEOUT_SECONDS="${INSTALL_TIMEOUT_SECONDS:-1800}"
SITE_HOST="moodle.test.127.0.0.1.sslip.io"
SITE_DOMAIN="moodle.test"
ADMIN_EMAIL="demo@moodle.test"
BUILT_LAEMP_ARGS=()

function usage() {
  cat <<'EOF'
Run the Docker matrix for laemp.sh.

Usage:
  tests/docker/run-matrix.sh [options]

Options:
  --distro NAME             Filter to one distro (debian or ubuntu)
  --label NAME              Filter to one exact case label
  --image-set NAME          Filter to one image set (stock or prereqs)
  --php VERSION             Filter to one PHP version
  --web SERVER              Filter to one web server (apache or nginx)
  --database TYPE           Filter to one database (mariadb or pgsql)
  --moodle VERSION          Filter to one Moodle version
  --results-dir DIR         Write logs and TSV output to DIR
  --keep-failed-container   Do not delete failed containers
  --rebuild-images          Force image rebuilds before running
  --playwright              Run Playwright after direct sanity checks
  -h, --help                Show this help text

Examples:
  tests/docker/run-matrix.sh
  tests/docker/run-matrix.sh --web nginx --database mariadb
  tests/docker/run-matrix.sh --image-set prereqs --web nginx
EOF
}

function require_playwright() {
  docker_require_tools node npm npx
  if [[ ! -x "${PROJECT_ROOT}/node_modules/.bin/playwright" ]]; then
    echo "Error: Playwright dependencies are not installed." >&2
    echo "Run 'npm install' in ${PROJECT_ROOT} first." >&2
    exit 1
  fi
}

function case_matches_filters() {
  local label="$1"
  local distro="$2"
  local image_set="$3"
  local php_version="$4"
  local web_server="$5"
  local database="$6"
  local moodle_version="$7"

  [[ -z "${LABEL_FILTER}" || "${LABEL_FILTER}" == "${label}" ]] || return 1
  [[ -z "${DISTRO_FILTER}" || "${DISTRO_FILTER}" == "${distro}" ]] || return 1
  [[ -z "${IMAGE_SET_FILTER}" || "${IMAGE_SET_FILTER}" == "${image_set}" ]] || return 1
  [[ -z "${PHP_FILTER}" || "${PHP_FILTER}" == "${php_version}" ]] || return 1
  [[ -z "${WEB_FILTER}" || "${WEB_FILTER}" == "${web_server}" ]] || return 1
  [[ -z "${DB_FILTER}" || "${DB_FILTER}" == "${database}" ]] || return 1
  [[ -z "${MOODLE_FILTER}" || "${MOODLE_FILTER}" == "${moodle_version}" ]] || return 1
}

function build_laemp_args() {
  local image_set="$1"
  local php_version="$2"
  local web_server="$3"
  local database="$4"
  local moodle_version="$5"
  local extra_flags="$6"
  local -a args=(-c -w "${web_server}" -d "${database}" -m "${moodle_version}" -S)
  local -a extra_array=()

  if [[ "${image_set}" == "stock" ]]; then
    args=(-c -p "${php_version}" "${args[@]}")
  fi

  if [[ -n "${extra_flags}" ]]; then
    read -r -a extra_array <<<"${extra_flags}"
    args+=("${extra_array[@]}")
  fi

  BUILT_LAEMP_ARGS=("${args[@]}")
}

function extract_admin_password() {
  local install_log="$1"
  awk -F': ' '/Admin password:/ {print $NF; exit}' "${install_log}"
}

function verify_case() {
  local container_name="$1"
  local web_server="$2"
  local database="$3"
  local host_port="$4"
  local combo_dir="$5"
  local table_count=""

  docker_exec_root_shell "${container_name}" "test -f /var/www/html/${SITE_HOST}/config.php"
  docker_exec_root_shell "${container_name}" "curl -ksSfI https://127.0.0.1 | head -n 1" >"${combo_dir}/http_head_internal.txt"
  curl -ksSfI "https://${SITE_HOST}:${host_port}" | head -n 1 >"${combo_dir}/http_head_external.txt"

  if [[ "${web_server}" == "nginx" ]]; then
    docker_exec_root_shell "${container_name}" "pgrep -f '/usr/sbin/nginx' >/dev/null"
    docker_exec_root_shell "${container_name}" "pidof php-fpm8.4 >/dev/null 2>&1 || pidof php-fpm >/dev/null 2>&1"
  else
    docker_exec_root_shell "${container_name}" "pgrep -f 'apache2' >/dev/null"
  fi

  if [[ "${database}" == "pgsql" ]]; then
    docker_exec_root_shell "${container_name}" "service postgresql status >/dev/null 2>&1 || pidof postgres >/dev/null 2>&1"
    table_count=$(
      docker_exec_root_shell "${container_name}" \
        "sudo -u postgres psql -d moodle -Atc \"select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'mdl_%';\""
    )
  else
    docker_exec_root_shell "${container_name}" "pidof mariadbd >/dev/null 2>&1 || pidof mysqld >/dev/null 2>&1"
    table_count=$(
      docker_exec_root_shell "${container_name}" \
        "mysql -Nse \"select count(*) from information_schema.tables where table_schema = 'moodle' and table_name like 'mdl_%';\""
    )
  fi

  if [[ -z "${table_count}" || "${table_count}" -lt 400 ]]; then
    echo "Error: Moodle table count check failed (${table_count:-missing})." >&2
    return 1
  fi

  printf '%s\n' "${table_count}" >"${combo_dir}/table_count.txt"
}

function run_playwright() {
  local combo_dir="$1"
  local host_port="$2"
  local admin_password="$3"

  (
    cd "${PROJECT_ROOT}"
    MOODLE_URL="https://${SITE_HOST}:${host_port}" \
    MOODLE_ADMIN_USERNAME="admin" \
    MOODLE_ADMIN_PASSWORD="${admin_password}" \
    MOODLE_ADMIN_EMAIL="${ADMIN_EMAIL}" \
    MOODLE_SITE_NAME="${SITE_HOST}" \
    npx playwright test "${PLAYWRIGHT_SPEC}" \
      --reporter=list \
      --workers 1 \
      --output "${combo_dir}/playwright-output"
  ) 2>&1 | tee "${combo_dir}/playwright.log"
}

function cleanup_container() {
  local container_name="$1"
  local status="$2"

  if [[ "${status}" != "PASS" && "${KEEP_FAILED_CONTAINER}" == "true" ]]; then
    echo "Keeping failed container ${container_name} for inspection." >&2
    return 0
  fi

  docker_cleanup_container "${container_name}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      LABEL_FILTER="${2:?missing value for --label}"
      shift 2
      ;;
    --distro)
      DISTRO_FILTER="${2:?missing value for --distro}"
      shift 2
      ;;
    --image-set)
      IMAGE_SET_FILTER="${2:?missing value for --image-set}"
      shift 2
      ;;
    --php)
      PHP_FILTER="${2:?missing value for --php}"
      shift 2
      ;;
    --web)
      WEB_FILTER="${2:?missing value for --web}"
      shift 2
      ;;
    --database)
      DB_FILTER="${2:?missing value for --database}"
      shift 2
      ;;
    --moodle)
      MOODLE_FILTER="${2:?missing value for --moodle}"
      shift 2
      ;;
    --results-dir)
      RESULTS_DIR="${2:?missing value for --results-dir}"
      shift 2
      ;;
    --keep-failed-container)
      KEEP_FAILED_CONTAINER=true
      shift
      ;;
    --rebuild-images)
      REBUILD_IMAGES=true
      shift
      ;;
    --playwright)
      RUN_PLAYWRIGHT=true
      shift
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
docker_require_tools awk curl date mktemp

if [[ "${RUN_PLAYWRIGHT}" == "true" ]]; then
  require_playwright
fi

if [[ -z "${RESULTS_DIR}" ]]; then
  RESULTS_DIR="$(mktemp -d "/tmp/amp-moodle-docker-matrix-$(date +%Y%m%d-%H%M%S)-XXXX")"
else
  mkdir -p "${RESULTS_DIR}"
fi

RESULTS_TSV="${RESULTS_DIR}/results.tsv"
printf 'label\tstatus\tdistro\timage_set\timage\tcontainer\turl\tphp\tweb\tmoodle\tdatabase\textra_flags\tadmin_email\ttable_count\tartifacts\n' >"${RESULTS_TSV}"

matched=0
failures=0
index=0
active_container=""

function cleanup_active_container_on_exit() {
  if [[ -n "${active_container}" ]]; then
    cleanup_container "${active_container}" "FAIL"
  fi
}

trap cleanup_active_container_on_exit EXIT

for case_entry in "${SUPPORTED_CASES[@]}"; do
  IFS='|' read -r label distro image_set php_version web_server database moodle_version extra_flags <<<"${case_entry}"

  if ! case_matches_filters "${label}" "${distro}" "${image_set}" "${php_version}" "${web_server}" "${database}" "${moodle_version}"; then
    continue
  fi

  matched=$((matched + 1))
  index=$((index + 1))

  combo_dir="${RESULTS_DIR}/${label}"
  mkdir -p "${combo_dir}"
  install_log="${combo_dir}/install.log"
  inspect_log="${combo_dir}/inspect.txt"
  host_port=$((10442 + index))
  image=$(docker_image_for_case "${distro}" "${image_set}")
  container_name="amp-moodle-$(docker_slugify "${label}")"
  status="FAIL"
  table_count=""
  admin_password=""

  docker_build_image "${PROJECT_ROOT}" "${distro}" "${image_set}" "${REBUILD_IMAGES}"
  docker_run_case_container "${container_name}" "${image}" "${host_port}"
  active_container="${container_name}"

  build_laemp_args "${image_set}" "${php_version}" "${web_server}" "${database}" "${moodle_version}" "${extra_flags}"
  laemp_args=("${BUILT_LAEMP_ARGS[@]}")
  install_cmd=$(
    printf 'export LAEMP_FORCE_HOST_MODE=true DEBIAN_FRONTEND=noninteractive MOODLE_SITE_HOST=%q MOODLE_SITE_DOMAIN=%q MOODLE_ADMIN_EMAIL=%q; timeout %q /usr/local/bin/laemp.sh' \
      "${SITE_HOST}" "${SITE_DOMAIN}" "${ADMIN_EMAIL}" "${INSTALL_TIMEOUT_SECONDS}"
  )
  for arg in "${laemp_args[@]}"; do
    install_cmd+=" $(printf '%q' "${arg}")"
  done

  if docker_exec_root_shell "${container_name}" "${install_cmd}" 2>&1 | tee "${install_log}"; then
    admin_password=$(extract_admin_password "${install_log}" || true)
    if verify_case "${container_name}" "${web_server}" "${database}" "${host_port}" "${combo_dir}"; then
      table_count=$(cat "${combo_dir}/table_count.txt")
      if [[ "${RUN_PLAYWRIGHT}" == "true" && -n "${admin_password}" ]]; then
        if run_playwright "${combo_dir}" "${host_port}" "${admin_password}"; then
          status="PASS"
        else
          status="FAIL"
        fi
      else
        status="PASS"
      fi
    fi
  else
    exit_code=$?
    if [[ "${exit_code}" -eq 124 ]]; then
      status="TIMEOUT"
    else
      status="FAIL"
    fi
  fi

  "${DOCKER_CMD}" inspect "${container_name}" >"${inspect_log}" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\thttps://%s:%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${label}" \
    "${status}" \
    "${distro}" \
    "${image_set}" \
    "${image}" \
    "${container_name}" \
    "${SITE_HOST}" \
    "${host_port}" \
    "${php_version}" \
    "${web_server}" \
    "${moodle_version}" \
    "${database}" \
    "${extra_flags}" \
    "${ADMIN_EMAIL}" \
    "${table_count}" \
    "${combo_dir}" >>"${RESULTS_TSV}"

  if [[ "${status}" != "PASS" ]]; then
    failures=$((failures + 1))
  fi

  cleanup_container "${container_name}" "${status}"
  active_container=""
done

trap - EXIT

if [[ "${matched}" -eq 0 ]]; then
  echo "Error: no cases matched the requested filters." >&2
  echo "Results directory: ${RESULTS_DIR}" >&2
  exit 1
fi

echo "Results written to ${RESULTS_TSV}"

if [[ "${failures}" -gt 0 ]]; then
  echo "Docker matrix completed with ${failures} failure(s)." >&2
  exit 1
fi

echo "Docker matrix completed successfully."
