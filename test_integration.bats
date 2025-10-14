#!/usr/bin/env bats

# Integration tests for laemp.sh that run full installations in Podman containers
# These tests verify end-to-end functionality including service installation,
# configuration, and operation.

# Load test helpers if available
# Note: BATS load command doesn't support shell redirections
# If the file doesn't exist, BATS will skip it gracefully
# load '/usr/local/lib/bats/load.bash'

# Global test configuration
export PODMAN_PLATFORM="linux/amd64"
export TEST_TIMEOUT=600  # 10 minutes for full installations
export CONTAINER_PREFIX="laemp-test"

# Container tracking
declare -a TEST_CONTAINERS

# Setup function runs before each test
setup() {
  # Create unique container name for this test
  export TEST_CONTAINER="${CONTAINER_PREFIX}-$(date +%s)-$$"

  # Track container for cleanup
  TEST_CONTAINERS+=("$TEST_CONTAINER")

  # Ensure Podman images are built (Ubuntu 24.04 or Debian 13)
  if ! podman image exists amp-moodle-ubuntu:24.04; then
    skip "Ubuntu 24.04 test image not found. Run: podman build -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 ."
  fi
}

# Teardown function runs after each test
teardown() {
  # Clean up test container if it exists
  if [ -n "${TEST_CONTAINER:-}" ]; then
    podman rm -f "$TEST_CONTAINER" 2>/dev/null || true
  fi
}

# Cleanup all test containers on exit
cleanup_all_containers() {
  for container in "${TEST_CONTAINERS[@]}"; do
    podman rm -f "$container" 2>/dev/null || true
  done
}
trap cleanup_all_containers EXIT

#
# Helper Functions
#

# Start a test container and copy script into it
start_test_container() {
  local image="${1:-amp-moodle-ubuntu:24.04}"

  # Start container with systemd support
  podman run -d \
    --platform "$PODMAN_PLATFORM" \
    --name "$TEST_CONTAINER" \
    --privileged \
    --tmpfs /tmp \
    --tmpfs /run \
    --tmpfs /run/lock \
    --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \
    "$image" \
    /bin/bash -c "sleep infinity"

  # Wait for container to be ready
  sleep 2

  # Copy laemp.sh script into container
  podman cp laemp.sh "${TEST_CONTAINER}:/usr/local/bin/laemp.sh"
  podman exec "$TEST_CONTAINER" chmod +x /usr/local/bin/laemp.sh
}

# Execute laemp.sh in container with given arguments
# Note: Must run as root for package installation and system configuration
exec_laemp() {
  local args="$*"
  podman exec --user root "$TEST_CONTAINER" bash -c "cd /root && /usr/local/bin/laemp.sh $args"
}

# Check if a service is running in the container
service_is_active() {
  local service="$1"
  podman exec --user root "$TEST_CONTAINER" systemctl is-active "$service" >/dev/null 2>&1
}

# Check if a file exists in the container
file_exists() {
  local file="$1"
  podman exec "$TEST_CONTAINER" test -f "$file"
}

# Check if a directory exists in the container
dir_exists() {
  local dir="$1"
  podman exec "$TEST_CONTAINER" test -d "$dir"
}

# Get file checksum from container
get_file_checksum() {
  local file="$1"
  podman exec "$TEST_CONTAINER" md5sum "$file" 2>/dev/null | awk '{print $1}'
}

# Check if command exists in container
command_exists() {
  local cmd="$1"
  podman exec "$TEST_CONTAINER" command -v "$cmd" >/dev/null 2>&1
}

# Check if systemd unit exists in container
unit_exists() {
  local unit="$1"
  podman exec --user root "$TEST_CONTAINER" systemctl list-units --all --no-pager | grep -q "$unit"
}

# Check if postgres database exists in container
postgres_db_exists() {
  local dbname="$1"
  podman exec --user root "$TEST_CONTAINER" sudo -u postgres psql -l | grep -q "$dbname"
}

