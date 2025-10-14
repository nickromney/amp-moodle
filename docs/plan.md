# Implementation Plan for Completing laemp.sh Moodle Installer

## Executive Summary

This document outlines the implementation plan to transform `laemp.sh` from a partially functional Moodle installer into a production-ready, fully-tested deployment tool. The script will remain as a single bash file while gaining complete functionality, comprehensive testing, and production-grade error handling.

## Current State Analysis

### What Works Well

- **Web Server Installation**: Both Apache and Nginx with optimized configurations
- **PHP Management**: Version-flexible installation with PHP-FPM pools and Moodle-specific tuning
- **Partial Moodle Setup**: Downloads source, creates directories, generates partial config.php
- **Monitoring Stack**: Complete Prometheus installation with multiple exporters
- **Utility Infrastructure**: Robust logging, dry-run mode, package management

### Critical Gaps

1. **No Database Installation**: Script accepts database config but never installs MySQL/PostgreSQL
2. **Broken SSL Integration**: Certificate paths hardcoded, no validation, ACME command has wrong flag
3. **Incomplete Moodle Setup**: Creates config.php but doesn't run CLI installer or populate database
4. **Limited Testing**: Only 8 BATS tests for CLI parsing, zero integration tests
5. **No Rollback**: Script exits on error with no cleanup or state tracking

## Implementation Phases

## Phase 1: Critical Missing Features (Priority 1 - Blocking)

### 1.1 Database Installation

**Location**: After line 1891 (after `memcached_ensure()`)

**New Functions**:

```bash
mysql_ensure() {
  # Install MySQL/MariaDB server
  # Create database and user
  # Configure for Moodle (innodb settings, character set)
  # Start and enable service
}

postgres_ensure() {
  # Install PostgreSQL server
  # Create database and user
  # Configure for Moodle (UTF-8 encoding)
  # Start and enable service
}
```

**Changes Required**:

- Add `MYSQL_ENSURE=false` and `POSTGRES_ENSURE=false` to defaults (line 21)
- Modify `-d` flag parsing to set appropriate database flag (line 2019)
- Call database function in `main()` before Moodle installation (line 1937)
- Generate secure random passwords for database users
- Add `database_verify()` function similar to `apache_verify()` pattern

**Testing**:

- Unit test: Verify `-d mysql` and `-d pgsql` flags parse correctly
- Integration test: Verify database service starts and accepts connections
- Integration test: Verify database and user created with correct permissions

### 1.2 Fix SSL Certificate Integration

**Changes Required**:

**a) Dynamic Certificate Paths in vhost_config** (lines 876-882):

```bash
# Instead of hardcoded /etc/letsencrypt paths:
declare -A vhost_config=(
  [ssl-cert-file]=$(get_cert_path "cert")
  [ssl-key-file]=$(get_cert_path "key")
)

# New helper function:
get_cert_path() {
  if $ACME_CERT; then
    echo "/etc/letsencrypt/live/${moodleSiteName}/$1"
  elif $SELF_SIGNED_CERT; then
    echo "/etc/ssl/${moodleSiteName}.$1"
  else
    log error "No certificate method specified"
    exit 1
  fi
}
```

**b) Certificate Validation** (before lines 890, 899):

```bash
validate_certificates() {
  local cert_file="$1"
  local key_file="$2"

  if [ ! -f "$cert_file" ]; then
    log error "Certificate file not found: $cert_file"
    exit 1
  fi

  if [ ! -f "$key_file" ]; then
    log error "Certificate key file not found: $key_file"
    exit 1
  fi
}
```

**c) Fix ACME Certbot Command** (line 478):

```bash
# Change --challenge to --preferred-challenges
run_command --makes-changes certbot --apache -d "${domain}" ${san_flag} \
  -m "${email}" --agree-tos --preferred-challenges "${challenge_type}" \
  --server "${provider}"
```

**d) Self-Signed Certificate Location** (line 1549):

```bash
# Move certificates to standard location
run_command --makes-changes mkdir -p /etc/ssl
run_command --makes-changes openssl req -x509 -nodes -days 365 \
  -newkey "rsa:2048" \
  -out "/etc/ssl/${domain}.cert" \
  -keyout "/etc/ssl/${domain}.key" \
  -subj "/CN=${domain}" \
  -addext "subjectAltName = DNS:${domain}, DNS:www.${domain}"
```

