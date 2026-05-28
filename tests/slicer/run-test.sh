#!/usr/bin/env bash
# Run a baseline LAEMP installation in an existing Slicer VM using native slicer vm operations.
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
SITE_HOST="moodle.test.${VM_IP}.sslip.io"

echo "Using VM: ${VM_NAME} (${VM_IP})"
echo "Copying laemp.sh to VM..."
slicer_vm_cp "${PROJECT_ROOT}/laemp.sh" "${VM_NAME}:/home/ubuntu/laemp.sh" --mode binary --permissions 0755 >/dev/null

echo "Running LAEMP installation (this may take 10-15 minutes)..."
slicer_vm_exec "${VM_NAME}" \
  --env "MOODLE_SITE_DOMAIN=moodle.test" \
  --env "MOODLE_SITE_HOST=${SITE_HOST}" \
  --env "MOODLE_ADMIN_EMAIL=demo@moodle.test" \
  -- "sudo -E /home/ubuntu/laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5013 -S"

echo "LAEMP installation complete."
echo "Access Moodle at: https://${SITE_HOST}"
