# Testing Guide

This repo uses both containers and VMs because they answer different questions.

- Containers are the widely available path. Use them for fast bootstrap and last-mile checks.
- Slicer VMs are the VM-faithful path. Use them for real Ubuntu behavior, `systemd`, exporter wiring, guest trust stores, and browser smoke against a live guest.

## Test Tiers

### 1. Smoke tests

Fast host-side validation.

```bash
bats test_smoke.bats
```

Covers script shape, syntax, help output, and basic static checks.

### 2. CLI parsing tests

Host-side BATS tests that exercise dry-run parsing and option combinations.

```bash
bats test_laemp.bats
```

### 3. Docker baseline

The first Docker path to reach for is the Slicer-proven baseline: Debian stock image, PHP 8.4, nginx, MariaDB, Moodle 5.1.3, self-signed TLS.

```bash
make docker-baseline
```

This runner builds the stock Debian image if needed, starts an isolated container, executes `laemp.sh`, and writes logs plus verification artifacts to `/tmp`.

### 4. Container integration tests

For broader stock-image coverage, use the BATS integration suite.

```bash
docker build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
docker build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .
CONTAINER_RUNTIME=docker bats test_integration.bats
```

If you use Podman instead:

```bash
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .
CONTAINER_RUNTIME=podman bats test_integration.bats
```

### 5. Browser tests against a running target

The Playwright suite assumes Moodle is already up.

```bash
npm install
npx playwright install chromium

# Then point Playwright at a running site
MOODLE_URL=https://moodle.test.127.0.0.1.sslip.io npm test
```

Set credentials through environment variables or `.env.test.local`:

```bash
MOODLE_ADMIN_USERNAME=admin
MOODLE_ADMIN_PASSWORD=...
MOODLE_ADMIN_EMAIL=demo@moodle.test
MOODLE_URL=https://moodle.test.127.0.0.1.sslip.io
```

### 6. Slicer matrix plus Playwright smoke

Provision a fresh VM per combo, run `laemp.sh`, then run Playwright smoke against the live guest.

```bash
npm install
npx playwright install chromium

tests/slicer/run-matrix.sh
tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5013
tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5013 --database pgsql --extra-flag -M
```

The repo also exposes:

```bash
make slicer
make slicer-test-bats
make slicer-matrix
```

## Compose Notes

`compose.yml` is useful for the current Debian systemd container and external database services.

Today it is not a full stock Ubuntu matrix. If you want broad Docker coverage, use:

- `test_integration.bats` for stock-image runs
- the prereqs Dockerfiles for last-mile container runs
- `compose.yml` where you specifically want the Debian systemd or external-database flow

## What Each Path Proves

- `test_smoke.bats`: script integrity and obvious regressions
- `test_laemp.bats`: CLI surface and dry-run behavior
- `tests/docker/run-baseline.sh`: one honest end-to-end container bootstrap
- `test_integration.bats`: container bootstrap behavior on stock images
- Playwright: user-facing Moodle behavior against a running target
- Slicer matrix: real Ubuntu provisioning behavior

## Troubleshooting

### Container tests fail early

```bash
docker ps -a
docker rm -f $(docker ps -a --filter name=laemp-test -q)
```

For Podman:

```bash
podman ps -a
podman rm -f $(podman ps -a --filter name=laemp-test -q)
```

### Playwright cannot connect

Check the exact URL being tested.

```bash
echo "$MOODLE_URL"
curl -k "$MOODLE_URL"
```

For local container or VM testing, prefer the current host pattern:

- `https://moodle.test.127.0.0.1.sslip.io`
- or the VM-specific form `https://moodle.test.<vm-ip>.sslip.io`

### Slicer tests fail

Use the system daemon under `~/slicer-mac` and inspect the per-run artifacts emitted by `tests/slicer/run-matrix.sh`.
