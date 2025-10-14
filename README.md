# amp-moodle

Install AMP stack on Ubuntu/Debian, with optional Moodle

## Features

- Installs LAMP/LEMP stack (Linux, Apache/Nginx, MySQL/PostgreSQL, PHP)
- Supports multiple PHP versions (default: 8.4, ready for 8.4)
- Installs Moodle LMS (default: 4.5/405, ready for 5.0/500)
- SSL certificate management (Let's Encrypt or self-signed)
- Memcached support
- Default web server: Nginx with PHP-FPM
- PHP-FPM pool configuration per site with optimized settings
- Prometheus monitoring with exporters for system, web server, and PHP metrics
- PHP configuration optimized for Moodle (max_input_vars=5000, memory limits, etc.)
- Automatic PHP version validation for Moodle compatibility

## Requirements

- Ubuntu or Debian Linux
- Root access or sudo privileges
- Internet connection for downloading packages

## Usage

```bash
# Show help
./laemp.sh -h

# Dry run to see what would be installed
./laemp.sh -n -v

# Install PHP, Nginx, and Moodle with monitoring
sudo ./laemp.sh -p -w nginx -m -r

# Install Apache with PHP-FPM and Moodle
sudo ./laemp.sh -p -w apache -f -m

# Install specific PHP version alongside existing
sudo ./laemp.sh -P 8.4 -w nginx

# Install with self-signed certificate
sudo ./laemp.sh -p -w nginx -m -S

# Install with Let's Encrypt certificate
sudo ./laemp.sh -p -w nginx -m -a
```

## Command-line Options

- `-a, --acme-cert` - Request an ACME certificate for the specified domain
- `-c, --ci` - Run in CI mode (no prompts)
- `-d, --database` - Database type (default: mysql, supported: mysql, mysqli, pgsql)
- `-f, --fpm` - Enable FPM for the web server
- `-h, --help` - Display help message
- `-m, --moodle` - Install Moodle (default: 405 for 4.5, use 500 for 5.0)
- `-M, --memcached` - Install Memcached
- `-n, --nop` - Dry run (show commands without executing)
- `-p, --php` - Install PHP (default: 8.4)
- `-P, --php-alongside` - Install specific PHP version alongside existing
- `-r, --prometheus` - Install Prometheus monitoring with exporters
- `-s, --sudo` - Use sudo for running commands
- `-S, --self-signed` - Create a self-signed certificate
- `-v, --verbose` - Enable verbose output
- `-w, --web` - Web server type (default: nginx, supported: apache, nginx)

## Monitoring with Prometheus

When installed with `-r`, the following monitoring endpoints are available:

- **Prometheus UI**: <http://your-server:9090>
- **Node Exporter** (system metrics): <http://localhost:9100/metrics>
- **Apache Exporter** (if Apache): <http://localhost:9117/metrics>
- **Nginx Exporter** (if Nginx): <http://localhost:9113/metrics>
- **PHP-FPM Exporter** (if FPM): <http://localhost:9253/metrics>

All exporters run as systemd services and start automatically on boot.

## PHP-FPM Pool Configuration

When using PHP-FPM, the script creates dedicated pools for each Moodle site with:

- Separate user permissions
- Optimized resource limits
- Moodle-specific PHP settings
- Security restrictions (open_basedir)
- Dedicated session storage
- Separate error logging

## Moodle Version Compatibility

The script validates PHP versions against Moodle requirements:

- **Moodle 4.5**: Requires PHP 8.1+
- **Moodle 5.0**: Requires PHP 8.2+

## PHP Extensions Installed

Based on official Moodle requirements:

- curl, gd, intl, mbstring, soap, xml, xmlrpc, zip
- sodium (required for Moodle 4.5+)
- opcache (performance)
- ldap (authentication)
- mysqli or pgsql (database)

## Testing on macOS with Podman

Since the script only supports Ubuntu/Debian, use Podman to test in containers:

### Install Podman

```shell
brew install podman
```

### Initialize and start Podman

```shell
podman machine init
podman machine start
```

### Build test containers

```shell
# Build Ubuntu test container
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu .

# Build Debian test container
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian .
```

### Run tests

```shell
# Test on Ubuntu
podman run --platform linux/amd64 -it amp-moodle-ubuntu
# Inside container:
sudo laemp.sh -h  # Show help
sudo laemp.sh -n -v  # Dry run with verbose output
sudo laemp.sh -p -w -m  # Install PHP, Nginx, and Moodle

# Test on Debian
podman run --platform linux/amd64 -it amp-moodle-debian
# Inside container:
sudo laemp.sh -h  # Show help
sudo laemp.sh -n -v  # Dry run with verbose output
sudo laemp.sh -p -w -m  # Install PHP, Nginx, and Moodle
```

### Clean up

```shell
podman machine stop
podman machine rm
```

## Local macOS Development (Limited)

For limited local testing without containers:

[apache2](https://formulae.brew.sh/formula/httpd):

```shell
brew install httpd
```

[PHP](https://formulae.brew.sh/formula/php#default)

```shell
brew install php
```

[certbot](https://formulae.brew.sh/formula/certbot#default)

```shell
brew install certbot
```

Note: The script itself cannot run on macOS as it's designed specifically for Ubuntu/Debian systems.
