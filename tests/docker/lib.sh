#!/usr/bin/env bash

set -euo pipefail

DOCKER_CMD="${DOCKER_CMD:-docker}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-}"

function docker_require() {
  if ! command -v "${DOCKER_CMD}" >/dev/null 2>&1; then
    echo "Error: ${DOCKER_CMD} is not installed or not in PATH." >&2
    exit 1
  fi

  if ! "${DOCKER_CMD}" info >/dev/null 2>&1; then
    echo "Error: cannot talk to the Docker daemon." >&2
    exit 1
  fi
}

function docker_require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Error: required tool '${tool}' is not installed." >&2
      exit 1
    fi
  done
}

# Keep in sync with frankenphp-moodle and laemp docker_allocate_host_port helpers.
function docker_host_port_busy() {
  local host="$1"
  local port="$2"

  command -v python3 >/dev/null 2>&1 || {
    echo "Error: python3 is required to probe host ports." >&2
    exit 1
  }

  python3 - "${host}" "${port}" <<'PY'
import socket
import sys

host = sys.argv[1]
port = int(sys.argv[2])

probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
probe.settimeout(0.2)
try:
    if probe.connect_ex((host, port)) == 0:
        sys.exit(0)
finally:
    probe.close()

binder = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    binder.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    binder.bind((host, port))
except OSError:
    sys.exit(0)
finally:
    binder.close()

sys.exit(1)
PY
}

function docker_host_port_occupant() {
  local host="$1"
  local port="$2"
  local line=""

  if command -v lsof >/dev/null 2>&1; then
    line="$(lsof -nP -iTCP@"${host}:${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1 " (pid " $2 ")"}')"
  fi
  if [[ -z "${line}" ]] && command -v "${DOCKER_CMD}" >/dev/null 2>&1; then
    line="$("${DOCKER_CMD}" ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | awk -v p=":${port}->" 'index($0, p) { print $1; exit }')"
  fi
  printf '%s\n' "${line}"
}

function docker_allocate_host_port() {
  local host="$1"
  local preferred="$2"
  local attempts=30
  local candidate="${preferred}"
  local occupant=""
  local i
  local reserved
  local skipped

  shift 2

  if docker_host_port_busy "${host}" "${preferred}"; then
    occupant="$(docker_host_port_occupant "${host}" "${preferred}")"
    if [[ "${preferred}" == "80" ]]; then
      candidate="18280"
    elif [[ "${preferred}" == "443" ]]; then
      candidate="18643"
    fi
    if [[ -n "${occupant}" ]]; then
      echo "Host port ${host}:${preferred} is busy (${occupant}); looking for a free port from ${candidate}." >&2
    else
      echo "Host port ${host}:${preferred} is busy; looking for a free port from ${candidate}." >&2
    fi
  fi

  i=0
  while [[ "${i}" -lt "${attempts}" ]]; do
    skipped=false
    for reserved in "$@"; do
      if [[ -n "${reserved}" && "${candidate}" == "${reserved}" ]]; then
        skipped=true
        break
      fi
    done
    if [[ "${skipped}" == "false" ]] && ! docker_host_port_busy "${host}" "${candidate}"; then
      if [[ "${candidate}" != "${preferred}" ]]; then
        echo "Using host port ${host}:${candidate}." >&2
      fi
      printf '%s\n' "${candidate}"
      return 0
    fi
    candidate=$((candidate + 1))
    i=$((i + 1))
  done

  echo "Error: could not find a free host port near ${preferred} on ${host}." >&2
  return 1
}

function docker_published_host_port() {
  local mapping="${1:-}"

  if [[ -z "${mapping}" ]]; then
    return 1
  fi
  printf '%s\n' "${mapping##*:}"
}

function docker_slugify() {
  tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs '[:alnum:]' '-'
}

function docker_image_for_case() {
  local distro="$1"
  local image_set="$2"

  case "${distro}:${image_set}" in
    debian:stock)
      printf '%s\n' "amp-moodle-debian:13"
      ;;
    debian:prereqs)
      printf '%s\n' "amp-moodle-prereqs-debian"
      ;;
    ubuntu:stock)
      printf '%s\n' "amp-moodle-ubuntu:24.04"
      ;;
    ubuntu:prereqs)
      printf '%s\n' "amp-moodle-prereqs-ubuntu"
      ;;
    *)
      echo "Error: unsupported distro/image-set '${distro}:${image_set}'." >&2
      exit 1
      ;;
  esac
}

function dockerfile_for_case() {
  local distro="$1"
  local image_set="$2"

  case "${distro}:${image_set}" in
    debian:stock)
      printf '%s\n' "Dockerfile.debian"
      ;;
    debian:prereqs)
      printf '%s\n' "Dockerfile.prereqs.debian"
      ;;
    ubuntu:stock)
      printf '%s\n' "Dockerfile.ubuntu"
      ;;
    ubuntu:prereqs)
      printf '%s\n' "Dockerfile.prereqs.ubuntu"
      ;;
    *)
      echo "Error: unsupported distro/image-set '${distro}:${image_set}'." >&2
      exit 1
      ;;
  esac
}

function docker_image_exists() {
  local image="$1"
  "${DOCKER_CMD}" image inspect "${image}" >/dev/null 2>&1
}

function docker_build_image() {
  local project_root="$1"
  local distro="$2"
  local image_set="$3"
  local rebuild="${4:-false}"
  local image
  local dockerfile

  image=$(docker_image_for_case "${distro}" "${image_set}")
  dockerfile=$(dockerfile_for_case "${distro}" "${image_set}")
  if [[ "${dockerfile}" != /* ]]; then
    dockerfile="${project_root}/${dockerfile}"
  fi

  if [[ "${rebuild}" != "true" ]] && docker_image_exists "${image}"; then
    return 0
  fi

  if [[ -n "${DOCKER_PLATFORM}" ]]; then
    "${DOCKER_CMD}" build --platform "${DOCKER_PLATFORM}" -f "${dockerfile}" -t "${image}" "${project_root}"
  else
    "${DOCKER_CMD}" build -f "${dockerfile}" -t "${image}" "${project_root}"
  fi
}

function docker_cleanup_container() {
  local container_name="$1"
  "${DOCKER_CMD}" rm -f "${container_name}" >/dev/null 2>&1 || true
}

function docker_run_case_container() {
  local container_name="$1"
  local image="$2"
  local https_port="$3"
  local bind_host="${4:-127.0.0.1}"

  docker_cleanup_container "${container_name}"

  if [[ -n "${DOCKER_PLATFORM}" ]]; then
    "${DOCKER_CMD}" run -d \
      --platform "${DOCKER_PLATFORM}" \
      --name "${container_name}" \
      --privileged \
      --tmpfs /tmp \
      --tmpfs /run \
      --tmpfs /run/lock \
      -p "${bind_host}:${https_port}:443" \
      "${image}" \
      sleep infinity >/dev/null
  else
    "${DOCKER_CMD}" run -d \
      --name "${container_name}" \
      --privileged \
      --tmpfs /tmp \
      --tmpfs /run \
      --tmpfs /run/lock \
      -p "${bind_host}:${https_port}:443" \
      "${image}" \
      sleep infinity >/dev/null
  fi
}

function docker_exec_root_shell() {
  local container_name="$1"
  local shell_command="$2"
  "${DOCKER_CMD}" exec --user root "${container_name}" bash -lc "${shell_command}"
}