**Testing**:

- Unit test: Verify certificate path logic returns correct paths
- Integration test: Self-signed certificate generation creates valid certs
- Integration test: ACME certificate request succeeds in staging mode
- Integration test: Vhosts created with correct certificate paths

### 1.3 Complete Moodle Installation

**Location**: In `moodle_ensure()` after line 874

**New Code**:

```bash
moodle_install_database() {
  log verbose "Running Moodle CLI installation"

  # Check if already installed
  if php "${moodleDir}/admin/cli/check_database_schema.php" 2>/dev/null | grep -q "Installation completed"; then
    log verbose "Moodle already installed, skipping CLI installation"
    return 0
  fi

  # Run installation
  run_command --makes-changes php "${moodleDir}/admin/cli/install_database.php" \
    --lang=en \
    --adminuser=admin \
    --adminpass="$(generate_password)" \
    --adminemail="admin@${moodleSiteName}" \
    --fullname="${moodleSiteName}" \
    --shortname="${moodleSiteName}" \
    --agree-license

  # Set up cron
  setup_moodle_cron
}

setup_moodle_cron() {
  log verbose "Setting up Moodle cron job"

  local cron_command="*/5 * * * * php ${moodleDir}/admin/cli/cron.php"

  # Add to www-data crontab if not exists
  if ! crontab -u "${webserverUser}" -l 2>/dev/null | grep -q "cli/cron.php"; then
    (crontab -u "${webserverUser}" -l 2>/dev/null; echo "$cron_command") | \
      crontab -u "${webserverUser}" -
  fi
}

generate_password() {
  # Generate secure 16-character password
  openssl rand -base64 12 | tr -d "=+/" | cut -c1-16
}
```

**Memcached Configuration** (line 700, after dataroot):

```bash
# Add memcached configuration if enabled
if $MEMCACHED_ENSURE; then
  # Add before require_once line
  sed -i "/require_once(__DIR__ . '\\/lib\\/setup.php');/i\\\n\\\n\
// Memcached session storage\\n\
\\\$CFG->session_handler_class = '\\\\core\\\\session\\\\memcached';\\n\
\\\$CFG->session_memcached_save_path = '127.0.0.1:11211';\\n\
\\\$CFG->session_memcached_prefix = 'memc.sess.key.';\\n\
\\\$CFG->session_memcached_acquire_lock_timeout = 120;\\n\
\\\$CFG->session_memcached_lock_expire = 7200;\\n" "$configFile"

  log verbose "Added Memcached configuration to config.php"
fi
```

**Testing**:

- Integration test: Verify Moodle database tables created
- Integration test: Verify admin user can log in
- Integration test: Verify cron job added to www-data crontab
- Integration test: Verify Moodle accessible via web browser
- Integration test: Verify memcached configuration when -M flag used

## Phase 2: Comprehensive BATS Testing

### 2.1 Update Unit Tests (test_laemp.bats)

**Current Issues**:

- Tests expect "Options chosen:" output that doesn't exist
- Tests reference old `-a` flag for Apache (now `-w apache`)
- No tests for new database flags

**New Tests Needed**:

```bash
# Database flag tests
@test "-d mysql flag" {
  run ./laemp.sh -d mysql -n -v
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to mysql" ]]
}

@test "-d pgsql flag" {
  run ./laemp.sh -d pgsql -n -v
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to pgsql" ]]
}

# Web server flag tests
@test "-w apache flag" {
  run ./laemp.sh -w apache -n -v
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
}

@test "-w nginx flag" {
  run ./laemp.sh -w nginx -n -v
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
}

# Certificate flag tests
@test "-S self-signed flag" {
  run ./laemp.sh -S -n -v
  [ $status -eq 0 ]
}

@test "-a acme-cert flag" {
  run ./laemp.sh -a -n -v
  [ $status -eq 0 ]
}

# Combined flags tests
@test "full stack with mysql" {
  run ./laemp.sh -p -w nginx -d mysql -m -S -n -v
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to mysql" ]]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure Moodle" ]]
}

# Error condition tests
@test "invalid database type" {
  run ./laemp.sh -d invalid
  [ $status -eq 1 ]
  [[ "$output" =~ "Unsupported database type" ]]
}

@test "invalid web server type" {
  run ./laemp.sh -w invalid
  [ $status -eq 1 ]
  [[ "$output" =~ "Unsupported web server type" ]]
}

@test "-f without -w should fail" {
  run ./laemp.sh -f
  [ $status -eq 1 ]
  [[ "$output" =~ "Option -f requires" ]]
}
```

