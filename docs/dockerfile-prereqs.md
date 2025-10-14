# Dockerfile Prerequisites Implementation Plan

## Overview

This project maintains **two sets of Docker images** for comprehensive laemp.sh testing:

1. **Stock Images** (`Dockerfile.ubuntu`, `Dockerfile.debian`) - Bare Ubuntu/Debian for full bootstrap testing
2. **Prerequisite Images** (`Dockerfile.prereqs.ubuntu`, `Dockerfile.prereqs.debian`) - Pre-installed packages for "last mile" testing

This document describes the prerequisite images implementation and explains when to use each type.

## Quick Start

**For full bootstrap testing (tests package installation):**
```bash
podman run -it amp-moodle-ubuntu:24.04
sudo laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S
```

**For last mile testing (tests configuration only):**
```bash
podman run -it amp-moodle-prereqs-ubuntu
sudo laemp.sh -c -m 501 -S -w nginx -d mariadb  # Note: no -p flag needed
```

## Goals

1. **Comprehensive Testing**: Stock images test full bootstrap, prereqs images test configuration logic
2. **Fast Iteration**: Prereqs images skip package installation (~5-7 minute savings per test)
3. **CI/CD Optimization**: Prereqs images can be cached in pipelines for faster builds
4. **Development Workflow**: Developers can iterate quickly on configuration changes

## Architecture

### Two Independent Image Sets

**Stock Images (Full Bootstrap):**
```
ubuntu:24.04 → + base tools only → amp-moodle-ubuntu:24.04
debian:13 → + base tools only → amp-moodle-debian:13
```

**Prerequisite Images (Last Mile):**
```
ubuntu:24.04 → + base tools + PHP + Nginx + MariaDB → amp-moodle-prereqs-ubuntu
debian:13 → + base tools + PHP + Nginx + MariaDB → amp-moodle-prereqs-debian
```

- **No layer sharing between sets**: Each serves a different testing purpose
- **Stock images**: Test laemp.sh's ability to bootstrap from bare OS
- **Prereqs images**: Test laemp.sh's configuration logic with packages pre-installed

## Prerequisites to Install

Based on laemp.sh analysis (lines 2052-2106, 1822-1898, 2649-2764), the prereq images will install:

### 1. PHP 8.4 Packages

**Repository Setup:**
- Ubuntu: Ondrej PPA (`ppa:ondrej/php`)
- Debian: Sury repository (`deb https://packages.sury.org/php/ $CODENAME main`)

**Packages:**
- Core: `php8.4-cli`, `php8.4-common`, `php8.4-fpm`
- Extensions (from `moodle_ensure()` lines 1495-1513):
  - `php8.4-curl` - HTTP requests
  - `php8.4-gd` - Image manipulation
  - `php8.4-intl` - Internationalization
  - `php8.4-mbstring` - Multibyte string handling
  - `php8.4-soap` - Web services
  - `php8.4-xml` - XML processing
  - `php8.4-xmlrpc` - XML-RPC support
  - `php8.4-zip` - ZIP archive handling
  - `php8.4-opcache` - Bytecode caching
  - `php8.4-ldap` - LDAP integration
  - `php8.4-mysqli` - MariaDB database driver

### 2. Nginx

**Repository Setup:**
- Both distros: nginx.org official repository
- GPG key: `https://nginx.org/keys/nginx_signing.key`
- Repository: `http://nginx.org/packages/mainline/{ubuntu|debian} $CODENAME nginx`
- APT pinning: Priority 900 for nginx.org packages

**Package:**
- `nginx` (mainline branch from official repository)

### 3. MariaDB

**Packages:**
- `mariadb-server`
- `mariadb-client`

**Note:** Database system will be initialized by package installation, but NO database or user creation.

### 4. Additional Dependencies

**From `moodle_dependencies()` (lines 1066-1102):**
- `ghostscript` - PDF generation
- `libaio1` or `libaio1t64` (Debian 13+) - Async I/O
- `libcurl4` - HTTP client library
- `libgss3` - GSS-API support
- `libmcrypt-dev` - Encryption library
- `libxml2` - XML parser
- `libxslt1.1` - XSLT processor
- `libzip-dev` - ZIP library
- `sassc` - SASS compiler
- `unzip`, `zip` - Archive utilities
- `libmariadb3` - MariaDB client library

