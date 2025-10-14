#!/bin/bash
# Verify Moodle installation is working correctly

set -e

echo "Verifying Moodle installation..."
echo "================================="

# Check if services are running
echo -n "Checking Nginx... "
if pidof nginx >/dev/null 2>&1; then
  echo "✓ Running"
else
  echo "✗ Not running"
  exit 1
fi

echo -n "Checking PHP-FPM... "
if pidof php-fpm8.4 >/dev/null 2>&1; then
  echo "✓ Running"
else
  echo "✗ Not running"
  exit 1
fi

echo -n "Checking PostgreSQL... "
if pidof postgres >/dev/null 2>&1; then
  echo "✓ Running"
else
  echo "✗ Not running"
  exit 1
fi

# Check if Moodle responds
echo -n "Checking Moodle HTTP response... "
if curl -k -f -s https://localhost/index.php >/dev/null 2>&1; then
  echo "✓ Responding"
else
  echo "✗ Not responding"
  exit 1
fi

# Check if database is accessible
echo -n "Checking database connectivity... "
if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
  echo "✓ Connected"
else
  echo "✗ Cannot connect"
  exit 1
fi

# Check if Moodle database exists and has tables
echo -n "Checking Moodle database... "
TABLE_COUNT=$(sudo -u postgres psql -d moodle -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | xargs || echo "0")
if [ "$TABLE_COUNT" -gt 100 ]; then
  echo "✓ $TABLE_COUNT tables found"
else
  echo "✗ Expected 100+ tables, found $TABLE_COUNT"
  exit 1
fi

echo ""
echo "================================="
echo "All checks passed! ✓"
echo "Moodle is ready at https://localhost"