### 2.2 Add Integration Tests (test_integration.bats)

**New File**: `test_integration.bats`

```bash
#!/usr/bin/env bats

# Integration tests that run full installations in containers
# These tests are slow but verify end-to-end functionality

setup() {
  # Start fresh Ubuntu container
  export TEST_CONTAINER=$(podman run -d --platform linux/amd64 \
    --name laemp-test-$(date +%s) \
    amp-moodle-ubuntu sleep infinity)

  # Copy script into container
  podman cp laemp.sh $TEST_CONTAINER:/usr/local/bin/
}

teardown() {
  # Clean up container
  podman rm -f $TEST_CONTAINER
}

@test "install nginx with php and mysql" {
  podman exec $TEST_CONTAINER sudo laemp.sh -p -w nginx -d mysql

  # Verify Nginx installed
  podman exec $TEST_CONTAINER nginx -v

  # Verify PHP installed
  podman exec $TEST_CONTAINER php -v

  # Verify MySQL installed
  podman exec $TEST_CONTAINER mysql --version

  # Verify services running
  podman exec $TEST_CONTAINER systemctl is-active nginx
  podman exec $TEST_CONTAINER systemctl is-active php8.3-fpm
  podman exec $TEST_CONTAINER systemctl is-active mysql
}

@test "install apache with php and postgresql" {
  podman exec $TEST_CONTAINER sudo laemp.sh -p -w apache -f -d pgsql

  # Verify Apache installed
  podman exec $TEST_CONTAINER apache2 -v

  # Verify PostgreSQL installed
  podman exec $TEST_CONTAINER psql --version

  # Verify services running
  podman exec $TEST_CONTAINER systemctl is-active apache2
  podman exec $TEST_CONTAINER systemctl is-active postgresql
}

@test "full moodle installation with nginx" {
  podman exec $TEST_CONTAINER sudo laemp.sh \
    -p -w nginx -d mysql -m 405 -S

  # Verify Moodle files exist
  podman exec $TEST_CONTAINER test -f /var/www/html/moodle.romn.co/config.php
  podman exec $TEST_CONTAINER test -d /home/moodle/moodledata

  # Verify database exists
  podman exec $TEST_CONTAINER mysql -e "SHOW DATABASES" | grep moodle

  # Verify web server responds
  podman exec $TEST_CONTAINER curl -k https://127.0.0.1 | grep -i moodle
}

@test "idempotency - run twice produces no changes" {
  # First run
  podman exec $TEST_CONTAINER sudo laemp.sh -p -w nginx -d mysql

  # Get state checksums
  local php_version_1=$(podman exec $TEST_CONTAINER php -v)
  local packages_1=$(podman exec $TEST_CONTAINER dpkg -l | md5sum)

  # Second run
  podman exec $TEST_CONTAINER sudo laemp.sh -p -w nginx -d mysql

  # Verify state unchanged
  local php_version_2=$(podman exec $TEST_CONTAINER php -v)
  local packages_2=$(podman exec $TEST_CONTAINER dpkg -l | md5sum)

  [ "$php_version_1" = "$php_version_2" ]
  [ "$packages_1" = "$packages_2" ]
}

@test "prometheus monitoring stack installation" {
  podman exec $TEST_CONTAINER sudo laemp.sh -p -w nginx -r

  # Verify Prometheus installed
  podman exec $TEST_CONTAINER test -f /usr/local/bin/prometheus

  # Verify exporters installed
  podman exec $TEST_CONTAINER test -f /usr/local/bin/node_exporter
  podman exec $TEST_CONTAINER test -f /usr/local/bin/nginx-prometheus-exporter

  # Verify services running
  podman exec $TEST_CONTAINER systemctl is-active prometheus
  podman exec $TEST_CONTAINER systemctl is-active node_exporter
}
```

