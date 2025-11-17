# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a bash automation script (`laemp.sh`) that installs LAMP/LEMP stack on Ubuntu/Debian systems with optional Moodle LMS deployment. The script supports multiple PHP versions (default: 8.4), both Apache and Nginx web servers, SSL certificates, database configurations, and Prometheus monitoring.

**Current Status**: The bash script is production-ready. An Ansible rewrite is in progress (`ansible/` directory) to provide an IaC alternative with the same functionality.

## Development Commands

### Running Tests

```bash
# Run BATS test suite (command-line option parsing tests)
make test  # or: bats test_laemp.bats

# Run pre-commit hooks (includes shellcheck, gitleaks, markdownlint)
make precommit

# Install pre-commit hooks
make precommit-install
```

### Linting and Formatting

```bash
# Run shellcheck on bash scripts
make lint  # or: shellcheck laemp.sh setup-security.sh

# Format all code
make fmt

# Run security scans
make gitleaks          # Scan for secrets
make gitleaks-protect  # Check staged files only
```

### Local Testing with Podman (macOS)

```bash
# Install Podman
brew install podman podman-compose
podman machine init
podman machine start
```

#### Two Testing Scenarios

This project provides **two types of Docker images** for different testing scenarios:

**1. Stock Images (Full Bootstrap Testing)**
Tests laemp.sh's ability to bootstrap a system from bare Ubuntu/Debian:

```bash
# Build stock images
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .

# Test full bootstrap (installs all packages + configuration)
podman run -it amp-moodle-ubuntu:24.04
sudo laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S
# Duration: ~5-10 minutes
```

**2. Prerequisite Images (Last Mile Testing)**
Tests laemp.sh's configuration logic with packages pre-installed:

```bash
# Build prereqs images (PHP 8.4, Nginx, MariaDB pre-installed)
podman build --platform linux/amd64 -f Dockerfile.prereqs.ubuntu -t amp-moodle-prereqs-ubuntu .
podman build --platform linux/amd64 -f Dockerfile.prereqs.debian -t amp-moodle-prereqs-debian .

# Test last mile configuration only (skips package installation)
podman run -it amp-moodle-prereqs-ubuntu
sudo laemp.sh -c -m 501 -S -w nginx -d mariadb  # Note: no -p flag
# Duration: ~2-3 minutes
```

**When to use each:**

- **Stock images**: Verify package installation, test repository setup, production scenarios
- **Prereqs images**: Fast iteration on configuration, CI/CD pipelines, development workflow

See `docs/dockerfile-prereqs.md` for detailed explanation of both scenarios.

### Container Testing with compose.yml

The project includes a `compose.yml` (Podman Compose) that orchestrates multi-container testing:

```bash
# Start persistent Debian container (idempotent - won't destroy existing)
make debian
# Then run: podman-compose exec moodle-test-debian sudo /usr/local/bin/laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S

# Start persistent Ubuntu container
make ubuntu
# Then run: podman-compose exec moodle-test-ubuntu sudo /usr/local/bin/laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S

# Destroy and recreate for clean slate testing
make debian-clean  # or make ubuntu-clean
```

The compose setup includes:
- Separate PostgreSQL database container (`postgres-db`) with health checks
- Systemd-enabled Debian/Ubuntu containers for realistic service management
- Port mappings: 8443 (Debian), 9443 (Ubuntu) for HTTPS access
- Volume mounts for persistent testing

### Makefile Targets

The Makefile is designed for a polyglot repository but includes useful targets for this bash project:

- `make help` - Show all available targets
- `make test` - Run BATS test suite
- `make precommit` - Run all pre-commit hooks on all files
- `make precommit-install` - Install pre-commit hooks
- `make lint` - Run shellcheck on bash scripts
- `make security-setup` - Install security tooling (macOS only)
- `make debian` / `make ubuntu` - Start Podman test containers (idempotent)
- `make debian-clean` / `make ubuntu-clean` - Destroy and recreate containers

## Script Architecture

The `laemp.sh` script (2,731 lines) is structured as follows:

### 1. Configuration Section (lines 1-75)

- Default variables for PHP (8.4), Moodle (4.5/405), database settings
- Database installation flags: `MYSQL_ENSURE` (line 28), `POSTGRES_ENSURE` (line 29)
- Locale setup for UTF-8 (`en_US.UTF-8`)
- Error handling with `set -euo pipefail`
- Directory paths and user configuration

