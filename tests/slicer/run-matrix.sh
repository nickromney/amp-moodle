#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=tests/slicer/lib.sh
source "${SCRIPT_DIR}/lib.sh"

SUPPORTED_COMBOS=(
  "8.3|apache|405"
  "8.3|apache|500"
  "8.3|apache|5021"
  "8.3|nginx|405"
  "8.3|nginx|500"
  "8.3|nginx|5021"
  "8.4|apache|500"
  "8.4|apache|5021"
  "8.4|nginx|500"
  "8.4|nginx|5021"
)

DB_TYPE="mariadb"
CERT_MODE="self-signed"
RESULTS_DIR=""
KEEP_FAILED_VM=false
PLAYWRIGHT_SPEC="tests/e2e/slicer-smoke.spec.ts"
PLAYWRIGHT_PROJECT="chromium"
PHP_FILTER=""
WEB_FILTER=""
MOODLE_FILTER=""
declare -a EXTRA_FLAGS=()

function usage() {
  cat <<'EOF'
Run the supported LAEMP Slicer matrix with Playwright smoke checks.

Usage:
  tests/slicer/run-matrix.sh [options]

Options:
  --php VERSION             Filter to one PHP version (8.3 or 8.4)
  --web SERVER              Filter to one web server (apache or nginx)
  --moodle VERSION          Filter to one Moodle version (405, 500, 5021)
  --database TYPE           Database type to install (default: mariadb)
  --cert MODE               Certificate mode: self-signed or mkcert (default: self-signed)
  --extra-flag FLAG         Extra laemp.sh flag to pass through (repeatable)
  --keep-failed-vm          Do not delete the VM after a failed run
  --results-dir DIR         Write logs and TSV summary to DIR
  --project NAME            Playwright project to run (default: chromium)
  -h, --help                Show this help text

Examples:
  tests/slicer/run-matrix.sh
  tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5021
  tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5021 --database pgsql --extra-flag -M
EOF
}

function require_playwright() {
  slicer_require_tools awk date mktemp node npm npx
  if [[ ! -x "${PROJECT_ROOT}/node_modules/.bin/playwright" ]]; then
    echo "Error: Playwright dependencies are not installed." >&2
    echo "Run 'npm install' in ${PROJECT_ROOT} first." >&2
    exit 1
  fi
}