### 2.3 Add Smoke Tests (test_smoke.bats)

**New File**: `test_smoke.bats`

```bash
#!/usr/bin/env bats

# Quick smoke tests for critical functionality
# These should run fast and catch obvious breakages

@test "script has correct shebang" {
  head -n 1 laemp.sh | grep "#!/usr/bin/env bash"
}

@test "script is executable" {
  [ -x laemp.sh ]
}

@test "help option works" {
  run ./laemp.sh -h
  [ $status -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "all functions have verbose logging entry" {
  # Every function should log on entry
  local functions=$(grep -E "^function |^[a-z_]+\(\) \{" laemp.sh | wc -l)
  local log_entries=$(grep 'log verbose "Entered function' laemp.sh | wc -l)

  # Allow some utility functions to not log
  [ $log_entries -gt $((functions - 10)) ]
}

@test "no bashisms (script is portable bash)" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  shellcheck -s bash laemp.sh
}

@test "all TODOs are documented" {
  # If there are TODOs, they should be in known locations
  if grep -q "TODO" laemp.sh; then
    grep "TODO" laemp.sh | grep -E "(line 2232|line 2233)"
  fi
}
```

### 2.4 Testing Infrastructure Updates

**Update Makefile**:

```makefile
# Add new test targets
.PHONY: test-unit
test-unit: ## Run unit tests only
 @echo "$(YELLOW)Running BATS unit tests...$(NC)"
 @bats test_laemp.bats

.PHONY: test-integration
test-integration: ## Run integration tests (requires Podman)
 @echo "$(YELLOW)Running integration tests...$(NC)"
 @echo "$(YELLOW)Building test containers...$(NC)"
 @podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu .
 @podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian .
 @bats test_integration.bats

.PHONY: test-smoke
test-smoke: ## Run quick smoke tests
 @echo "$(YELLOW)Running smoke tests...$(NC)"
 @bats test_smoke.bats

.PHONY: test
test: test-smoke test-unit test-integration ## Run all tests
 @echo "$(GREEN)✓ All tests passed$(NC)"
```

**Update Dockerfiles**:

- Add systemd support for service testing
- Add networking for web server tests
- Add volume mounts for test artifacts

## Phase 3: Production Hardening

### 3.1 Error Handling & Rollback

**State Tracking** (new file location: `/var/lib/laemp/state.json`):

```bash
STATE_FILE="/var/lib/laemp/state.json"

state_init() {
  mkdir -p "$(dirname "$STATE_FILE")"
  echo '{"version": "1.0", "steps": {}}' > "$STATE_FILE"
}

state_set() {
  local step="$1"
  local status="$2"  # started, completed, failed

  # Update state file with jq if available, otherwise use sed
  if command -v jq >/dev/null; then
    tmp=$(mktemp)
    jq ".steps[\"$step\"] = \"$status\"" "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
  fi
}

state_get() {
  local step="$1"

  if command -v jq >/dev/null; then
    jq -r ".steps[\"$step\"] // \"not_started\"" "$STATE_FILE"
  else
    echo "not_started"
  fi
}

# Usage in functions:
php_ensure() {
  if [ "$(state_get "php_install")" = "completed" ]; then
    log verbose "PHP already installed (per state file)"
    return 0
  fi

  state_set "php_install" "started"

  # ... installation logic ...

  state_set "php_install" "completed"
}
```

**Backup Before Modify**:

```bash
backup_file() {
  local file="$1"
  local backup="${file}.bak.$(date +%s)"

  if [ -f "$file" ]; then
    run_command --makes-changes cp "$file" "$backup"
    log verbose "Backed up $file to $backup"
  fi
}

# Usage:
nginx_create_optimized_config() {
  backup_file "/etc/nginx/nginx.conf"

  # ... create new config ...

  # Validate before committing
  if ! nginx -t; then
    log error "New config invalid, restoring backup"
    restore_latest_backup "/etc/nginx/nginx.conf"
    exit 1
  fi
}

restore_latest_backup() {
  local file="$1"
  local backup=$(ls -t "${file}.bak."* 2>/dev/null | head -1)

  if [ -n "$backup" ]; then
    run_command --makes-changes cp "$backup" "$file"
    log info "Restored $file from $backup"
  fi
}
```