### 2. Utility Functions (lines 76-403)

- **`log()`** (line 112): Multi-level logging (error/info/verbose/debug) with file output
- **`run_command()`** (line 349): Wrapper for executing commands, respects dry-run mode
- **`package_ensure()`** (line 233): Ensures packages are installed via apt
- **`repository_ensure()`** (line 279): Adds apt repositories
- **`tool_exists()`** (line 208): Check if command is available

### 3. SSL Certificate Functions (lines 404-559)

- **`get_cert_path()`** (line 419): Returns correct certificate paths dynamically based on certificate type
- **`validate_certificates()`** (line 467): Validates certificate files exist before vhost creation
- **`acme_cert_request()`** (line 506): Request Let's Encrypt certificates via certbot (FIXED: uses `--preferred-challenges` and `--non-interactive`)
- **`self_signed_cert_request()`** (line 1716): Generate self-signed certificates (FIXED: creates in `/etc/ssl/` not current directory)

### 4. Web Server Functions (lines 481-1286)

- **`apache_ensure()`** (line 513): Install and configure Apache
- **`apache_create_vhost()`** (line 576): Generate Apache virtual host configs
- **`nginx_ensure()`** (line 1145): Install and configure Nginx
- **`nginx_create_vhost()`** (line 1190): Generate Nginx server blocks
- **`nginx_create_optimized_config()`** (line 942): Create performance-tuned nginx.conf

### 5. PHP Functions (lines 1287-1514)

- **`php_ensure()`** (line 1342): Install PHP and extensions (curl, gd, intl, mbstring, soap, xml, zip, sodium, opcache, ldap)
- **`php_configure_for_moodle()`** (line 1409): Set Moodle-specific PHP settings (max_input_vars=5000, memory_limit=256M)
- **`php_fpm_create_pool()`** (line 1446): Create dedicated PHP-FPM pools with per-site configuration
- **`php_extensions_ensure()`** (line 1395): Install required PHP extensions

### 6. Moodle Functions (lines 644-1125)

- **`moodle_validate_php_version()`** (line 1005): Check PHP version compatibility using October 2025 matrix (3.11-5.1 supported)
- **`moodle_download_extract()`** (line 746): Download and extract Moodle from official source
- **`moodle_configure_directories()`** (line 728): Set up moodledata directory with correct permissions
- **`moodle_config_files()`** (line 675): Generate config.php with database settings and Memcached configuration (NEW: lines 814-830)
- **`generate_password()`** (line 896): Generates secure random passwords using openssl
- **`moodle_install_database()`** (line 905): Runs Moodle CLI installer to create database schema and admin user
- **`setup_moodle_cron()`** (line 951): Sets up cron job for www-data user (runs every 5 minutes)
- **`moodle_ensure()`** (line 996): Main Moodle installation orchestrator with complete installation flow

### 7. Memcached and Caching Functions (lines 1126-1144)

- **`memcached_ensure()`** (line 1126): Install and configure Memcached server
- Automatically integrated into Moodle config when `-M` flag used

### 8. Database Functions (lines 2130-2358) **NEW**

- **`mysql_verify()`** (line 2130): Verifies MySQL/MariaDB installation and service status
- **`mysql_ensure()`** (line 2164): Installs MariaDB with secure password generation, creates UTF-8 database with InnoDB configuration
- **`postgres_verify()`** (line 2236): Verifies PostgreSQL installation and service status
- **`postgres_ensure()`** (line 2270): Installs PostgreSQL 16 from official repository, creates UTF-8 database with proper collation

### 9. Monitoring Functions (lines 1560-1870)

- **`prometheus_ensure()`** (line 1560): Install Prometheus time-series database
- **`prometheus_install_node_exporter()`** (line 1672): System metrics exporter
- **`prometheus_install_apache_exporter()`** (line 1710): Apache metrics
- **`prometheus_install_nginx_exporter()`** (line 1763): Nginx metrics
- **`prometheus_install_phpfpm_exporter()`** (line 1818): PHP-FPM metrics

### 10. Main Entry Point (lines 2360-2731)

- **`main()`** (line 2360): Command-line argument parsing with getopt, orchestrates installation flow
- **`detect_distro_and_codename()`** (line 1952): Detect Ubuntu/Debian distribution
- Database flag parsing (lines 2486-2514): Sets `MYSQL_ENSURE` or `POSTGRES_ENSURE` based on `-d` argument

