#!/bin/bash
# Complete cleanup of laemp test environment

set -e

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
COMPOSE_CMD=(${COMPOSE_CMD:-docker compose})

echo "Cleaning up laemp test environment..."
echo "======================================"

# Stop and remove containers
echo "Stopping containers..."
"${COMPOSE_CMD[@]}" down -v 2>/dev/null || true

# Remove volumes
echo "Removing volumes..."
"${CONTAINER_RUNTIME}" volume rm laemp-mysql-data laemp-postgres-data \
  laemp-ubuntu-logs laemp-ubuntu-moodle \
  laemp-debian-logs laemp-debian-moodle \
  laemp-serversideup-moodle 2>/dev/null || true

# Remove network
echo "Removing network..."
"${CONTAINER_RUNTIME}" network rm laemp-test-net 2>/dev/null || true

echo ""
echo "======================================"
echo "Cleanup complete! ✓"