function build_laemp_args() {
  local php_version="$1"
  local web_server="$2"
  local moodle_version="$3"
  local args=(-c -p "${php_version}" -w "${web_server}" -d "${DB_TYPE}" -m "${moodle_version}")

  case "${CERT_MODE}" in
    self-signed)
      args+=(-S)
      ;;
    mkcert)
      args+=(--mkcert)
      ;;
    *)
      echo "Error: unsupported certificate mode '${CERT_MODE}'." >&2
      exit 1
      ;;
  esac

  if [[ ${#EXTRA_FLAGS[@]} -gt 0 ]]; then
    args+=("${EXTRA_FLAGS[@]}")
  fi

  printf '%s\n' "${args[@]}"
}

function combo_matches_filters() {
  local php_version="$1"
  local web_server="$2"
  local moodle_version="$3"

  [[ -z "${PHP_FILTER}" || "${PHP_FILTER}" == "${php_version}" ]] || return 1
  [[ -z "${WEB_FILTER}" || "${WEB_FILTER}" == "${web_server}" ]] || return 1
  [[ -z "${MOODLE_FILTER}" || "${MOODLE_FILTER}" == "${moodle_version}" ]] || return 1
}

function extract_admin_password() {
  local install_log="$1"
  awk -F': ' '/Admin password:/ {print $NF; exit}' "${install_log}"
}

function verify_stack_in_vm() {
  local vm_name="$1"
  local web_server="$2"
  local site_host="$3"
  local combo_dir="$4"
  local table_count=""
  local web_service="${web_server}"

  if [[ "${web_server}" == "apache" ]]; then
    web_service="apache2"
  fi

  slicer_vm_exec_retry "${vm_name}" -- "curl -ksSfI https://${site_host} | head -n 1" > "${combo_dir}/http_head.txt"
  slicer_vm_exec_retry "${vm_name}" -- "systemctl is-active ${web_service}" > "${combo_dir}/web_service.txt"
  slicer_vm_exec_retry "${vm_name}" -- "systemctl is-active cron" > "${combo_dir}/cron_service.txt"

  if [[ "${DB_TYPE}" == "pgsql" ]]; then
    slicer_vm_exec_retry "${vm_name}" -- "systemctl is-active postgresql" > "${combo_dir}/db_service.txt"
    table_count=$(slicer_vm_exec_retry "${vm_name}" -- "sudo -u postgres psql -d moodle -Atc \"select count(*) from information_schema.tables where table_schema = 'public' and table_name like 'mdl_%';\"")
  else
    slicer_vm_exec_retry "${vm_name}" -- "systemctl is-active mariadb" > "${combo_dir}/db_service.txt"
    table_count=$(slicer_vm_exec_retry "${vm_name}" -- "sudo mysql -Nse \"select count(*) from information_schema.tables where table_schema = 'moodle' and table_name like 'mdl_%';\"")
  fi

  if [[ -z "${table_count}" || "${table_count}" -lt 400 ]]; then
    echo "Error: Moodle table count check failed for ${vm_name} (${table_count:-missing})." >&2
    return 1
  fi

  printf '%s\n' "${table_count}" > "${combo_dir}/table_count.txt"
}

function run_playwright_smoke() {
  local combo_dir="$1"
  local site_host="$2"
  local admin_password="$3"

  (
    cd "${PROJECT_ROOT}"
    MOODLE_URL="https://${site_host}" \
    MOODLE_ADMIN_USERNAME="admin" \
    MOODLE_ADMIN_PASSWORD="${admin_password}" \
    MOODLE_ADMIN_EMAIL="demo@moodle.test" \
    MOODLE_SITE_NAME="${site_host}" \
    npx playwright test "${PLAYWRIGHT_SPEC}" \
      --project "${PLAYWRIGHT_PROJECT}" \
      --reporter=list \
      --workers 1 \
      --output "${combo_dir}/playwright-output"
  ) 2>&1 | tee "${combo_dir}/playwright.log"
}

function cleanup_vm() {
  local vm_name="$1"
  local run_status="$2"

  if [[ -z "${vm_name}" ]]; then
    return 0
  fi

  if [[ "${run_status}" != "PASS" && "${KEEP_FAILED_VM}" == "true" ]]; then
    echo "Keeping failed VM ${vm_name} for inspection." >&2
    return 0
  fi

  slicer_delete_vm "${vm_name}" || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --php)
      PHP_FILTER="${2:?missing value for --php}"
      shift 2
      ;;
    --web)
      WEB_FILTER="${2:?missing value for --web}"
      shift 2
      ;;
    --moodle)
      MOODLE_FILTER="${2:?missing value for --moodle}"
      shift 2
      ;;
    --database)
      DB_TYPE="${2:?missing value for --database}"
      shift 2
      ;;
    --cert)
      CERT_MODE="${2:?missing value for --cert}"
      shift 2
      ;;
    --extra-flag)
      EXTRA_FLAGS+=("${2:?missing value for --extra-flag}")
      shift 2
      ;;
    --keep-failed-vm)
      KEEP_FAILED_VM=true
      shift
      ;;
    --results-dir)
      RESULTS_DIR="${2:?missing value for --results-dir}"
      shift 2
      ;;
    --project)
      PLAYWRIGHT_PROJECT="${2:?missing value for --project}"
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

slicer_require
require_playwright

if [[ -z "${RESULTS_DIR}" ]]; then
  RESULTS_DIR="$(mktemp -d "/tmp/amp-moodle-slicer-matrix-$(date +%Y%m%d-%H%M%S)-XXXX")"
else
  mkdir -p "${RESULTS_DIR}"
fi

RESULTS_TSV="${RESULTS_DIR}/results.tsv"
printf 'label\tstatus\tvm\tip\turl\tphp\tweb\tmoodle\tdatabase\tcert\tadmin_email\ttable_count\tartifacts\n' > "${RESULTS_TSV}"

