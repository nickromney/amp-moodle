#!/usr/bin/env bash
# Run BATS option-parsing tests in an existing Slicer VM using native slicer vm operations.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=tests/slicer/lib.sh
source "${SCRIPT_DIR}/lib.sh"

slicer_require

VM_NAME="${SLICER_VM:-$(slicer_latest_vm)}"
if [[ -z "${VM_NAME}" ]]; then
  echo "Error: no running Slicer VM found. Set SLICER_VM or create one first." >&2
  exit 1
fi

VM_IP="$(slicer_vm_ip "${VM_NAME}")"
echo "Using VM: ${VM_NAME} (${VM_IP})"

echo "Ensuring bats is installed..."
slicer_vm_exec "${VM_NAME}" -- "if ! command -v bats >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y bats; fi"

echo "Copying test files to VM..."
slicer_vm_cp "${PROJECT_ROOT}/test_laemp.bats" "${VM_NAME}:/home/ubuntu/test_laemp.bats" --mode binary --permissions 0644 >/dev/null
slicer_vm_cp "${PROJECT_ROOT}/laemp.sh" "${VM_NAME}:/home/ubuntu/laemp.sh" --mode binary --permissions 0755 >/dev/null

echo "Running BATS tests..."
slicer_vm_exec "${VM_NAME}" -- "cd /home/ubuntu && bats test_laemp.bats"
