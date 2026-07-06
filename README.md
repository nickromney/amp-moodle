# amp-moodle

`laemp.sh` installs LAMP or LEMP plus Moodle on Ubuntu and Debian. The script targets real Linux hosts, so this repo keeps two complementary test paths:

- Slicer VMs for VM-faithful validation with `systemd`, real package lifecycle, and real service startup.
- Docker or Podman containers for broadly available bootstrap and last-mile testing.

Local defaults now split site identity from browser hostname:

- Browser host: `moodle.test.127.0.0.1.sslip.io`
- Moodle domain: `moodle.test`
- Admin email: `demo@moodle.test`

## Quick Start

```bash
# Show help
./laemp.sh -h

# Dry run
./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5021 -S

# Full local install on Ubuntu/Debian
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5021 -S

# Full local install with PostgreSQL, memcached, and monitoring
sudo ./laemp.sh -c -p 8.4 -w nginx -d pgsql -m 5021 -S -M -r

# Locally trusted certificate inside the guest
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5021 --mkcert
```

## Test Strategy

### 1. Fast host-side checks

```bash
bats test_smoke.bats
bats test_laemp.bats
```

These cover syntax, help text, dry-run behavior, and CLI parsing.

### 2. Container testing for broad accessibility

Use Docker or Podman when you want something most contributors can run quickly.

```bash
# Fastest end-to-end Docker check
make docker-baseline

# Broader stock-image integration coverage
docker build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
docker build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .
CONTAINER_RUNTIME=docker bats test_integration.bats
```

The prereqs images are for last-mile configuration testing:

```bash
docker build --platform linux/amd64 -f Dockerfile.prereqs.ubuntu -t amp-moodle-prereqs-ubuntu .
docker build --platform linux/amd64 -f Dockerfile.prereqs.debian -t amp-moodle-prereqs-debian .
```

### 3. Slicer for VM-faithful validation

Use Slicer when the question is "does this behave like a real Ubuntu host?"

```bash
# One supported combo with Playwright smoke
tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5021

# Full supported Slicer matrix
make slicer-matrix
```

The Slicer harness uses the system daemon at `~/slicer-mac`, not repo-local runtime state.

## Docker vs Slicer

They are not substitutes for one another.

- Docker or Podman is the accessible path. It is the right place to test bootstrap logic, stock images, prereqs images, and external-database container flows.
- Slicer is the VM-faithful path. It is the right place to test `systemd`, package post-install behavior, in-guest `mkcert`, Prometheus exporters, and end-to-end Ubuntu behavior.

Current repo state reflects that split:

- `tests/slicer/run-matrix.sh` is the canonical VM matrix runner.
- `tests/docker/run-baseline.sh` is the canonical container baseline runner.
- `test_integration.bats` is the canonical stock-image container runner.
- `compose.yml` is currently centered on the Debian systemd container plus external database services.

## Documentation

- [`tests/README.md`](/Users/nickromney/Developer/personal/amp-moodle/tests/README.md): test entry points and what each tier proves.
- [`docs/container-testing.md`](/Users/nickromney/Developer/personal/amp-moodle/docs/container-testing.md): container-first testing workflow and constraints.
- [`docs/dockerfile-prereqs.md`](/Users/nickromney/Developer/personal/amp-moodle/docs/dockerfile-prereqs.md): stock vs prereqs image model.
- [`HANDOVER.md`](/Users/nickromney/Developer/personal/amp-moodle/HANDOVER.md): current Slicer guidance.
- [`next-steps.md`](/Users/nickromney/Developer/personal/amp-moodle/next-steps.md): active follow-up work.
- [`docs/archive/README.md`](/Users/nickromney/Developer/personal/amp-moodle/docs/archive/README.md): archived generated notes that are no longer current source of truth.