matched=0
failures=0
declare -a LAEMP_ARGS=()
active_vm=""

function cleanup_active_vm_on_exit() {
  if [[ -n "${active_vm}" ]]; then
    cleanup_vm "${active_vm}" "FAIL"
  fi
}

trap cleanup_active_vm_on_exit EXIT

for combo in "${SUPPORTED_COMBOS[@]}"; do
  IFS='|' read -r php_version web_server moodle_version <<<"${combo}"

  if ! combo_matches_filters "${php_version}" "${web_server}" "${moodle_version}"; then
    continue
  fi

  matched=1
  label="php${php_version}-${web_server}-moodle${moodle_version}-${DB_TYPE}"
  combo_dir="${RESULTS_DIR}/${label}"
  mkdir -p "${combo_dir}"
  install_log="${combo_dir}/install.log"
  run_status="FAIL"
  vm_name=""

  echo "=== ${label} ==="
  workflow="amp-moodle-$(slicer_slugify "${label}")-$(date +%Y%m%d-%H%M%S)"
  vm_name="$(slicer_create_vm "${workflow}")"
  active_vm="${vm_name}"
  slicer_wait_vm "${vm_name}" "3m"
  vm_ip="$(slicer_vm_ip "${vm_name}")"
  site_host="moodle.test.${vm_ip}.sslip.io"

  slicer_vm_cp "${PROJECT_ROOT}/laemp.sh" "${vm_name}:/home/ubuntu/laemp.sh" --mode binary --permissions 0755 >/dev/null

  LAEMP_ARGS=()
  while IFS= read -r arg; do
    LAEMP_ARGS+=("${arg}")
  done < <(build_laemp_args "${php_version}" "${web_server}" "${moodle_version}")
  install_cmd=(sudo -E /home/ubuntu/laemp.sh)
  install_cmd+=("${LAEMP_ARGS[@]}")

  if slicer_vm_exec "${vm_name}" \
    --env "MOODLE_SITE_DOMAIN=moodle.test" \
    --env "MOODLE_SITE_HOST=${site_host}" \
    --env "MOODLE_ADMIN_EMAIL=demo@moodle.test" \
    -- "$(printf '%q ' "${install_cmd[@]}")" 2>&1 | tee "${install_log}"; then
    admin_password="$(extract_admin_password "${install_log}")"
    if [[ -z "${admin_password}" ]]; then
      echo "Error: could not extract admin password from ${install_log}." >&2
      failures=$((failures + 1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "FAIL" "${vm_name}" "${vm_ip}" "https://${site_host}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "demo@moodle.test" "" "${combo_dir}" >> "${RESULTS_TSV}"
      cleanup_vm "${vm_name}" "${run_status}"
      active_vm=""
      continue
    fi

    if verify_stack_in_vm "${vm_name}" "${web_server}" "${site_host}" "${combo_dir}" && \
      run_playwright_smoke "${combo_dir}" "${site_host}" "${admin_password}"; then
      table_count="$(cat "${combo_dir}/table_count.txt")"
      run_status="PASS"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "${run_status}" "${vm_name}" "${vm_ip}" "https://${site_host}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "demo@moodle.test" "${table_count}" "${combo_dir}" >> "${RESULTS_TSV}"
    else
      failures=$((failures + 1))
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${label}" "FAIL" "${vm_name}" "${vm_ip}" "https://${site_host}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "demo@moodle.test" "" "${combo_dir}" >> "${RESULTS_TSV}"
    fi
  else
    failures=$((failures + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${label}" "${run_status}" "${vm_name}" "${vm_ip:-}" "https://${site_host:-}" "${php_version}" "${web_server}" "${moodle_version}" "${DB_TYPE}" "${CERT_MODE}" "demo@moodle.test" "" "${combo_dir}" >> "${RESULTS_TSV}"
  fi

  cleanup_vm "${vm_name}" "${run_status}"
  active_vm=""
done

if [[ "${matched}" -eq 0 ]]; then
  echo "Error: no supported combos matched the supplied filters." >&2
  exit 1
fi

echo "Results written to ${RESULTS_TSV}"

if [[ "${failures}" -gt 0 ]]; then
  exit 1
fi