**Tools:**
- `composer` - PHP dependency manager (installed via install script in `moodle_composer_install()`)
- `openssl` - SSL/TLS toolkit
- `cron` - Scheduled task daemon

## What Will NOT Be Configured

The prereqs images install packages but do NOT configure them. All configuration is performed by laemp.sh:

| Component | Installed by Prereqs | Configured by laemp.sh |
|-----------|---------------------|------------------------|
| PHP packages | ✅ | ❌ |
| PHP-FPM service | ✅ (package) | ❌ (not started) |
| PHP-FPM pools | ❌ | ✅ `php_fpm_create_pool()` |
| PHP settings | ❌ | ✅ `php_configure_for_moodle()` |
| Nginx package | ✅ | ❌ |
| Nginx service | ✅ (package) | ❌ (not started) |
| Nginx global config | ❌ | ✅ `nginx_create_optimized_config()` |
| Nginx vhost | ❌ | ✅ `nginx_create_vhost()` |
| MariaDB packages | ✅ | ❌ |
| MariaDB service | ✅ (package) | ❌ (not started) |
| MariaDB database | ❌ | ✅ `mariadb_ensure()` |
| MariaDB user | ❌ | ✅ `mariadb_ensure()` |
| MariaDB Moodle config | ❌ | ✅ `/etc/mysql/mariadb.conf.d/99-moodle.cnf` |
| SSL certificates | ❌ | ✅ `self_signed_cert_request()` |
| Moodle files | ❌ | ✅ `moodle_download_extract()` |
| Moodle config.php | ❌ | ✅ `moodle_config_files()` |
| Moodle database schema | ❌ | ✅ `moodle_install_database()` |
| Cron jobs | ❌ | ✅ `setup_moodle_cron()` |

## Why This Works

1. **Automatic FPM Detection**: `-w nginx` automatically sets `FPM_ENSURE=true` (laemp.sh line 3165)
2. **Package Detection**: laemp.sh uses `tool_exists()` and `dpkg -s` to detect installed packages and skips reinstallation
3. **Idempotent Configuration**: All laemp.sh configuration functions check if configuration already exists before applying changes

## Dockerfile Implementations

### 1. Dockerfile.prereqs.debian

```dockerfile
FROM debian:13

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base dependencies
RUN apt-get update && apt-get install -y \
    wget curl gnupg lsb-release sudo tar unzip \
    locales ca-certificates bats git && \
    rm -rf /var/lib/apt/lists/*

# Generate locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Add Sury PHP repository
RUN curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury-php-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/sury-php-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/sury-php.list

# Add nginx.org repository
RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg && \
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list && \
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" > /etc/apt/preferences.d/99nginx

# Install PHP 8.4, Nginx, MariaDB
RUN apt-get update && apt-get install -y \
    php8.4-cli php8.4-common php8.4-fpm \
    php8.4-curl php8.4-gd php8.4-intl php8.4-mbstring \
    php8.4-soap php8.4-xml php8.4-xmlrpc php8.4-zip \
    php8.4-opcache php8.4-ldap php8.4-mysqli \
    nginx \
    mariadb-server mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Determine libaio package (Debian 13+ uses libaio1t64)
RUN apt-get update && \
    if apt-cache search libaio1t64 | grep -q "libaio1t64"; then \
        apt-get install -y libaio1t64; \
    else \
        apt-get install -y libaio1; \
    fi && rm -rf /var/lib/apt/lists/*

# Install Moodle dependencies
RUN apt-get update && apt-get install -y \
    ghostscript libcurl4 libgss3 libmcrypt-dev \
    libxml2 libxslt1.1 libzip-dev sassc unzip zip \
    libmariadb3 openssl cron \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php && \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm /tmp/composer-setup.php

# Copy laemp.sh script
COPY laemp.sh /usr/local/bin/laemp.sh
RUN chmod +x /usr/local/bin/laemp.sh

# Create non-root user for testing
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/testuser
USER testuser

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD test -x /usr/local/bin/laemp.sh && /bin/bash -c 'exit 0'

CMD ["/bin/bash"]
```

### 2. Dockerfile.prereqs.ubuntu

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base dependencies
RUN apt-get update && apt-get install -y \
    wget curl gnupg lsb-release software-properties-common \
    sudo tar unzip locales bats git && \
    rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Add Ondrej PHP PPA