# Count log files in container
count_log_files() {
  podman exec "$TEST_CONTAINER" bash -c 'ls /usr/local/bin/logs/*.log 2>/dev/null | wc -l'
}

#
# Basic Installation Tests
#

@test "install nginx with php" {
  start_test_container

  # Run installation
  run exec_laemp -p -w nginx -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Nginx installed
  run command_exists nginx
  [ "$status" -eq 0 ]

  # Verify PHP installed
  run command_exists php
  [ "$status" -eq 0 ]

  # Verify PHP version is 8.4 (default)
  run podman exec "$TEST_CONTAINER" php -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PHP 8.4" ]]

  # Verify PHP-FPM service exists (nginx enables FPM by default)
  run unit_exists "php8.4-fpm"
  [ "$status" -eq 0 ]
}

@test "install apache with php without fpm" {
  start_test_container

  # Run installation without FPM flag
  run exec_laemp -p -w apache -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Apache installed
  run command_exists apache2
  [ "$status" -eq 0 ]

  # Verify PHP installed
  run command_exists php
  [ "$status" -eq 0 ]

  # Verify PHP-FPM is NOT enabled (no -f flag)
  run unit_exists "php8.4-fpm"
  [ "$status" -ne 0 ]
}

@test "install apache with php with fpm" {
  start_test_container

  # Run installation with FPM flag
  run exec_laemp -p -w apache -f -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Apache installed
  run command_exists apache2
  [ "$status" -eq 0 ]

  # Verify PHP-FPM service exists
  run unit_exists "php8.4-fpm"
  [ "$status" -eq 0 ]
}

@test "install specific php version" {
  start_test_container

  # Install PHP 8.2
  run exec_laemp -p 8.2 -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify PHP 8.2 installed
  run podman exec "$TEST_CONTAINER" php -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "PHP 8.2" ]]
}

#
# Database Installation Tests
#

@test "install mysql database" {
  start_test_container

  # Run installation with MySQL
  run exec_laemp -p -w nginx -d mysql -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify MySQL installed
  run command_exists mysql
  [ "$status" -eq 0 ]

  # Verify MySQL service running
  run service_is_active mysql
  [ "$status" -eq 0 ]

  # Verify MySQL accepts connections
  run podman exec "$TEST_CONTAINER" mysql -e "SELECT 1"
  [ "$status" -eq 0 ]
}

@test "install postgresql database" {
  start_test_container

  # Run installation with PostgreSQL
  run exec_laemp -p -w nginx -d pgsql -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify PostgreSQL installed
  run command_exists psql
  [ "$status" -eq 0 ]

  # Verify PostgreSQL service running
  run service_is_active postgresql
  [ "$status" -eq 0 ]

  # Verify PostgreSQL accepts connections
  run podman exec "$TEST_CONTAINER" sudo -u postgres psql -c "SELECT 1"
  [ "$status" -eq 0 ]
}

#
# SSL Certificate Tests
#

@test "create self-signed certificate" {
  start_test_container

  # Run installation with self-signed certificate
  run exec_laemp -p -w nginx -S -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify certificate files created
  run file_exists "/etc/ssl/moodle.romn.co.crt"
  [ "$status" -eq 0 ] || file_exists "/etc/ssl/moodle.romn.co.cert"

  run file_exists "/etc/ssl/moodle.romn.co.key"
  [ "$status" -eq 0 ]

  # Verify certificate is valid
  run podman exec "$TEST_CONTAINER" openssl x509 -in /etc/ssl/moodle.romn.co.crt -noout -text
  [ "$status" -eq 0 ] || run podman exec "$TEST_CONTAINER" openssl x509 -in /etc/ssl/moodle.romn.co.cert -noout -text
  [ "$status" -eq 0 ]
}

#
# Moodle Installation Tests
#

