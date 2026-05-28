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

  docker_cleanup_container "${container_name}"

  if [[ -n "${DOCKER_PLATFORM}" ]]; then
    "${DOCKER_CMD}" run -d \
      --platform "${DOCKER_PLATFORM}" \
      --name "${container_name}" \
      --privileged \
      --tmpfs /tmp \
      --tmpfs /run \
      --tmpfs /run/lock \
      -p "${https_port}:443" \
      "${image}" \
      sleep infinity >/dev/null
  else
    "${DOCKER_CMD}" run -d \
      --name "${container_name}" \
      --privileged \
      --tmpfs /tmp \
      --tmpfs /run \
      --tmpfs /run/lock \
      -p "${https_port}:443" \
      "${image}" \
      sleep infinity >/dev/null
  fi
}

function docker_exec_root_shell() {
  local container_name="$1"
  local shell_command="$2"
  "${DOCKER_CMD}" exec --user root "${container_name}" bash -lc "${shell_command}"
}