RUN add-apt-repository -y ppa:ondrej/php

# Add nginx.org repository
RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor > /usr/share/keyrings/nginx-archive-keyring.gpg && \
    echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list && \
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" > /etc/apt/preferences.d/99nginx

# Install PHP 8.4, Nginx, MariaDB
RUN apt-get update && apt-get install -y \
    php8.4-cli php8.4-common php8.4-fpm \
    php8.4-curl php8.4-gd php8.4-intl php8.4-mbstring \
    php8.4-soap php8.4-xml php8.4-xmlrpc php8.4-zip \
    php8.4-opcache php8.4-ldap php8.4-mysqli \
    nginx \
    mariadb-server mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Install Moodle dependencies (Ubuntu uses libaio1)
RUN apt-get update && apt-get install -y \
    ghostscript libaio1 libcurl4 libgss3 libmcrypt-dev \
    libxml2 libxslt1.1 libzip-dev sassc unzip zip \
    libmariadb3 openssl cron \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php && \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
    rm /tmp/composer-setup.php

# Copy laemp.sh script
COPY laemp.sh /usr/local/bin/laemp.sh
RUN chmod +x /usr/local/bin/laemp.sh

# Create non-root user for testing
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR /home/testuser
USER testuser

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD test -x /usr/local/bin/laemp.sh && /bin/bash -c 'exit 0'

CMD ["/bin/bash"]
```

## Build Commands

```bash
# Build prerequisite images (for "last mile" testing)
podman build --platform linux/amd64 -f Dockerfile.prereqs.ubuntu -t amp-moodle-prereqs-ubuntu .
podman build --platform linux/amd64 -f Dockerfile.prereqs.debian -t amp-moodle-prereqs-debian .

# Build stock images (for full bootstrap testing)
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .
```

## Important Note: Two Types of Images

This project maintains **two distinct sets of Docker images** for different testing scenarios:

### 1. Stock Images (Full Bootstrap Testing)
- **Files**: `Dockerfile.ubuntu`, `Dockerfile.debian`
- **Base**: `ubuntu:24.04`, `debian:13`
- **Contents**: Only base tools (wget, curl, git, bats, sudo, etc.)
- **Purpose**: Test laemp.sh's ability to bootstrap a system from scratch
- **Images**: `amp-moodle-ubuntu:24.04`, `amp-moodle-debian:13`

### 2. Prerequisite Images (Last Mile Testing)
- **Files**: `Dockerfile.prereqs.ubuntu`, `Dockerfile.prereqs.debian`
- **Base**: `ubuntu:24.04`, `debian:13`
- **Contents**: PHP 8.4, Nginx, MariaDB, Composer, all dependencies pre-installed
- **Purpose**: Test laemp.sh's configuration logic without waiting for package installation
- **Images**: `amp-moodle-prereqs-ubuntu`, `amp-moodle-prereqs-debian`

**Why maintain both?**
- Stock images verify laemp.sh can install all packages correctly
- Prereqs images enable fast iteration when testing configuration changes
- Both are needed for comprehensive testing of laemp.sh functionality

## Testing Commands

### Scenario 1: Full Bootstrap Testing (Stock Images)

Tests laemp.sh's ability to install all packages from scratch:

```bash
# Test Ubuntu full bootstrap
podman run -it amp-moodle-ubuntu:24.04
sudo laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S

# Test Debian full bootstrap
podman run -it amp-moodle-debian:13
sudo laemp.sh -c -p 8.4 -w nginx -d mariadb -m 501 -S
```

**What this tests:**
- ✅ Repository addition (Ondrej/Sury for PHP, nginx.org for Nginx)
- ✅ Package installation (PHP 8.4, Nginx, MariaDB, all extensions)
- ✅ Service initialization
- ✅ Configuration generation (Nginx, PHP-FPM, MariaDB)
- ✅ Moodle installation
- ✅ SSL certificate creation

**Duration:** ~5-10 minutes per run (package downloads + installation)

### Scenario 2: Last Mile Testing (Prereqs Images)

Tests laemp.sh's configuration logic with packages pre-installed:

```bash
# Test Ubuntu prereqs
podman run -it amp-moodle-prereqs-ubuntu