@test "full moodle installation with nginx and mysql" {
  start_test_container

  # Run full Moodle installation (Moodle 5.1.0)
  run exec_laemp -p -w nginx -d mysql -m 501 -S -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Moodle directory exists
  run dir_exists "/var/www/html/moodle.romn.co"
  [ "$status" -eq 0 ]

  # Verify config.php created
  run file_exists "/var/www/html/moodle.romn.co/config.php"
  [ "$status" -eq 0 ]

  # Verify moodledata directory exists
  run dir_exists "/home/moodle/moodledata"
  [ "$status" -eq 0 ]

  # Verify moodledata has correct permissions
  run podman exec "$TEST_CONTAINER" stat -c %U /home/moodle/moodledata
  [ "$status" -eq 0 ]
  [[ "$output" =~ "www-data" ]] || [[ "$output" =~ "moodle" ]]

  # Verify MySQL database created
  run podman exec "$TEST_CONTAINER" mysql -e "SHOW DATABASES LIKE 'moodle'"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "moodle" ]]
}

@test "full moodle installation with apache and postgresql" {
  start_test_container

  # Run full Moodle installation with Apache and PostgreSQL (Moodle 5.1.0)
  run exec_laemp -p -w apache -f -d pgsql -m 501 -S -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Apache installed
  run command_exists apache2
  [ "$status" -eq 0 ]

  # Verify PostgreSQL database created
  run postgres_db_exists "moodle"
  [ "$status" -eq 0 ]

  # Verify Moodle files exist
  run file_exists "/var/www/html/moodle.romn.co/config.php"
  [ "$status" -eq 0 ]
}

@test "moodle installation creates vhost configuration" {
  start_test_container

  # Run Moodle installation (Moodle 5.1.0)
  run exec_laemp -p -w nginx -d mysql -m 501 -S -c
  [ "$status" -eq 0 ]

  # Verify Nginx vhost configuration created
  run file_exists "/etc/nginx/sites-available/moodle.romn.co"
  [ "$status" -eq 0 ]

  # Verify vhost is enabled
  run file_exists "/etc/nginx/sites-enabled/moodle.romn.co"
  [ "$status" -eq 0 ]

  # Verify configuration is valid
  run podman exec "$TEST_CONTAINER" nginx -t
  [ "$status" -eq 0 ]
}

@test "moodle installation with different version" {
  start_test_container

  # Install Moodle 5.0 (version 500)
  run exec_laemp -p 8.4 -w nginx -d mysql -m 500 -S -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Moodle directory exists
  run dir_exists "/var/www/html/moodle.romn.co"
  [ "$status" -eq 0 ]
}

#
# Monitoring Stack Tests
#

@test "install prometheus monitoring stack" {
  start_test_container

  # Run installation with Prometheus
  run exec_laemp -p -w nginx -r -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Prometheus binary installed
  run file_exists "/usr/local/bin/prometheus"
  [ "$status" -eq 0 ]

  # Verify node exporter installed
  run file_exists "/usr/local/bin/node_exporter"
  [ "$status" -eq 0 ]

  # Verify Prometheus configuration exists
  run file_exists "/etc/prometheus/prometheus.yml"
  [ "$status" -eq 0 ]
}

@test "prometheus exporters match web server type" {
  start_test_container

  # Install with Nginx
  run exec_laemp -p -w nginx -r -c
  [ "$status" -eq 0 ]

  # Verify Nginx exporter installed
  run file_exists "/usr/local/bin/nginx-prometheus-exporter"
  [ "$status" -eq 0 ]

  # Verify Apache exporter NOT installed
  run file_exists "/usr/local/bin/apache_exporter"
  [ "$status" -ne 0 ]
}

@test "install memcached" {
  start_test_container

  # Run installation with Memcached
  run exec_laemp -p -M -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify Memcached installed
  run command_exists memcached
  [ "$status" -eq 0 ]

  # Verify Memcached service exists
  run unit_exists "memcached"
  [ "$status" -eq 0 ]
}

#
# Configuration Verification Tests
#

@test "nginx configuration is optimized for moodle" {
  start_test_container

  run exec_laemp -p -w nginx -c
  [ "$status" -eq 0 ]

  # Verify nginx.conf exists
  run file_exists "/etc/nginx/nginx.conf"
  [ "$status" -eq 0 ]

  # Check for Moodle-specific optimizations
  run podman exec "$TEST_CONTAINER" grep -q "client_max_body_size" /etc/nginx/nginx.conf
  [ "$status" -eq 0 ]
}

