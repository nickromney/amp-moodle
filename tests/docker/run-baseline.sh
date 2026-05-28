#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec "${SCRIPT_DIR}/run-matrix.sh" \
  --label debian-stock-nginx-mariadb-m5013 \
  --distro debian \
  --image-set stock \
  --php 8.4 \
  --web nginx \
  --database mariadb \
  --moodle 5013 \
  "$@"