**Cleanup on Exit**:

```bash
cleanup() {
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log error "Script failed with exit code $exit_code"
    log info "Cleanup actions..."

    # Stop services that were started this run
    if [ "$(state_get "nginx_started")" = "true" ]; then
      systemctl stop nginx
    fi

    # Remove incomplete installations
    if [ "$(state_get "moodle_install")" = "started" ]; then
      log warning "Moodle installation incomplete, consider removing ${moodleDir}"
    fi
  fi
}

trap cleanup EXIT
```

### 3.2 Input Validation

**New Validation Functions**:

```bash
validate_domain() {
  local domain="$1"

  # Basic domain validation regex
  if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    log error "Invalid domain name: $domain"
    return 1
  fi
}

validate_email() {
  local email="$1"

  if ! [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log error "Invalid email address: $email"
    return 1
  fi
}

validate_version() {
  local version="$1"

  # Moodle version should be 3 digits (405, 500, etc.)
  if ! [[ "$version" =~ ^[0-9]{3}$ ]]; then
    log error "Invalid Moodle version format: $version (expected 3 digits like 405 or 500)"
    return 1
  fi
}

check_prerequisites() {
  log verbose "Checking prerequisites..."

  # Check disk space (need at least 2GB free)
  local free_space=$(df /var | tail -1 | awk '{print $4}')
  if [ "$free_space" -lt 2097152 ]; then  # 2GB in KB
    log error "Insufficient disk space in /var (need 2GB, have $(($free_space/1024))MB)"
    exit 1
  fi

  # Check memory (need at least 1GB)
  local free_mem=$(free -m | grep Mem | awk '{print $7}')
  if [ "$free_mem" -lt 1024 ]; then
    log warning "Low available memory: ${free_mem}MB (recommended: 1GB+)"
  fi

  # Check network connectivity
  if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    log error "No network connectivity detected"
    exit 1
  fi
}

# Add to main():
main() {
  check_prerequisites
  validate_domain "$moodleSiteName"

  # ... rest of main logic ...
}
```

### 3.3 Post-Installation Verification

**New Function**: `verify_installation()`

```bash
verify_installation() {
  log info "Running post-installation verification..."

  local errors=0

  # Verify web server
  if $NGINX_ENSURE; then
    if ! systemctl is-active nginx >/dev/null; then
      log error "Nginx service not running"
      ((errors++))
    fi

    if ! nginx -t 2>/dev/null; then
      log error "Nginx configuration has errors"
      ((errors++))
    fi
  fi

  if $APACHE_ENSURE; then
    if ! systemctl is-active apache2 >/dev/null; then
      log error "Apache service not running"
      ((errors++))
    fi
  fi

  # Verify PHP
  if ! php -v >/dev/null 2>&1; then
    log error "PHP not functional"
    ((errors++))
  fi

  if $FPM_ENSURE; then
    if ! systemctl is-active "php${PHP_VERSION_MAJOR_MINOR}-fpm" >/dev/null; then
      log error "PHP-FPM service not running"
      ((errors++))
    fi
  fi

  # Verify database
  if [ "$DB_TYPE" = "mysql" ]; then
    if ! mysql -e "SELECT 1" >/dev/null 2>&1; then
      log error "MySQL not functional"
      ((errors++))
    fi

    if ! mysql -e "SHOW DATABASES" | grep -q "$DB_NAME"; then
      log error "Moodle database not created"
      ((errors++))
    fi
  elif [ "$DB_TYPE" = "pgsql" ]; then
    if ! sudo -u postgres psql -c "SELECT 1" >/dev/null 2>&1; then
      log error "PostgreSQL not functional"
      ((errors++))
    fi
  fi

  # Verify Moodle
  if $MOODLE_ENSURE; then
    if [ ! -f "${moodleDir}/config.php" ]; then
      log error "Moodle config.php not found"
      ((errors++))
    fi

    if [ ! -d "$moodleDataDir" ]; then
      log error "Moodle data directory not found"
      ((errors++))
    fi

    # Test web access
    local url="https://${moodleSiteName}"
    if ! curl -k -s "$url" | grep -q "Moodle"; then
      log warning "Cannot access Moodle at $url"
      ((errors++))
    fi

    # Check cron job
    if ! crontab -u "$webserverUser" -l 2>/dev/null | grep -q "cli/cron.php"; then
      log warning "Moodle cron job not configured"
      ((errors++))
    fi
  fi

  # Verify SSL certificates
  if $ACME_CERT || $SELF_SIGNED_CERT; then
    local cert_path=$(get_cert_path "cert")

    if [ ! -f "$cert_path" ]; then
      log error "SSL certificate not found at $cert_path"
      ((errors++))
    else
      # Check certificate validity
      if ! openssl x509 -in "$cert_path" -noout -checkend 0 >/dev/null 2>&1; then
        log error "SSL certificate is expired or invalid"
        ((errors++))
      fi
    fi
  fi

  # Summary
  if [ $errors -eq 0 ]; then
    log info "✓ All verification checks passed!"
    log info "Moodle is accessible at: https://${moodleSiteName}"
    return 0
  else
    log error "✗ $errors verification check(s) failed"
    log info "Check logs at: $LOG_FILE"
    return 1
  fi
}

# Call at end of main():
main() {
  # ... all installation logic ...

  verify_installation
}
```