## Key Command-Line Options

```bash
# Web server and PHP
-w, --web [apache|nginx]  # Default: nginx
-p, --php [version]       # Default: 8.4
-P, --php-alongside       # Install additional PHP version
-f, --fpm                 # Enable PHP-FPM (automatic with nginx)

# Moodle and database
-m, --moodle [version]    # Install Moodle (405 for 4.5, 500 for 5.0, 501 for 5.1) - NOW COMPLETE: installs DB schema + admin
-d, --database [type]     # Database type (mysql/pgsql) - NOW FUNCTIONAL: actually installs database server

# SSL certificates
-a, --acme-cert           # Request Let's Encrypt certificate - FIXED: correct certbot flags
-S, --self-signed         # Create self-signed certificate - FIXED: creates in /etc/ssl/

# Monitoring and caching
-r, --prometheus          # Install Prometheus monitoring stack
-M, --memcached           # Install Memcached - NOW CONFIGURES: Moodle session storage

# Script behavior
-n, --nop                 # Dry run (show commands without executing)
-v, --verbose             # Verbose output
-c, --ci                  # CI mode (non-interactive)
-s, --sudo                # Use sudo for commands
-h, --help                # Show help
```

## Architecture Patterns

### 1. Dry Run Mode

All state-changing operations go through `run_command()` which checks `DRY_RUN_CHANGES` flag. This allows safe testing with `-n` flag.

### 2. Logging System

Four log levels (error/info/verbose/debug) with file output to `logs/` directory. Each run creates timestamped log file.

### 3. Package Management

- Uses `package_ensure()` to check if packages are installed before attempting installation
- Adds ondrej/php PPA for latest PHP versions
- Supports both apt-get and apt package managers

### 4. PHP-FPM Pools

Creates dedicated pools per Moodle site with:

- Separate user permissions
- Moodle-specific settings (max_input_vars=5000, memory_limit=256M)
- Security restrictions (open_basedir)
- Dedicated session and log directories

### 5. Monitoring Stack

When `-r` flag is used:

- Prometheus scrapes metrics from all exporters
- Exporters run as systemd services
- Accessible at: <http://server:9090> (Prometheus UI)
- Individual exporters: :9100 (node), :9113 (nginx), :9117 (apache), :9253 (php-fpm)

### 6. Database Installation (NEW)

When `-d mysql` or `-d pgsql` flag is used:

- Automatically installs and configures database server
- Generates secure random password using openssl
- Creates Moodle database with proper encoding:
  - MySQL: utf8mb4 with InnoDB configuration
  - PostgreSQL: UTF-8 with proper collation
- Stores credentials in `/tmp/` with 600 permissions
- Idempotent: checks if database exists before creation

### 7. Complete Moodle Installation (ENHANCED)

The script now performs complete Moodle installation:

- Downloads and extracts Moodle source code
- Creates config.php with database connection
- Runs CLI installer to create database schema
- Creates admin user with secure generated password
- Sets up cron job for automated maintenance (every 5 minutes)
- Configures Memcached for session storage (when `-M` flag used)
- Displays admin credentials at completion

## Important Considerations

1. **Platform Restriction**: Script only works on Ubuntu/Debian. Exits with error on other distributions (`detect_distro_and_codename()` checks `/etc/os-release`).

2. **Error Handling**: Uses `set -euo pipefail` for strict error handling. Any command failure stops execution immediately.

3. **PHP Version Validation**: Script validates PHP/Moodle compatibility using October 2025 matrix:
   - Moodle 5.1+: PHP 8.2, 8.4, 8.4 (minimum: 8.2)
   - Moodle 5.0: PHP 8.2, 8.4, 8.4 (minimum: 8.2)
   - Moodle 4.4-4.5: PHP 8.1, 8.2, 8.4 (minimum: 8.1)
   - Moodle 4.2-4.3: PHP 8.0, 8.1, 8.2 (minimum: 8.0)
   - Moodle 4.1: PHP 7.4, 8.0, 8.1 (minimum: 7.4)
   - Moodle 4.0: PHP 7.3, 7.4, 8.0 (minimum: 7.3)
   - Moodle 3.11: PHP 7.3, 7.4, 8.0 (minimum: 7.3)