@test "php configuration is optimized for moodle" {
  start_test_container

  run exec_laemp -p -w nginx -d mysql -m 501 -c
  [ "$status" -eq 0 ]

  # Check PHP FPM pool configuration
  run file_exists "/etc/php/8.4/fpm/pool.d/moodle.romn.co.conf"
  [ "$status" -eq 0 ]

  # Verify Moodle-specific PHP settings
  run podman exec "$TEST_CONTAINER" grep -q "max_input_vars" /etc/php/8.4/fpm/pool.d/moodle.romn.co.conf
  [ "$status" -eq 0 ]
}

@test "apache configuration includes ssl when certificate provided" {
  start_test_container

  run exec_laemp -p -w apache -S -c
  [ "$status" -eq 0 ]

  # Check Apache vhost configuration
  run file_exists "/etc/apache2/sites-available/moodle.romn.co.conf"
  [ "$status" -eq 0 ]

  # Verify SSL configuration present
  run podman exec "$TEST_CONTAINER" grep -q "SSLEngine on" /etc/apache2/sites-available/moodle.romn.co.conf
  [ "$status" -eq 0 ]
}

#
# Idempotency Tests
#

@test "running script twice with same options is idempotent" {
  start_test_container

  # First run
  run exec_laemp -p -w nginx -d mysql -c
  echo "First run output: $output"
  [ "$status" -eq 0 ]

  # Get checksums of key files
  local nginx_conf_1=$(get_file_checksum "/etc/nginx/nginx.conf")
  local php_version_1=$(podman exec "$TEST_CONTAINER" php -v | head -1)

  # Second run
  run exec_laemp -p -w nginx -d mysql -c
  echo "Second run output: $output"
  [ "$status" -eq 0 ]

  # Verify checksums unchanged
  local nginx_conf_2=$(get_file_checksum "/etc/nginx/nginx.conf")
  local php_version_2=$(podman exec "$TEST_CONTAINER" php -v | head -1)

  [ "$nginx_conf_1" = "$nginx_conf_2" ]
  [ "$php_version_1" = "$php_version_2" ]
}

@test "installing moodle twice does not break installation" {
  start_test_container

  # First Moodle installation
  run exec_laemp -p -w nginx -d mysql -m 501 -S -c
  [ "$status" -eq 0 ]

  # Verify config.php exists
  run file_exists "/var/www/html/moodle.romn.co/config.php"
  [ "$status" -eq 0 ]

  local config_checksum_1=$(get_file_checksum "/var/www/html/moodle.romn.co/config.php")

  # Second Moodle installation
  run exec_laemp -p -w nginx -d mysql -m 501 -S -c
  [ "$status" -eq 0 ]

  # Verify config.php still exists and unchanged
  local config_checksum_2=$(get_file_checksum "/var/www/html/moodle.romn.co/config.php")
  [ "$config_checksum_1" = "$config_checksum_2" ]
}

#
# Service Status Tests
#

@test "all services start successfully after nginx installation" {
  start_test_container

  run exec_laemp -p -w nginx -d mysql -c
  [ "$status" -eq 0 ]

  # Give services time to start
  sleep 5

  # Verify services are active
  run service_is_active nginx
  [ "$status" -eq 0 ]

  run service_is_active "php8.4-fpm"
  [ "$status" -eq 0 ]

  run service_is_active mysql
  [ "$status" -eq 0 ]
}

@test "all services start successfully after apache installation" {
  start_test_container

  run exec_laemp -p -w apache -f -d pgsql -c
  [ "$status" -eq 0 ]

  # Give services time to start
  sleep 5

  # Verify services are active
  run service_is_active apache2
  [ "$status" -eq 0 ]

  run service_is_active "php8.4-fpm"
  [ "$status" -eq 0 ]

  run service_is_active postgresql
  [ "$status" -eq 0 ]
}

