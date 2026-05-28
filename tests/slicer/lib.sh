#!/usr/bin/env bash

set -euo pipefail

SLICER_URL="${SLICER_URL:-$HOME/slicer-mac/slicer.sock}"
SLICER_HOSTGROUP="${SLICER_HOSTGROUP:-sbox}"
SLICER_VM_UID="${SLICER_VM_UID:-1000}"

function slicer_require() {
  if ! command -v slicer >/dev/null 2>&1; then
    echo "Error: slicer CLI is not installed or not in PATH." >&2
    exit 1
  fi

  if ! slicer vm list --url "${SLICER_URL}" >/dev/null 2>&1; then
    echo "Error: cannot reach Slicer daemon at ${SLICER_URL}." >&2
    echo "Set SLICER_URL if your daemon is not on the default socket." >&2
    exit 1
  fi
}

function slicer_require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "Error: required tool '${tool}' is not installed." >&2
      exit 1
    fi
  done
}

function slicer_create_vm() {
  local workflow="$1"
  local output
  output=$(slicer vm add "${SLICER_HOSTGROUP}" --url "${SLICER_URL}" \
    --tag "workflow=${workflow}" \
    --tag "owner=amp-moodle")
  printf '%s\n' "${output}" >&2
  awk '/Hostname:/ {print $2; exit}' <<<"${output}"
}

function slicer_wait_vm() {
  local vm_name="$1"
  local timeout="${2:-5m}"
  slicer vm ready "${vm_name}" --url "${SLICER_URL}" --timeout "${timeout}" >/dev/null
}

function slicer_delete_vm() {
  local vm_name="$1"
  slicer vm delete "${vm_name}" --url "${SLICER_URL}" >/dev/null
}

function slicer_vm_ip() {
  local vm_name="$1"
  slicer vm list --url "${SLICER_URL}" | awk -v vm="${vm_name}" '$1==vm {print $2; exit}'
}

function slicer_vm_cp() {
  slicer vm cp --url "${SLICER_URL}" "$@"
}

function slicer_vm_exec() {
  local vm_name="$1"
  shift
  slicer vm exec "${vm_name}" --url "${SLICER_URL}" --uid "${SLICER_VM_UID}" "$@"
}

function slicer_vm_exec_retry() {
  local vm_name="$1"
  shift
  for _ in 1 2 3 4 5; do
    if slicer vm exec "${vm_name}" --url "${SLICER_URL}" --uid "${SLICER_VM_UID}" "$@"; then
      return 0
    fi
    sleep 2
  done

  return 1
}

function slicer_vm_exec_root() {
  local vm_name="$1"
  shift
  slicer vm exec "${vm_name}" --url "${SLICER_URL}" "$@"
}

function slicer_latest_vm() {
  slicer vm list --url "${SLICER_URL}" | awk 'NR>2 && $1!="" {print $1; exit}'
}

function slicer_slugify() {
  tr '[:upper:]' '[:lower:]' <<<"$1" | tr -cs '[:alnum:]' '-'
}
