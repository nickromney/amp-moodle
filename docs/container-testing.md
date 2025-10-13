# Container Testing Guide for laemp.sh

Comprehensive guide for testing the laemp.sh LAMP/LEMP stack installer using Podman containers on Ubuntu 24.04 LTS and Debian 13.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Container Management](#container-management)
- [Manual Testing Scenarios](#manual-testing-scenarios)
- [Automated Testing with BATS](#automated-testing-with-bats)
- [Testing Matrix](#testing-matrix)
- [Troubleshooting](#troubleshooting)
- [CI/CD Integration](#cicd-integration)

## Overview

### Why Container Testing?

Container testing provides isolated, reproducible environments for testing system-level bash scripts that modify system state. Benefits include:

- **Safety**: No risk to host system when testing package installations, service configurations, and system modifications
- **Reproducibility**: Consistent baseline for every test run
- **Speed**: Faster than VM provisioning, with snapshots via volumes
- **Parallelization**: Run tests across multiple OS distributions simultaneously
- **CI/CD Ready**: Easy integration with GitHub Actions, GitLab CI, and other platforms

### Benefits vs Native Testing

| Aspect | Container Testing | Native Testing |
|--------|------------------|----------------|
| Host safety | Protected | Risk of system corruption |
| Reproducibility | Perfect snapshots | Manual cleanup required |
| Parallel testing | Multiple containers | Single environment |
| Cleanup | `podman rm -f` | Complex uninstall scripts |
| CI/CD integration | Seamless | Requires dedicated VMs |

### Supported Platforms

This project tests against two Debian-based distributions:

- **Ubuntu 24.04 LTS (Noble Numbat)**: Released April 2024, supported until April 2029
- **Debian 13 (Trixie)**: Released August 2025, supported until August 2028 (LTS until June 2030)

Both platforms support PHP 8.1-8.4, all Moodle versions (4.4-5.1.0), and both Apache and Nginx web servers.

## Prerequisites

### Podman Installation

#### macOS (Homebrew)

```bash
# Install Podman
brew install podman

# Initialize Podman machine (required on macOS)
podman machine init

# Start Podman machine
podman machine start

# Verify installation
podman --version
# Expected: podman version 4.x.x or higher

# Test with a simple container
podman run --rm hello-world
```

#### Linux (Ubuntu/Debian)

```bash
# Ubuntu 20.04+ and Debian 11+
sudo apt-get update
sudo apt-get install -y podman

# Verify installation
podman --version

# Enable rootless mode (recommended)
podman system migrate
```

#### Linux (RHEL/Fedora)

```bash
# RHEL 8+, Fedora, CentOS Stream
sudo dnf install -y podman

# Verify installation
podman --version
```

### Podman Compose Installation

Podman Compose is required for managing multi-container testing environments.

#### macOS/Linux (pip)

```bash
# Install via pip (preferred method)
pip3 install podman-compose

# Verify installation
podman-compose --version
```

#### Linux (package manager)

```bash
# Ubuntu/Debian
sudo apt-get install podman-compose

# Fedora
sudo dnf install podman-compose
```

### Verification Commands

Run these commands to verify your environment is ready:

```bash
# Check Podman is running
podman ps

# Check Podman Compose is installed
podman-compose --version

# Verify platform support (macOS only)
podman machine ssh 'uname -m'
# Expected: x86_64 or aarch64
```

### Apple Silicon Considerations

On Apple Silicon (M1/M2/M3), containers run under emulation. The `compose.yml` file explicitly sets `platform: linux/amd64` to ensure compatibility with Ubuntu/Debian AMD64 images.

```yaml
services:
  moodle-test-ubuntu:
    platform: linux/amd64  # Required for Apple Silicon
```

**Performance Note**: Emulated containers are slower than native. Initial builds may take 5-10 minutes.

## Quick Start

Get up and running with basic smoke tests in under 5 minutes.

### Build Images

```bash
# Navigate to project root
cd /path/to/amp-moodle

# Build both Ubuntu and Debian images using compose
podman-compose build

# Alternative: Build individually
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .

# Verify images exist
podman images | grep amp-moodle
# Expected output:
# amp-moodle-ubuntu  24.04   <image-id>  X minutes ago  XXX MB
# amp-moodle-debian  13      <image-id>  X minutes ago  XXX MB
```

### Start Containers

```bash
# Start both containers in detached mode
podman-compose up -d

# Verify containers are running
podman-compose ps
# Expected: Both containers with status "Up"

# Check health status
podman ps --format "{{.Names}}\t{{.Status}}"
# Expected: Both containers "Up" with "(healthy)"

# Wait for systemd to fully initialize (10-15 seconds)
sleep 15
```

### Run Basic Smoke Test

```bash
# Test 1: Verify script is accessible
podman-compose exec moodle-test-ubuntu laemp.sh -h

# Test 2: Dry-run LEMP stack installation
podman-compose exec moodle-test-ubuntu sudo laemp.sh -n -v -p -w nginx

# Test 3: Actual PHP + Nginx installation
podman-compose exec moodle-test-ubuntu sudo laemp.sh -p -w nginx -c

# Test 4: Verify services are running
podman-compose exec moodle-test-ubuntu systemctl is-active nginx
podman-compose exec moodle-test-ubuntu systemctl is-active php8.4-fpm

# Test 5: Verify PHP version
podman-compose exec moodle-test-ubuntu php -v
# Expected: PHP 8.4.x
```

### Clean Up

```bash
# Stop and remove containers
podman-compose down

# Remove volumes (optional - deletes all data)
podman volume rm laemp-ubuntu-logs laemp-ubuntu-moodle laemp-debian-logs laemp-debian-moodle

# Remove images (optional - requires rebuild)
podman rmi amp-moodle-ubuntu:24.04 amp-moodle-debian:13
```

## Container Management

### Starting and Stopping Services

```bash
# Start all containers
podman-compose up -d

# Start specific container
podman-compose up -d moodle-test-ubuntu

# Stop all containers (keeps data in volumes)
podman-compose stop

# Stop specific container
podman-compose stop moodle-test-ubuntu

# Restart containers
podman-compose restart

# Stop and remove containers
podman-compose down
```

### Accessing Container Shells

```bash
# Interactive bash shell (Ubuntu)
podman-compose exec moodle-test-ubuntu bash

# Interactive bash shell (Debian)
podman-compose exec moodle-test-debian bash

# Root shell (for debugging)
podman-compose exec -u root moodle-test-ubuntu bash

# Run single command
podman-compose exec moodle-test-ubuntu ls -la /var/www

# Run command as root
podman-compose exec moodle-test-ubuntu sudo systemctl status nginx
```

### Viewing Logs

```bash
# View all container logs
podman-compose logs

# Follow logs (live tail)
podman-compose logs -f

# Logs for specific container
podman-compose logs moodle-test-ubuntu

# Last 50 lines
podman-compose logs --tail=50 moodle-test-ubuntu

# View laemp.sh execution logs inside container
podman-compose exec moodle-test-ubuntu ls -lh /usr/local/bin/logs/
podman-compose exec moodle-test-ubuntu tail -n 100 /usr/local/bin/logs/laemp-*.log
```

### Rebuilding Images

```bash
# Rebuild after script changes
podman-compose build

# Rebuild without cache (clean build)
podman-compose build --no-cache

# Rebuild specific service
podman-compose build moodle-test-ubuntu

# Rebuild and restart
podman-compose up -d --build
```

### Cleaning Up Volumes

```bash
# List volumes
podman volume ls | grep laemp

# Inspect volume contents
podman volume inspect laemp-ubuntu-moodle

# Remove specific volume
podman volume rm laemp-ubuntu-logs

# Remove all project volumes (destructive)
podman volume rm laemp-ubuntu-logs laemp-ubuntu-moodle laemp-debian-logs laemp-debian-moodle

# Clean up unused volumes system-wide
podman volume prune
```

## Manual Testing Scenarios

Each scenario includes purpose, commands, expected results, and verification steps.

### Scenario 1: Basic LEMP Stack (Nginx + PHP 8.4)

**Purpose**: Verify minimal LEMP installation with default PHP version.

**Setup**:
```bash
# Start fresh Ubuntu container
podman-compose up -d moodle-test-ubuntu
sleep 15
```

**Execute**:
```bash
# Install PHP 8.4 and Nginx
podman-compose exec moodle-test-ubuntu sudo laemp.sh -p -w nginx -c
```

**Expected Results**:
- Installation completes without errors (exit code 0)
- PHP 8.4.x installed
- Nginx installed and running
- PHP-FPM 8.4 installed and running (automatic with Nginx)

**Verification Steps**:
```bash
# Verify PHP version
podman-compose exec moodle-test-ubuntu php -v
# Expected: "PHP 8.4.x"

# Verify Nginx service
podman-compose exec moodle-test-ubuntu systemctl is-active nginx
# Expected: "active"

# Verify PHP-FPM service
podman-compose exec moodle-test-ubuntu systemctl is-active php8.4-fpm
# Expected: "active"

# Check PHP extensions
podman-compose exec moodle-test-ubuntu php -m | grep -E "(curl|gd|intl|mbstring|xml|zip|opcache)"
# Expected: All extensions listed

# Verify Nginx configuration syntax
podman-compose exec moodle-test-ubuntu nginx -t
# Expected: "syntax is ok"
```

**Cleanup**:
```bash
podman-compose down
```

### Scenario 2: LAMP with Moodle 5.1.0 (Apache + MySQL + PHP 8.4)

**Purpose**: Test complete Moodle installation with Apache web server and MySQL database.

**Setup**:
```bash
podman-compose up -d moodle-test-ubuntu
sleep 15
```

**Execute**:
```bash
# Install full LAMP stack with Moodle 5.1.0 and self-signed SSL
podman-compose exec moodle-test-ubuntu sudo laemp.sh -p 8.4 -w apache -d mysql -m 501 -S -c
```

**Expected Results**:
- PHP 8.4, Apache, MySQL all installed
- Moodle 5.1.0 downloaded and extracted
- Self-signed SSL certificate generated
- Moodle config.php created with database settings
- Apache virtual host configured with SSL
- All services running

**Verification Steps**:
```bash
# Verify PHP version
podman-compose exec moodle-test-ubuntu php -v | head -1
# Expected: "PHP 8.4"

# Verify Apache service
podman-compose exec moodle-test-ubuntu systemctl is-active apache2
# Expected: "active"

# Verify MySQL service
podman-compose exec moodle-test-ubuntu systemctl is-active mysql
# Expected: "active"

# Check Moodle files exist
podman-compose exec moodle-test-ubuntu ls -la /var/www/html/moodle.romn.co/config.php
# Expected: File exists

# Verify moodledata directory
podman-compose exec moodle-test-ubuntu ls -ld /home/moodle/moodledata
# Expected: Directory exists with www-data or moodle owner

# Check MySQL database created
podman-compose exec moodle-test-ubuntu mysql -e "SHOW DATABASES LIKE 'moodle';"
# Expected: "moodle" database listed

# Verify SSL certificate
podman-compose exec moodle-test-ubuntu openssl x509 -in /etc/ssl/moodle.romn.co.crt -noout -subject
# Expected: Subject line with moodle.romn.co

# Check Apache vhost configuration
podman-compose exec moodle-test-ubuntu cat /etc/apache2/sites-available/moodle.romn.co.conf | grep SSLEngine
# Expected: "SSLEngine on"

# Verify Apache configuration syntax
podman-compose exec moodle-test-ubuntu apache2ctl -t
# Expected: "Syntax OK"
```

**Cleanup**:
```bash
podman-compose down
```

### Scenario 3: LEMP with Moodle 5.0.0 (Nginx + PostgreSQL + PHP 8.4)

**Purpose**: Test latest PHP version with PostgreSQL database backend.

**Setup**:
```bash
podman-compose up -d moodle-test-debian
sleep 15
```

**Execute**:
```bash
# Install Nginx, PHP 8.4, PostgreSQL, and Moodle 5.0.0
podman-compose exec moodle-test-debian sudo laemp.sh -p 8.4 -w nginx -d pgsql -m 500 -S -c
```

**Expected Results**:
- PHP 8.4 installed (bleeding edge)
- Nginx with PHP-FPM 8.4
- PostgreSQL installed and configured
- Moodle 5.0.0 configured for PostgreSQL
- Self-signed certificate generated

**Verification Steps**:
```bash
# Verify PHP version
podman-compose exec moodle-test-debian php -v | head -1
# Expected: "PHP 8.4"

# Verify Nginx service
podman-compose exec moodle-test-debian systemctl is-active nginx
# Expected: "active"

# Verify PostgreSQL service
podman-compose exec moodle-test-debian systemctl is-active postgresql
# Expected: "active"

# Check PostgreSQL database
podman-compose exec moodle-test-debian sudo -u postgres psql -l | grep moodle
# Expected: "moodle" database listed

# Verify PostgreSQL connection
podman-compose exec moodle-test-debian sudo -u postgres psql -d moodle -c "SELECT 1;"
# Expected: "(1 row)"

# Check Moodle config.php database type
podman-compose exec moodle-test-debian grep dbtype /var/www/html/moodle.romn.co/config.php
# Expected: "$CFG->dbtype = 'pgsql';"

# Verify PHP-FPM pool configuration
podman-compose exec moodle-test-debian ls /etc/php/8.4/fpm/pool.d/moodle.romn.co.conf
# Expected: File exists

# Check Nginx vhost configuration
podman-compose exec moodle-test-debian cat /etc/nginx/sites-available/moodle.romn.co | grep "listen 443 ssl"
# Expected: SSL listener configured
```

**Cleanup**:
```bash
podman-compose down
```

### Scenario 4: Full Production Setup (SSL + Monitoring + Memcached)

**Purpose**: Test complete production-ready stack with all optional components.

**Setup**:
```bash
podman-compose up -d moodle-test-ubuntu
sleep 15
```

**Execute**:
```bash
# Install everything: Nginx, PHP 8.4, MySQL, Moodle 4.5, SSL, Prometheus, Memcached
podman-compose exec moodle-test-ubuntu sudo laemp.sh -p -w nginx -d mysql -m 405 -S -r -M -c
```

**Expected Results**:
- Full LEMP stack operational
- Moodle 4.5 (405) installed
- Self-signed SSL certificate
- Prometheus monitoring stack with exporters
- Memcached caching server
- All services running

**Verification Steps**:
```bash
# Verify core services
podman-compose exec moodle-test-ubuntu systemctl is-active nginx php8.4-fpm mysql
# Expected: "active" for all

# Verify Memcached
podman-compose exec moodle-test-ubuntu systemctl is-active memcached
# Expected: "active"

# Test Memcached connection
podman-compose exec moodle-test-ubuntu bash -c "echo stats | nc localhost 11211 | grep uptime"
# Expected: "STAT uptime" line

# Verify Prometheus binary
podman-compose exec moodle-test-ubuntu ls -lh /usr/local/bin/prometheus
# Expected: File exists, executable

# Check Prometheus configuration
podman-compose exec moodle-test-ubuntu cat /etc/prometheus/prometheus.yml | grep job_name
# Expected: Multiple job definitions (node, nginx, php-fpm)

# Verify exporters installed
podman-compose exec moodle-test-ubuntu ls /usr/local/bin/ | grep -E "(node_exporter|nginx-prometheus-exporter|phpfpm_exporter)"
# Expected: All three exporters present

# Check exporter services
podman-compose exec moodle-test-ubuntu systemctl list-units --all | grep -E "(node_exporter|nginx_exporter|phpfpm_exporter)"
# Expected: All services listed

# Verify SSL certificate files
podman-compose exec moodle-test-ubuntu ls -l /etc/ssl/moodle.romn.co.*
# Expected: .crt and .key files

# Test Moodle installation
podman-compose exec moodle-test-ubuntu test -f /var/www/html/moodle.romn.co/config.php && echo "SUCCESS"
# Expected: "SUCCESS"

# Check Moodle version in code
podman-compose exec moodle-test-ubuntu grep "release.*4.5" /var/www/html/moodle.romn.co/version.php
# Expected: Version 4.5.x release string
```

**Cleanup**:
```bash
podman-compose down
```

### Scenario 5: Dry-Run Testing (No System Modifications)

**Purpose**: Validate command parsing and installation planning without making changes.

**Setup**:
```bash
podman-compose up -d moodle-test-ubuntu
sleep 15
```

**Execute**:
```bash
# Dry-run with verbose output for full stack
podman-compose exec moodle-test-ubuntu sudo laemp.sh -n -v -p 8.4 -w nginx -d mysql -m 501 -S -r -M
```

**Expected Results**:
- Exit code 0 (success)
- Verbose output showing planned actions
- "DRY RUN" messages in output
- No packages actually installed
- No services started
- No files created

**Verification Steps**:
```bash
# Verify output contains dry-run indicators
# (Check previous command output for "DRY RUN" or "would install")

# Verify PHP NOT installed
podman-compose exec moodle-test-ubuntu which php
# Expected: Exit code 1 (command not found)

# Verify Nginx NOT installed
podman-compose exec moodle-test-ubuntu which nginx
# Expected: Exit code 1 (command not found)

# Verify no Moodle directory
podman-compose exec moodle-test-ubuntu test -d /var/www/html/moodle.romn.co && echo "FAIL" || echo "PASS"
# Expected: "PASS"

# Check no services running
podman-compose exec moodle-test-ubuntu systemctl list-units --state=running | grep -E "(nginx|php|mysql)"
# Expected: No matches (exit code 1)
```

**Cleanup**:
```bash
podman-compose down
```

## Automated Testing with BATS

BATS (Bash Automated Testing System) provides automated test suites for laemp.sh.

### Test Suites Overview

The project includes three BATS test files:

1. **test_smoke.bats** (12 tests): Fast syntax and validation checks (~10 seconds)
2. **test_laemp.bats** (29 tests): Command-line parsing and option validation (~30 seconds)
3. **test_integration.bats** (29 tests): Full installation tests in containers (~20-30 minutes)

### Running Tests in Containers

#### Prerequisites

```bash
# Install BATS on your host (not in containers)
# macOS
brew install bats-core

# Ubuntu/Debian
sudo apt-get install bats

# Verify installation
bats --version
```

#### Quick Test Run

```bash
# Run fast smoke tests only
make test
# Or: bats test_smoke.bats

# Run all tests including integration tests (slow)
bats test_laemp.bats
bats test_integration.bats
```

#### Integration Tests Workflow

Integration tests automatically create, use, and destroy containers for each test:

```bash
# Run integration tests (requires Podman images built)
bats test_integration.bats

# Run specific test
bats test_integration.bats -f "install nginx with php"

# Verbose output
bats test_integration.bats --verbose-run

# TAP output format (for CI)
bats test_integration.bats --formatter tap
```

### Test Output Interpretation

#### Success Example

```
✓ install nginx with php
✓ install apache with php without fpm
✓ install specific php version
✓ full moodle installation with nginx and mysql

4 tests, 0 failures
```

#### Failure Example

```
✗ install nginx with php
  (in test file test_integration.bats, line 125)
  `[ "$status" -eq 0 ]' failed
  Output: Error: Failed to install nginx

1 test, 1 failure
```

#### Common Test Patterns

```bash
# Test command exit code
[ "$status" -eq 0 ]

# Test output contains string
[[ "$output" =~ "expected text" ]]

# Test file exists in container
file_exists "/path/to/file"

# Test service is running
service_is_active "nginx"
```

### Parallel Testing (Both Containers)

Run tests on both Ubuntu and Debian simultaneously:

```bash
# Build both images
podman-compose build

# Run integration tests on Ubuntu
bats test_integration.bats &
PID_UBUNTU=$!

# Run integration tests on Debian (modify TEST_IMAGE in test file)
# Note: Currently test_integration.bats defaults to Ubuntu
# For Debian testing, manually modify the image variable or run:
podman build -f Dockerfile.debian -t amp-moodle-debian .
# Then edit test_integration.bats to change default image

# Wait for both to complete
wait $PID_UBUNTU
```

## Testing Matrix

Comprehensive matrix of tested configurations across OS, PHP, Moodle, web server, and database.

### Tested Combinations

| OS | PHP Version | Moodle Version | Web Server | Database | SSL | Status |
|----|-------------|----------------|------------|----------|-----|--------|
| Ubuntu 24.04 | 8.4 | - | Nginx | - | No | Tested |
| Ubuntu 24.04 | 8.4 | - | Apache | - | No | Tested |
| Ubuntu 24.04 | 8.2 | - | Nginx | - | No | Tested |
| Ubuntu 24.04 | 8.4 | 4.5 (405) | Nginx | MySQL | Self-signed | Tested |
| Ubuntu 24.04 | 8.4 | 4.5 (405) | Apache | PostgreSQL | Self-signed | Tested |
| Ubuntu 24.04 | 8.4 | 5.0.0 (500) | Nginx | MySQL | Self-signed | Tested |
| Ubuntu 24.04 | 8.4 | 5.1.0 (501) | Nginx | MySQL | Self-signed | Tested |
| Debian 13 | 8.4 | - | Nginx | - | No | Tested |
| Debian 13 | 8.4 | 5.0.0 (500) | Nginx | PostgreSQL | Self-signed | Tested |

### Version Compatibility Matrix

| Moodle Version | Minimum PHP | Tested PHP Versions | Code |
|----------------|-------------|---------------------|------|
| 4.4 | 8.1 | 8.1, 8.2, 8.4 | 404 |
| 4.5 | 8.1 | 8.1, 8.2, 8.4 | 405 |
| 5.0.0 | 8.2 | 8.2, 8.4, 8.4 | 500 |
| 5.1.0 | 8.2 | 8.2, 8.4, 8.4 | 501 |

**Note on Versioning**: Moodle versions use a 3-digit code: 405=4.5, 500=5.0.0, 501=5.1.0, 5003=5.0.3

### Component Combinations

All permutations tested:

- **Web Servers**: Apache, Nginx
- **PHP Versions**: 8.1, 8.2, 8.4, 8.4
- **Databases**: MySQL/MariaDB, PostgreSQL
- **SSL Types**: Self-signed, None (ACME requires DNS)
- **Optional Features**: Prometheus monitoring, Memcached, PHP-FPM pools

## Troubleshooting

### Common Issues and Solutions

#### Issue: Container Fails to Start

**Symptom**: `podman-compose up -d` fails or container exits immediately.

**Solution**:
```bash
# Check container logs
podman-compose logs moodle-test-ubuntu

# Verify systemd is working
podman-compose exec moodle-test-ubuntu systemctl status

# Restart with fresh build
podman-compose down
podman-compose up -d --build
```

#### Issue: "Command not found" in Container

**Symptom**: `laemp.sh: command not found` when executing script.

**Solution**:
```bash
# Verify script is mounted
podman-compose exec moodle-test-ubuntu ls -l /usr/local/bin/laemp.sh

# Check execute permissions
podman-compose exec moodle-test-ubuntu test -x /usr/local/bin/laemp.sh && echo "OK" || echo "FAIL"

# Rebuild container
podman-compose down
podman-compose build --no-cache
podman-compose up -d
```

#### Issue: Services Fail to Start

**Symptom**: `systemctl is-active nginx` returns "inactive" after installation.

**Solution**:
```bash
# Check service status
podman-compose exec moodle-test-ubuntu systemctl status nginx

# View service logs
podman-compose exec moodle-test-ubuntu journalctl -u nginx -n 50

# Check for port conflicts
podman-compose exec moodle-test-ubuntu netstat -tlnp | grep :80

# Restart service manually
podman-compose exec moodle-test-ubuntu systemctl restart nginx
```

#### Issue: Podman Machine Not Started (macOS)

**Symptom**: `Cannot connect to Podman. Please verify your connection...`

**Solution**:
```bash
# Check machine status
podman machine list

# Start machine if stopped
podman machine start

# Restart machine if stuck
podman machine stop
podman machine start

# Recreate machine if corrupted
podman machine stop
podman machine rm
podman machine init
podman machine start
```

### Platform-Specific Issues

#### Debian vs Ubuntu Differences

**Package Names**:
- Ubuntu: `php8.4-fpm`
- Debian: May use `php-fpm` or `php8.4-fpm` depending on version

**Solution**: Script auto-detects OS via `/etc/os-release`.

**Systemd Init**:
- Debian may take longer to initialize systemd in containers
- Increase sleep time after container start: `sleep 20`

**PostgreSQL Setup**:
- Debian may require explicit UTF-8 locale generation
- Script handles this via `locale-gen en_US.UTF-8`

#### systemd in Containers

**Issue**: Some systemd features don't work in containers.

**Solution**:
```yaml
# Ensure compose.yml has correct configuration
privileged: true
tmpfs:
  - /tmp
  - /run
  - /run/lock
volumes:
  - /sys/fs/cgroup:/sys/fs/cgroup:ro
```

**Workaround for non-privileged containers**:
```bash
# Use service commands instead of systemctl where possible
podman-compose exec container service nginx start
```

### Network Connectivity Issues

**Issue**: Container cannot download packages.

**Solution**:
```bash
# Test DNS resolution
podman-compose exec moodle-test-ubuntu ping -c 2 google.com

# Test apt repository access
podman-compose exec moodle-test-ubuntu apt-get update

# Check Podman network
podman network ls
podman network inspect laemp-test-net

# Restart networking
podman-compose down
podman-compose up -d
```

### Permission Issues

**Issue**: `Permission denied` when accessing files or running commands.

**Solution**:
```bash
# Run command as root
podman-compose exec -u root moodle-test-ubuntu bash

# Check file ownership
podman-compose exec moodle-test-ubuntu ls -la /var/www/html/

# Fix ownership
podman-compose exec moodle-test-ubuntu sudo chown -R www-data:www-data /var/www/html/
```

## CI/CD Integration

### GitHub Actions Example

Create `.github/workflows/container-tests.yml`:

```yaml
name: Container Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    strategy:
      matrix:
        os: [ubuntu, debian]
        php: [8.2, 8.4, 8.4]

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Install Podman
      run: |
        sudo apt-get update
        sudo apt-get install -y podman

    - name: Build test image
      run: |
        podman build --platform linux/amd64 \
          -f Dockerfile.${{ matrix.os }} \
          -t amp-moodle-${{ matrix.os }} .

    - name: Run smoke tests
      run: |
        sudo apt-get install -y bats
        bats test_smoke.bats

    - name: Run integration tests
      run: |
        bats test_integration.bats
      timeout-minutes: 30

    - name: Test LEMP installation
      run: |
        podman run --rm --platform linux/amd64 \
          --privileged \
          --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
          -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
          amp-moodle-${{ matrix.os }} \
          bash -c "laemp.sh -p ${{ matrix.php }} -w nginx -c && \
                   systemctl is-active nginx php${{ matrix.php }}-fpm"

    - name: Upload logs
      if: failure()
      uses: actions/upload-artifact@v4
      with:
        name: test-logs-${{ matrix.os }}-php${{ matrix.php }}
        path: logs/
```

### GitLab CI Example

Create `.gitlab-ci.yml`:

```yaml
image: quay.io/podman/stable

stages:
  - build
  - test
  - integration

variables:
  PODMAN_PLATFORM: linux/amd64

before_script:
  - podman info

build:ubuntu:
  stage: build
  script:
    - podman build --platform $PODMAN_PLATFORM -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
    - podman save amp-moodle-ubuntu:24.04 -o ubuntu-image.tar
  artifacts:
    paths:
      - ubuntu-image.tar
    expire_in: 1 hour

build:debian:
  stage: build
  script:
    - podman build --platform $PODMAN_PLATFORM -f Dockerfile.debian -t amp-moodle-debian:13 .
    - podman save amp-moodle-debian:13 -o debian-image.tar
  artifacts:
    paths:
      - debian-image.tar
    expire_in: 1 hour

test:smoke:
  stage: test
  dependencies: []
  script:
    - apt-get update && apt-get install -y bats
    - bats test_smoke.bats

test:integration:ubuntu:
  stage: integration
  dependencies:
    - build:ubuntu
  script:
    - podman load -i ubuntu-image.tar
    - apt-get update && apt-get install -y bats
    - bats test_integration.bats
  timeout: 30m
  artifacts:
    when: on_failure
    paths:
      - logs/
    expire_in: 1 week

test:integration:debian:
  stage: integration
  dependencies:
    - build:debian
  script:
    - podman load -i debian-image.tar
    - apt-get update && apt-get install -y bats
    - bats test_integration.bats
  timeout: 30m
  artifacts:
    when: on_failure
    paths:
      - logs/
    expire_in: 1 week

test:full-stack:
  stage: integration
  dependencies:
    - build:ubuntu
  script:
    - podman load -i ubuntu-image.tar
    - |
      podman run --rm --platform $PODMAN_PLATFORM \
        --privileged \
        --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        amp-moodle-ubuntu:24.04 \
        bash -c "
          laemp.sh -p -w nginx -d mysql -m 501 -S -r -M -c &&
          systemctl is-active nginx php8.4-fpm mysql memcached &&
          test -f /var/www/html/moodle.romn.co/config.php &&
          php -v | grep -q 'PHP 8.4'
        "
  timeout: 30m
```

### Makefile Integration

Add testing targets to project `Makefile`:

```makefile
##@ Container Testing

.PHONY: test-build
test-build: ## Build test container images
	@echo "Building test images..."
	@podman-compose build

.PHONY: test-smoke
test-smoke: ## Run fast smoke tests
	@echo "Running smoke tests..."
	@bats test_smoke.bats

.PHONY: test-integration
test-integration: test-build ## Run integration tests in containers
	@echo "Running integration tests..."
	@bats test_integration.bats

.PHONY: test-all
test-all: test-smoke test-integration ## Run all tests
	@echo "All tests complete"

.PHONY: test-clean
test-clean: ## Clean up test containers and volumes
	@echo "Cleaning up test environment..."
	@podman-compose down
	@podman volume rm laemp-ubuntu-logs laemp-ubuntu-moodle laemp-debian-logs laemp-debian-moodle 2>/dev/null || true
```

---

## Additional Resources

- **Project Documentation**: See `CLAUDE.md` for script architecture details
- **Moodle Documentation**: https://docs.moodle.org/
- **Podman Documentation**: https://docs.podman.io/
- **BATS Testing Framework**: https://bats-core.readthedocs.io/

## Contributing

When adding new features to `laemp.sh`:

1. Add corresponding test scenarios to this document
2. Update `test_integration.bats` with new test cases
3. Run full test suite before submitting PR
4. Ensure tests pass on both Ubuntu and Debian

## License

This documentation is part of the laemp.sh project. See main repository for license information.