## Phase 4: Documentation & Refinement

### 4.1 Update CLAUDE.md

**Changes Needed**:

- Update "Important Considerations" with new database support
- Add section on state tracking and rollback
- Document new testing infrastructure
- Update line numbers for all functions after insertions
- Add troubleshooting section with common issues
- Document verification procedures

### 4.2 Create docs/ansible-rewrite.md

This document will be created showing how to achieve the same functionality using Ansible, based on the patterns from ansible-role-moodle and Jeff Geerling's roles.

### 4.3 Testing Documentation

**New Section in README.md**:

```markdown
## Testing

### Unit Tests
```bash
make test-unit
```

Runs BATS unit tests for command-line parsing and basic functionality.

### Integration Tests

```bash
make test-integration
```

Runs full installation tests in Podman containers. Tests both Ubuntu and Debian.

### Smoke Tests

```bash
make test-smoke
```

Quick validation tests that run in seconds.

### Manual Testing

```bash
# Build test container
podman build -f Dockerfile.ubuntu -t amp-moodle-ubuntu .

# Run interactive test
podman run -it --platform linux/amd64 amp-moodle-ubuntu

# Inside container:
sudo laemp.sh -p -w nginx -d mysql -m 405 -S
```

## Implementation Order

1. **Phase 1.1**: Database installation (mysql_ensure, postgres_ensure)
2. **Phase 1.2**: Fix SSL certificate integration
3. **Phase 1.3**: Complete Moodle installation
4. **Phase 2.1**: Update unit tests
5. **Phase 2.2**: Add integration tests
6. **Phase 2.3**: Add smoke tests
7. **Phase 3**: Production hardening (parallel with testing)
8. **Phase 4**: Documentation updates

## Success Criteria

- [ ] Single command installs complete LAMP/LEMP + Moodle stack
- [ ] All BATS tests pass (unit, integration, smoke)
- [ ] Script is idempotent (safe to run multiple times)
- [ ] Moodle accessible via HTTPS with valid certificates
- [ ] Database properly configured and functional
- [ ] All services start on boot
- [ ] Comprehensive error handling with rollback
- [ ] Complete documentation with examples
- [ ] State tracking enables resume after failure

## Estimated Effort

- Phase 1: 8-12 hours (core functionality)
- Phase 2: 6-10 hours (testing infrastructure)
- Phase 3: 6-8 hours (hardening)
- Phase 4: 4-6 hours (documentation)

### Total: 24-36 hours of development time

## Risk Mitigation

1. **Breaking changes**: Maintain backward compatibility with existing flags
2. **Platform differences**: Test on both Ubuntu 22.04 and Debian 11
3. **Database security**: Generate secure passwords, document storage
4. **Certificate expiry**: Document renewal procedures for both ACME and self-signed
5. **State file corruption**: Use JSON with fallback to simple key-value parsing
