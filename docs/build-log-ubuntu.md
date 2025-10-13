# Ubuntu 24.04 LTS (Noble Numbat) Container Build Log

Build log for amp-moodle-ubuntu:24.04 container image.

**Build Date:** October 13, 2025
**Base Image:** ubuntu:24.04
**Platform:** linux/amd64
**Final Image:** localhost/amp-moodle-ubuntu:24.04

## Build Summary

- **Total Steps:** 18
- **Base System:** Ubuntu 24.04 LTS (Noble Numbat)
- **Packages Installed:** 163 new packages
- **Packages Upgraded:** 2 packages
- **Archive Size:** 68.7 MB
- **Disk Space Used:** 271 MB additional

## Build Steps

### Step 1: Base Image
```
FROM ubuntu:24.04
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
    wget curl gnupg lsb-release software-properties-common sudo tar unzip \
    locales bats git
```

#### Repositories Fetched
- http://security.ubuntu.com/ubuntu noble-security InRelease (126 kB)
- http://archive.ubuntu.com/ubuntu noble InRelease (256 kB)
- http://archive.ubuntu.com/ubuntu noble-updates InRelease (126 kB)
- http://archive.ubuntu.com/ubuntu noble-backports InRelease (126 kB)

**Total Downloaded:** 34.0 MB in 3s (9981 kB/s)

#### Key Packages Installed

**Python 3 (Ubuntu-specific):**
- python3 3.12.3-0ubuntu2
- python3.12 3.12.3-1ubuntu0.8
- python3-apt 2.7.7ubuntu5
- python3-software-properties 0.99.49.3
- Multiple Python dependencies (blinker, cryptography, jwt, oauthlib, etc.)

**Testing & Development:**
- bats 1.10.0-1
- git 1:2.43.0-1ubuntu7.3
- bash-completion (via dependency)

**System Tools:**
- sudo 1.9.15p5-3ubuntu5.24.04.1
- systemd 255.4-1ubuntu8.11
- systemd-resolved 255.4-1ubuntu8.11
- dbus 1.14.10-4ubuntu4.1
- procps (via dependency)

**Network & Security:**
- curl 8.5.0-2ubuntu10.6
- wget 1.21.4-1ubuntu4.1
- openssh-client 1:9.6p1-3ubuntu13.14
- openssl 3.0.13-0ubuntu3.6
- ca-certificates 20240203
- gnupg 2.4.4-2ubuntu17.3

**Ubuntu-specific Packages:**
- software-properties-common 0.99.49.3
- distro-info-data 0.60ubuntu0.3
- networkd-dispatcher 2.2.4-1
- unattended-upgrades 2.9.1+nmu4ubuntu1
- appstream 1.0.2-1build6
- packagekit 1.2.8-2ubuntu1.2

**Libraries:**
- perl 5.38.2-3.2ubuntu0.2
- libssl3t64 (via openssl)
- libcurl4t64 8.5.0-2ubuntu10.6
- libgnutls30t64 (via dependencies)
- libicu74 74.2-1ubuntu3.1 (large, 10.9 MB)
- libxml2 2.9.14+dfsg-1.3ubuntu3.5
- libglib2.0-0t64 2.80.0-6ubuntu3.4

**Compression:**
- xz-utils 5.6.1+really5.4.5-1ubuntu0.2
- unzip 6.0-28ubuntu4.1
- tar 1.35+dfsg-3build1

