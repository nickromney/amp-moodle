#!/bin/bash
# Complete cleanup of laemp test environment

set -e

echo "Cleaning up laemp test environment..."
echo "======================================"

# Stop and remove containers
echo "Stopping containers..."
podman-compose down -v 2>/dev/null || true

# Remove volumes
echo "Removing volumes..."
podman volume rm laemp-mysql-data laemp-postgres-data \
  laemp-ubuntu-logs laemp-ubuntu-moodle \
  laemp-debian-logs laemp-debian-moodle 2>/dev/null || true

# Remove network
echo "Removing network..."
podman network rm laemp-test-net 2>/dev/null || true

echo ""
echo "======================================"
echo "Cleanup complete! ✓"