#
# Error Handling Tests
#

@test "invalid database type produces error" {
  start_test_container

  # Try to install with invalid database type
  run exec_laemp -d invalid -c
  echo "Output: $output"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Unsupported database type" ]] || [[ "$output" =~ "invalid" ]]
}

@test "invalid web server type produces error" {
  start_test_container

  # Try to install with invalid web server type
  run exec_laemp -w invalid -c
  echo "Output: $output"
  [ "$status" -ne 0 ]
}

@test "dry run mode does not make changes" {
  start_test_container

  # Run in dry-run mode
  run exec_laemp -p -w nginx -d mysql -m -n -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify PHP not actually installed
  run command_exists php
  [ "$status" -ne 0 ]

  # Verify Nginx not actually installed
  run command_exists nginx
  [ "$status" -ne 0 ]
}

#
# Cross-Distribution Tests
#

@test "installation works on debian" {
  # Check if Debian image exists
  if ! podman image exists amp-moodle-debian:latest; then
    skip "Debian test image not found. Run: podman build -f Dockerfile.debian -t amp-moodle-debian ."
  fi

  start_test_container "amp-moodle-debian"

  # Run installation on Debian
  run exec_laemp -p -w nginx -d mysql -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify installation successful
  run command_exists nginx
  [ "$status" -eq 0 ]

  run command_exists php
  [ "$status" -eq 0 ]
}

#
# Combined Installation Tests
#

@test "full stack with all options" {
  start_test_container

  # Install complete stack: Nginx, PHP, MySQL, Moodle, SSL, Prometheus, Memcached
  run exec_laemp -p -w nginx -d mysql -m 501 -S -r -M -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify web server
  run command_exists nginx
  [ "$status" -eq 0 ]

  # Verify PHP
  run command_exists php
  [ "$status" -eq 0 ]

  # Verify database
  run command_exists mysql
  [ "$status" -eq 0 ]

  # Verify Moodle
  run file_exists "/var/www/html/moodle.romn.co/config.php"
  [ "$status" -eq 0 ]

  # Verify SSL certificate
  run file_exists "/etc/ssl/moodle.romn.co.crt"
  [ "$status" -eq 0 ] || file_exists "/etc/ssl/moodle.romn.co.cert"

  # Verify Prometheus
  run file_exists "/usr/local/bin/prometheus"
  [ "$status" -eq 0 ]

  # Verify Memcached
  run command_exists memcached
  [ "$status" -eq 0 ]
}

@test "php alongside installation" {
  start_test_container

  # Install PHP 8.4 first
  run exec_laemp -p 8.4 -c
  [ "$status" -eq 0 ]

  # Verify PHP 8.4 installed
  run podman exec "$TEST_CONTAINER" php8.4 -v
  [ "$status" -eq 0 ]

  # Install PHP 8.2 alongside
  run exec_laemp -P 8.2 -c
  [ "$status" -eq 0 ]

  # Verify both versions available
  run podman exec "$TEST_CONTAINER" php8.4 -v
  [ "$status" -eq 0 ]

  run podman exec "$TEST_CONTAINER" php8.2 -v
  [ "$status" -eq 0 ]
}

#
# Log File Tests
#

@test "script creates log files" {
  start_test_container

  run exec_laemp -p -c
  [ "$status" -eq 0 ]

  # Verify log directory created
  run dir_exists "/usr/local/bin/logs"
  [ "$status" -eq 0 ]

  # Verify log file created
  run count_log_files
  [ "$status" -eq 0 ]
  [[ "$output" -gt 0 ]]
}

@test "verbose mode produces detailed output" {
  start_test_container

  # Run with verbose flag
  run exec_laemp -p -v -c
  echo "Output: $output"
  [ "$status" -eq 0 ]

  # Verify verbose messages present
  [[ "$output" =~ "verbose" ]] || [[ "$output" =~ "Entered function" ]] || [[ "$output" =~ "Installing" ]]
}