4. **Web Server Defaults**:
   - Nginx is default web server with PHP-FPM enabled automatically
   - Apache requires explicit `-f` flag to enable FPM
   - Both create optimized configurations for Moodle

5. **SSL Certificate Management**:
   - ACME uses HTTP-01 challenge with certbot (`--preferred-challenges http`)
   - Self-signed certificates valid for 365 days
   - Certificates stored in `/etc/ssl/` (self-signed) or `/etc/letsencrypt/live/` (ACME)
   - Dynamic certificate path resolution via `get_cert_path()` function
   - Pre-flight validation before vhost creation

6. **Database Requirements**: When using `-m` (Moodle), you MUST specify `-d mysql` or `-d pgsql`. The script will install the database server automatically.

7. **Service Management**: All services managed via `systemctl`. Script automatically enables services to start on boot.

8. **Idempotency**: Script is safe to run multiple times. All functions check if resources exist before creating them.

## Testing

The project includes three comprehensive test suites (70 total tests):

### 1. Unit Tests (`test_laemp.bats` - 29 tests)

Tests command-line option parsing and flag combinations:

```bash
bats test_laemp.bats
```

- Web server flags (`-w apache`, `-w nginx`)
- Database flags (`-d mysql`, `-d pgsql`)
- PHP version flags (`-p`, `-P`)
- SSL certificate flags (`-S`, `-a`)
- Monitoring and caching flags (`-r`, `-M`)
- Error conditions and invalid options

### 2. Integration Tests (`test_integration.bats` - 29 tests)

Tests full installation in Podman containers (Ubuntu 24.04 LTS, Debian 13):

```bash
# Build test containers first
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian .

# Run integration tests (see docs/container-testing.md for detailed guide)
bats test_integration.bats
```

Test categories:

- Basic installations (nginx/apache with PHP)
- Database installations (MySQL/PostgreSQL)
- SSL certificate creation
- Full Moodle installations (with database)
- Monitoring stack installation
- Configuration file verification
- Idempotency (running script twice)
- Service status verification
- Error handling
- Cross-distribution testing (Ubuntu 24.04/Debian 13)

### 3. Smoke Tests (`test_smoke.bats` - 12 tests)

Fast validation checks (< 1 second each):

```bash
bats test_smoke.bats
```

- Script validity (shebang, executable, syntax)
- Help functionality
- Function logging verification
- Shellcheck validation
- Basic structural checks

### Running All Tests

```bash
# Run all test suites
make test

# Run with verbose output
bats -p test_*.bats
```

### Podman Testing Notes

- Use Ubuntu 24.04 LTS (Noble Numbat) / Debian 13 (Trixie) containers for safe testing
- Script modifies system state significantly
- Integration tests automatically clean up containers
- Apple Silicon Macs need `--platform linux/amd64` flag
- See `docs/container-testing.md` for compose.yml usage and advanced testing workflows

### Pre-commit Hooks

Shellcheck, gitleaks, and markdownlint run automatically on commit:

```bash
make precommit-install  # Install hooks
make precommit          # Run manually
```

## Common Usage Examples

### Full LAMP Stack with Moodle (MySQL)

```bash
sudo laemp.sh -p 8.4 -w apache -f -d mysql -m 501 -S
```

**Installs:**

- PHP 8.4 with all extensions
- Apache with PHP-FPM
- MySQL/MariaDB with Moodle database
- Moodle 5.1 (fully installed with admin user)
- Self-signed SSL certificate
- Virtual host configuration
- Cron job for maintenance

### Full LEMP Stack with Moodle (PostgreSQL)

```bash
sudo laemp.sh -p 8.4 -w nginx -d pgsql -m 501 -a
```

**Installs:**

- PHP 8.4 with all extensions
- Nginx with optimized configuration
- PostgreSQL 16 with Moodle database
- Moodle 5.1 (fully installed)
- Let's Encrypt SSL certificate
- Nginx server block
- Cron job for maintenance

### Production Setup with Monitoring and Caching

```bash
sudo laemp.sh -p 8.4 -w nginx -d mysql -m 501 -S -r -M
```

**Installs everything above PLUS:**

- Prometheus monitoring (port 9090)
- Node exporter (system metrics)
- Nginx exporter (web server metrics)
- PHP-FPM exporter (PHP metrics)
- Memcached (configured for Moodle sessions)