# Verify packages are pre-installed:
php --version              # Should show PHP 8.4.x
nginx -v                   # Should show nginx version
mysql --version            # Should show MariaDB version
composer --version         # Should show composer version

# Run "last mile" configuration:
sudo laemp.sh -c -m 501 -S -w nginx -d mariadb
```

```bash
# Test Debian prereqs
podman run -it amp-moodle-prereqs-debian

# Verify packages are pre-installed:
php --version              # Should show PHP 8.4.x
nginx -v                   # Should show nginx version
mysql --version            # Should show MariaDB version
composer --version         # Should show composer version

# Run "last mile" configuration:
sudo laemp.sh -c -m 501 -S -w nginx -d mariadb
```

**What this tests:**
- ✅ Package detection (skips reinstallation)
- ✅ Configuration generation (Nginx, PHP-FPM, MariaDB)
- ✅ Moodle installation
- ✅ SSL certificate creation
- ✅ Database creation and schema installation

**Duration:** ~2-3 minutes per run (no package installation)

## Expected Behavior

When running `laemp.sh -c -m 501 -S -w nginx -d mariadb` on a prereqs image, the script should:

1. ✅ **Detect PHP 8.4 installed** → Skip PHP installation (lines 2059-2061)
2. ✅ **Detect Nginx installed** → Skip Nginx installation (line 1825)
3. ✅ **Detect MariaDB installed** → Skip MariaDB installation (line 2652)
4. 🔧 **Configure Nginx** → Create optimized nginx.conf (`nginx_create_optimized_config()`)
5. 🔧 **Create SSL certificate** → Generate self-signed cert in `/etc/ssl/` (`self_signed_cert_request()`)
6. 🔧 **Setup MariaDB** → Create database + user with secure password (`mariadb_ensure()`)
7. 🔧 **Configure MariaDB** → Create `/etc/mysql/mariadb.conf.d/99-moodle.cnf` with InnoDB settings
8. 🔧 **Download Moodle** → Extract Moodle 5.1 to `/var/www/html/moodle.romn.co` (`moodle_download_extract()`)
9. 🔧 **Configure PHP** → Set Moodle-specific PHP settings (`php_configure_for_moodle()`)
10. 🔧 **Create PHP-FPM pool** → Create dedicated pool for moodle.romn.co (`php_fpm_create_pool()`)
11. 🔧 **Create Nginx vhost** → Configure server block with SSL (`nginx_create_vhost()`)
12. 🔧 **Install Moodle** → Run CLI installer to create database schema (`moodle_install_database()`)
13. 🔧 **Setup cron** → Add cron job for www-data user (`setup_moodle_cron()`)

**Result**: Fully functional Moodle 5.1 installation accessible at `https://moodle.romn.co`

## Benefits

1. **Fast Iteration**: Test configuration changes without waiting for package installation
2. **Layer Efficiency**: Shared layers between prereqs and full images save disk space
3. **Clear Separation**: Package installation vs. configuration is clearly separated
4. **Flexible Testing**: Can test different laemp.sh configurations on the same prereqs image
5. **CI/CD Ready**: Prereqs images can be cached in CI pipelines for faster builds

## Implementation Checklist

- [x] Create `Dockerfile.prereqs.debian`
- [x] Create `Dockerfile.prereqs.ubuntu`
- [x] Build prereqs images
- [x] Verify packages installed (PHP 8.4, Nginx, MariaDB, Composer)
- [x] Keep stock Dockerfiles separate for full bootstrap testing
- [x] Update documentation (dockerfile-prereqs.md)
- [ ] Test full bootstrap scenario on stock images
- [ ] Test last mile scenario on prereqs images
- [ ] Update CLAUDE.md with testing scenarios
- [ ] Update container-testing.md with both scenarios
- [ ] Commit changes to repository

## References

- **laemp.sh functions analyzed**:
  - `php_ensure()` - lines 2052-2106
  - `nginx_ensure()` - lines 1822-1898
  - `mariadb_ensure()` - lines 2649-2764
  - `moodle_dependencies()` - lines 1066-1102
  - `moodle_ensure()` - lines 1487-1580
  - FPM auto-enable logic - line 3165

- **Related documentation**:
  - `docs/container-testing.md` - Container testing workflows
  - `docs/dockerfile-optimization.md` - Dockerfile best practices
  - `CLAUDE.md` - Project overview and laemp.sh architecture