### Step 5: Locale Generation
```bash
locale-gen en_US.UTF-8
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

**Image ID:** [Generated at build time]
**Tag:** localhost/amp-moodle-ubuntu:24.04

## Notable Features

### Systemd Integration
- systemd 255.4-1ubuntu8.11 installed
- systemd-resolved enabled (Ubuntu-specific)
- systemd-timesyncd enabled
- D-Bus system bus configured
- dbus-user-session included (Ubuntu-specific)

### Python 3 Ecosystem (Ubuntu Default)
Ubuntu 24.04 includes Python 3.12 as system Python with extensive libraries:
- Core Python 3.12.3
- python3-apt for package management integration
- python3-software-properties for PPA management
- python3-launchpadlib for Launchpad API access
- Multiple cryptography and authentication libraries

### Ubuntu-specific Features

#### Software Properties
- software-properties-common - Manage PPAs and repositories
- python3-software-properties - Python API for repository management
- add-apt-repository command available

#### Package Management
- appstream - Application metadata indexing
- packagekit - Universal package management abstraction
- unattended-upgrades - Automatic security updates

#### Network Management
- networkd-dispatcher - Event dispatcher for systemd-networkd
- systemd-resolved - DNS resolution service

### Security Updates
Multiple packages from ubuntu-security and ubuntu-updates repositories

## Comparison: Ubuntu vs Debian

| Feature | Ubuntu 24.04 | Debian 13 |
|---------|--------------|-----------|
| **Base Size** | ~75 MB | ~80 MB |
| **Packages Installed** | 163 | 115 |
| **Archive Downloaded** | 68.7 MB | 57.4 MB |
| **Disk Space Used** | 271 MB | 219 MB |
| **Python Included** | ✓ Python 3.12 (system) | ✗ No Python by default |
| **Git Version** | 2.43.0 | 2.47.3 |
| **Perl Version** | 5.38.2 | 5.40.1 |
| **BATS Version** | 1.10.0 | 1.11.1 |
| **Systemd Version** | 255.4 | 257.8 |
| **OpenSSL Version** | 3.0.13 | 3.5.1 |
| **Curl Version** | 8.5.0 | 8.14.1 |
| **software-properties** | ✓ Included | ✗ Not available |
| **networkd-dispatcher** | ✓ Included | ✗ Not available |
| **unattended-upgrades** | ✓ Included | ✗ Not available |
| **PPA Support** | ✓ Native | ✗ Manual only |

### Key Differences

#### Ubuntu Advantages:
1. **Python Ecosystem:** System Python 3.12 with extensive libraries pre-installed
2. **PPA Support:** Native add-apt-repository command for third-party repositories
3. **Package Abstractions:** PackageKit and AppStream for universal package management
4. **Automatic Updates:** unattended-upgrades pre-configured
5. **Network Management:** networkd-dispatcher for network event handling
6. **User Experience:** More polished desktop/server hybrid tooling

#### Debian Advantages:
1. **Smaller Size:** 52 MB less disk space used (219 MB vs 271 MB)
2. **Faster Download:** 11.3 MB less to download (57.4 MB vs 68.7 MB)
3. **Fewer Dependencies:** 115 vs 163 packages installed
4. **Newer Software:** Git 2.47.3 (vs 2.43.0), OpenSSL 3.5.1 (vs 3.0.13), Curl 8.14.1 (vs 8.5.0)
5. **Minimal Approach:** No Python bloat, cleaner base system
6. **Pure Debian:** No Ubuntu-specific abstractions or wrappers

### Software Version Comparison

**Newer in Ubuntu:**
- None (Ubuntu 24.04 released April 2024, Debian 13 released August 2025)

**Newer in Debian:**
- Git: 2.47.3 vs 2.43.0 (4 minor versions newer)
- OpenSSL: 3.5.1 vs 3.0.13 (5 minor versions newer)
- Curl: 8.14.1 vs 8.5.0 (9 minor versions newer)
- Perl: 5.40.1 vs 5.38.2 (2 minor versions newer)
- BATS: 1.11.1 vs 1.10.0 (1 minor version newer)
- Systemd: 257.8 vs 255.4 (2 major versions newer)

### Package Count Breakdown

**Ubuntu-only packages (not in Debian minimal install):**
- Python 3 and 40+ Python libraries
- software-properties-common and python3-software-properties
- appstream and packagekit stack
- networkd-dispatcher
- unattended-upgrades
- polkitd and related PolicyKit components
- Multiple GObject introspection libraries (gir1.2-*)
- libicu74 (10.9 MB internationalization library)

## Build Performance

- **Cache Hits:** Steps 2-3 used cached layers
- **Network Speed:** 9981 kB/s average (vs 5421 kB/s Debian)
- **Package Installation:** ~30 seconds (vs ~26 seconds Debian)
- **Total Build Time:** ~60 seconds (vs ~45 seconds Debian)

## Usage

### Build Command
```bash
podman build --platform linux/amd64 \
  -f Dockerfile.ubuntu \
  -t amp-moodle-ubuntu:24.04 .
```

### Run Command
```bash
podman run --rm -it amp-moodle-ubuntu:24.04
```

### Test laemp.sh
```bash
podman run --rm -it amp-moodle-ubuntu:24.04 laemp.sh --help
```

### Run BATS Tests
```bash
podman run --rm -it amp-moodle-ubuntu:24.04 bats /app/test_laemp.bats
```

### Use PPA (Ubuntu-specific)
```bash
podman run --rm -it amp-moodle-ubuntu:24.04 bash
# Inside container:
sudo add-apt-repository ppa:ondrej/php
```

## Recommendations

### When to Use Ubuntu Container:
- Testing with Ubuntu-specific tools (add-apt-repository, etc.)
- Need Python 3 in base system
- Want automatic security updates (unattended-upgrades)
- Prefer PackageKit abstraction layer
- Testing Ubuntu LTS for production deployment

### When to Use Debian Container:
- Want minimal base system (52 MB smaller)
- Don't need Python in base layer
- Prefer latest software versions
- Want pure Debian experience
- Need faster build times (15 seconds faster)
- Minimizing container image size

## Notes

### Debconf Warning (Non-Critical)
```
debconf: delaying package configuration, since apt-utils is not installed
```
**Impact:** Package configuration prompts are suppressed (expected behavior in containers)

### Python in Base System
Ubuntu 24.04 includes Python 3.12 as system Python, adding:
- 40+ Python packages
- ~50 MB to final image size
- Useful for: apt operations, software-properties, launchpadlib integration
- Trade-off: Larger base but more functionality out-of-the-box

## Next Steps

1. Compare laemp.sh behavior between Ubuntu and Debian
2. Test PPA functionality (Ubuntu-specific ondrej/php, ondrej/apache2)
3. Verify all services start correctly on both platforms
4. Run integration test suite on both containers
5. Document any Ubuntu vs Debian differences in laemp.sh behavior
6. Test systemd-resolved DNS differences

## Related Documentation

- [Container Testing Guide](container-testing.md)
- [Dockerfile Comparison](dockerfile-comparison.md)
- [Build Optimization Guide](dockerfile-optimization.md)
- [Debian Build Log](build-log-debian.md)
