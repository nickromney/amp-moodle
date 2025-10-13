# Debian 13 (Trixie) Container Build Log

Build log for amp-moodle-debian:13 container image.

**Build Date:** October 13, 2025
**Base Image:** debian:13
**Platform:** linux/amd64
**Final Image:** localhost/amp-moodle-debian:13

## Build Summary

- **Total Steps:** 18
- **Base System:** Debian 13 (Trixie)
- **Packages Installed:** 115 new packages
- **Packages Upgraded:** 2 packages
- **Archive Size:** 57.4 MB
- **Disk Space Used:** 219 MB additional

## Build Steps

### Step 1: Base Image

```dockerfile
FROM debian:13
```

### Step 2-3: Environment Configuration

```bash
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
```

### Step 4: Package Installation

#### Package Manager Update

```bash
apt-get update && apt-get install -y \
    wget curl gnupg lsb-release sudo tar unzip \
    locales ca-certificates bats git
```

#### Repositories Fetched

- <http://deb.debian.org/debian> trixie InRelease (140 kB)
- <http://deb.debian.org/debian> trixie-updates InRelease (47.3 kB)
- <http://deb.debian.org/debian-security> trixie-security InRelease (43.4 kB)
- <http://deb.debian.org/debian> trixie/main amd64 Packages (9669 kB)

**Total Downloaded:** 9959 kB in 2s (5421 kB/s)

#### Key Packages Installed

**Testing & Development:**

- bats 1.11.1-1
- git 1:2.47.3-0+deb13u1
- bash-completion 1:2.16.0-7

**System Tools:**

- sudo 1.9.16p2-3
- systemd 257.8-1~deb13u2
- dbus 1.16.2-2
- procps 2:4.0.4-9

**Network & Security:**

- curl 8.14.1-2
- wget 1.25.0-2
- openssh-client 1:10.0p1-7
- openssl 3.5.1-1+deb13u1
- ca-certificates 20250419
- gnupg 2.4.7-21

**Libraries:**

- perl 5.40.1-6
- libssl3t64 3.5.1-1+deb13u1
- libcurl4t64 8.14.1-2
- libgnutls30t64 3.8.9-3

**Compression:**

- xz-utils 5.8.1-1
- unzip 6.0-29
- tar 1.35+dfsg-3.1

### Step 5: Locale Generation

```bash
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
```

**Output:** Locale en_US.UTF-8 generated successfully

### Step 6: Locale Environment Variables

```bash
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
```

### Step 7: Directory and User Setup

```bash
RUN mkdir -p /app /var/log/laemp /moodledata /var/www/moodle \
    && chmod 1777 /tmp \
    && useradd -m -s /bin/bash testuser \
    && echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser
```

**Created Directories:**

- `/app` - Application directory
- `/var/log/laemp` - Log directory
- `/moodledata` - Moodle data directory
- `/var/www/moodle` - Moodle web root

**User Created:**

- Username: testuser
- Shell: /bin/bash
- Home: /home/testuser
- Sudo: Passwordless access

### Step 8-9: Copy and Configure laemp.sh

```bash
COPY laemp.sh /usr/local/bin/laemp.sh
RUN chmod +x /usr/local/bin/laemp.sh
```

### Step 10-11: Copy and Configure setup-security.sh

```bash
COPY setup-security.sh /usr/local/bin/setup-security.sh
RUN chmod +x /usr/local/bin/setup-security.sh
```

### Step 12-14: Copy Test Files

```bash
COPY test_laemp.bats /app/test_laemp.bats
COPY test_integration.bats /app/test_integration.bats
COPY test_smoke.bats /app/test_smoke.bats
```

### Step 15: Set Working Directory

```bash
WORKDIR /app
```

### Step 16: Define Volumes

```bash
VOLUME ["/var/log/laemp", "/moodledata", "/var/www/moodle"]
```

### Step 17: Switch to Non-Root User

```bash
USER testuser
```

### Step 18: Default Command

```bash
CMD ["/bin/bash"]
```

## Final Image

**Image ID:** b9f06ab7d65abf6c1f91f7d93bc1e91bc3a48af55aa2d43a1f6330a36e0b7ff9
**Tag:** localhost/amp-moodle-debian:13

## Notable Features

### Systemd Integration

- systemd 257.8-1~deb13u2 installed
- systemd-timesyncd enabled
- systemd-cryptsetup included
- D-Bus system bus configured

### Security Updates

- OpenSSL 3.5.1-1+deb13u1 (from trixie-security)
- libssl3t64 3.5.1-1+deb13u1 (from trixie-security)
- openssl-provider-legacy 3.5.1-1+deb13u1

### Development Tools

- Git with full internationalization support
- BATS testing framework
- Bash completion enabled
- SSH client for remote operations

### Warnings and Notes

#### Update-alternatives Warnings (Non-Critical)

During xz-utils installation, several man page symlinks were skipped:

- lzma, unlzma, lzcat, lzmore, lzless, lzdiff, lzcmp, lzgrep, lzegrep, lzfgrep

**Impact:** Documentation links missing, but functionality intact

#### Systemd in Container

```text
A chroot environment has been detected, udev not started.
```

**Impact:** udev not available in container environment (expected behavior)

## Build Performance

- **Cache Hits:** Steps 2-3 used cached layers
- **Network Speed:** 5421 kB/s average
- **Package Installation:** 26 seconds
- **Total Build Time:** ~45 seconds (estimated)

## Comparison with Ubuntu Build

| Feature | Debian 13 | Ubuntu 24.04 |
|---------|-----------|--------------|
| Base Size | ~80 MB | ~75 MB |
| Packages Installed | 115 | ~120 |
| Systemd Version | 257.8 | 257.x |
| Git Version | 2.47.3 | 2.43.x |
| Perl Version | 5.40.1 | 5.38.x |
| BATS Version | 1.11.1 | 1.11.x |

## Usage

### Build Command

```bash
podman build --platform linux/amd64 \
  -f Dockerfile.debian \
  -t amp-moodle-debian:13 .
```

### Run Command

```bash
podman run --rm -it amp-moodle-debian:13
```

### Test laemp.sh

```bash
podman run --rm -it amp-moodle-debian:13 laemp.sh --help
```

### Run BATS Tests

```bash
podman run --rm -it amp-moodle-debian:13 bats /app/test_laemp.bats
```

## Next Steps

1. Test laemp.sh installation in container
2. Verify all services start correctly
3. Run integration test suite
4. Compare with Ubuntu container behavior
5. Document any Debian-specific issues

## Related Documentation

- [Container Testing Guide](container-testing.md)
- [Dockerfile Comparison](dockerfile-comparison.md)
- [Build Optimization Guide](dockerfile-optimization.md)
