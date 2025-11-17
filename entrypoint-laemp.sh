#!/bin/bash
set -euxo pipefail

LOG_DIR="${LAEMP_LOG_DIR:-/var/log/laemp}"
mkdir -p "$LOG_DIR"
chmod 755 "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"

if [[ -f /usr/sbin/policy-rc.d ]]; then
  rm -f /usr/sbin/policy-rc.d
fi

wait_for_db() {
  local host="$1"
  local port="$2"
  local max_wait=60
  local waited=0

  echo "Waiting for ${host}:${port}..." | tee -a "$LOG_FILE"

  # Prefer nc if available, fallback to /dev/tcp
  if command -v nc >/dev/null 2>&1; then
    while ! nc -z "$host" "$port" >/dev/null 2>&1; do
      sleep 2
      waited=$((waited + 2))
      if [ "$waited" -ge "$max_wait" ]; then
        echo "Timed out waiting for ${host}:${port}" | tee -a "$LOG_FILE"
        exit 1
      fi
    done
  else
    while ! timeout 1 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; do
      sleep 2
      waited=$((waited + 2))
      if [ "$waited" -ge "$max_wait" ]; then
        echo "Timed out waiting for ${host}:${port}" | tee -a "$LOG_FILE"
        exit 1
      fi
    done
  fi

  echo "Database is ready" | tee -a "$LOG_FILE"
}

DB_PORT=5432
if [[ "${DB_TYPE:-}" == "mariadb" || "${DB_TYPE:-}" == "mysql" ]]; then
  DB_PORT=3306
fi

if [[ -n "${DB_HOST:-}" ]]; then
  wait_for_db "$DB_HOST" "$DB_PORT"
fi

echo "Launching laemp.sh" | tee -a "$LOG_FILE"
if /usr/local/bin/laemp.sh -c -p "${PHP_VERSION:-8.4}" -w nginx -d "${DB_TYPE:-pgsql}" -m "${MOODLE_VERSION:-501}" -S --skip-db-server 2>&1 | tee -a "$LOG_FILE"; then
  echo "SUCCESS" | tee -a "$LOG_FILE"
  exit 0
else
  echo "FAILED" | tee -a "$LOG_FILE"
  exit 1
fi
