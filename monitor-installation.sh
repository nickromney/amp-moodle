#!/bin/bash
# Monitor laemp.sh installation progress in containers

CONTAINERS=("laemp-test-ubuntu" "laemp-test-debian")

echo "========================================"
echo "Monitoring laemp.sh installations"
echo "========================================"
echo ""

while true; do
  clear
  echo "========================================"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation Status"
  echo "========================================"
  echo ""

  for container in "${CONTAINERS[@]}"; do
    echo "[$container]"
    echo "----------------------------------------"

    # Check if container exists and is running
    if ! podman ps --format "{{.Names}}" | grep -q "^${container}$"; then
      echo "  Status: Container not running"
      echo ""
      continue
    fi

    # Check installation status file
    if podman exec "$container" test -f /home/testuser/install-status 2>/dev/null; then
      status=$(podman exec "$container" cat /home/testuser/install-status 2>/dev/null || echo "UNKNOWN")
      echo "  Status: $status"

      # If completed, show verification
      if [[ "$status" == "SUCCESS" ]]; then
        echo "  Verification: Running checks..."
        if podman exec "$container" /usr/local/bin/verify-moodle.sh >/dev/null 2>&1; then
          echo "  ✓ All verification checks passed"
        else
          echo "  ✗ Verification checks failed"
        fi
      fi
    else
      echo "  Status: STARTING (no status file yet)"
    fi

    # Show last few log lines
    echo "  Last log entries:"
    podman exec "$container" tail -3 /home/testuser/laemp-install.log 2>/dev/null | sed 's/^/    /'
    echo ""
  done

  echo "========================================"
  echo "Press Ctrl+C to stop monitoring"
  echo "Refresh in 60 seconds..."
  echo ""

  sleep 60
done