### Testing Before Installation (Dry Run)

```bash
sudo laemp.sh -n -v -p 8.4 -w nginx -d mysql -m 501 -S
```

Shows all commands that would be executed without making changes.

## Ansible Infrastructure as Code (In Progress)

The `ansible/` directory contains an Ansible rewrite of the bash script functionality. This provides declarative infrastructure management with the same capabilities.

### Ansible Directory Structure

- `ansible.cfg` - Points Ansible at local inventory, enables callbacks
- `requirements.yml` - Roles and collections (Moodle role + Podman connection plugin)
- `inventory/containers.ini` - Static inventory for Podman containers from `compose.yml`
- `group_vars/all.yml` - Shared defaults between Ansible and laemp.sh (domains, paths, DB credentials)
- `playbooks/container-verify.yml` - Verification playbook that collects service/package/file data for diffing
- `playbooks/site.yml` - Main Ansible playbook (currently a shim, being expanded to full role stack)

### Ansible Usage

```bash
# Install Ansible dependencies
ansible-galaxy install -r ansible/requirements.yml

# Verify container state (produces JSON snapshot in ansible/.artifacts/)
cd ansible
ansible-playbook playbooks/container-verify.yml

# Run Ansible converge (install/configure Moodle)
ansible-playbook playbooks/site.yml

# Compare laemp.sh vs Ansible results
diff -u .artifacts/laemp-test-debian-*.json
```

### Ansible Testing Strategy

The project uses the same Podman containers (`compose.yml`) for both bash and Ansible testing to ensure parity:

1. Start container with `make debian` or `make ubuntu`
2. Run laemp.sh inside container and capture verification snapshot
3. Run Ansible playbook and capture second snapshot
4. Diff snapshots to identify any divergence

See `ansible/README.md` and `next-steps.md` for current Ansible work status.

## Project Documentation

Additional documentation in `docs/` directory:

- **`docs/plan.md`** (485 lines): Complete 36-hour implementation plan with code examples
- **`docs/ansible-rewrite.md`** (1,089 lines): Ansible migration guide with role patterns and playbook examples
- **`docs/IMPLEMENTATION_SUMMARY.md`** (571 lines): Project completion status, success criteria, and file changes
- **`docs/container-testing.md`**: Comprehensive guide to Podman testing workflows

## Project Status and Recent Work

### Bash Script (laemp.sh) - Production Ready

The bash script has been completed and enhanced from 2,242 to 2,731 lines (+489 lines). Key improvements:

**Critical Fixes:**
1. **Database Installation**: Was missing entirely, now fully functional for MySQL and PostgreSQL
2. **SSL Certificates**: Fixed certbot command flags and certificate path handling
3. **Moodle Installation**: Now completes full installation including database schema and admin user
4. **Memcached Integration**: Now properly configured in Moodle's config.php
5. **Nginx Repository**: Replaced third-party repositories (Ondrej PPA for Ubuntu, Sury for Debian) with official nginx.org repository for both distros (lines 1414-1447)

**New Functions Added:**
- `mysql_verify()`, `mysql_ensure()` (lines 2130-2235)
- `postgres_verify()`, `postgres_ensure()` (lines 2236-2358)
- `get_cert_path()`, `validate_certificates()` (lines 419-504)
- `generate_password()` (line 896)
- `moodle_install_database()` (line 905)
- `setup_moodle_cron()` (line 951)

**Platform Support:**
- Moodle 5.1.0 Support (version 501)
- Ubuntu 24.04 LTS (Noble Numbat)
- Debian 13 (Trixie)

**Testing:**
- Expanded from 8 to 70 total tests across 3 test suites
- Integration tests with Podman containers
- Smoke tests for fast validation
- Multi-container orchestration with compose.yml

**Status**: Production-ready and fully functional for single-server Moodle deployments.

### Ansible Rewrite - In Progress

An Ansible rewrite is underway to provide Infrastructure as Code capabilities with the same functionality as the bash script. Current status:

- Scaffolding complete (`ansible/` directory with roles, inventory, playbooks)
- Verification playbook working (captures system state for comparison)
- Shim playbook runs but needs expansion to full role stack
- Testing strategy uses same Podman containers as bash script for parity validation

See `ansible/README.md` and `next-steps.md` for current work items.
