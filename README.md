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
./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S

# Full local install on Ubuntu/Debian
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5024 -S

# Full local install with PostgreSQL, memcached, and monitoring
sudo ./laemp.sh -c -p 8.4 -w nginx -d pgsql -m 5024 -S -M -r

# Locally trusted certificate inside the guest
sudo ./laemp.sh -c -p 8.4 -w nginx -d mariadb -m 5024 --mkcert
```

## Local Validation Hooks

This repo uses lefthook for local validation before commits and pushes.

```bash
lefthook install
# or, if you prefer the repo Makefile entrypoint:
make hooks
```

Pre-commit checks run fast staged-file validation such as ShellCheck for shell
scripts and YAML linting for YAML files. Pre-push runs the local CI gate from
`lefthook.yml`.

Skip a hook only when you have a specific reason:

```bash
LEFTHOOK=0 git commit ...
LEFTHOOK=0 git push
git commit --no-verify
git push --no-verify
```

No GitHub Actions workflow is active in this checkout. The pre-push gate runs locally; run it manually with:

```bash
lefthook run pre-push --force
```

### Moodle 5.2.4 and 5.3.0

The default is Moodle 5.2.4 (`-m 5024`, tag `v5.2.4`). Moodle 5.3.0 (`-m 5030`,
tag `v5.3.0`) is the next LTS release and is supported on request:

```bash
sudo ./laemp.sh -c -p 8.4 -w nginx -d pgsql -m 5030 -S
```

Four-digit codes install the tagged release package and verify its pinned
sha256; three-digit codes (`502`, `503`) install Moodle's weekly `+` build
instead. Downloads fall back from `download.moodle.org` to
`packaging.moodle.org`.

| Code | Release | PHP | MariaDB | PostgreSQL |
| --- | --- | --- | --- | --- |
| `5024` | 5.2.4 | 8.3-8.4 | 10.11+ | 16+ |
| `5030` | 5.3.0 | 8.3-8.4 | 11.4+ | 17+ |

Moodle 5.3 rejects MariaDB 10.11, which is what Ubuntu 24.04 and Debian 12
ship. `laemp.sh` checks the MariaDB this host would install and stops before
provisioning if it is too old; use Debian 13 (MariaDB 11.8), PostgreSQL
(`-d pgsql`, installs PostgreSQL 17 from the PGDG repository for 5.3), or
stay on 5.2.4. Moodle 5.3 also removes the Classic theme.

### Moodle 4.4.2+

Moodle 4.4.2 and later in the 4.4 line are supported with PHP 8.3:

```bash
sudo ./laemp.sh -c -p 8.3 -w nginx -d mariadb -m 4042 -S
```

Use `-m 4042` for Moodle 4.4.2. Moodle 4.4 uses the application directory as
its web root; Moodle 5.x's `/public` layout is detected and retained.

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
tests/slicer/run-matrix.sh --php 8.4 --web nginx --moodle 5024

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

### Private installer credentials

Admin passwords are saved in a private file, never printed in the progress log.
Read the file with `sudo cat /var/lib/amp-moodle/moodle-admin-credentials.env`.
The parent directory must be owned by root and mode `0700`; files must be regular,
root-owned, mode `0600`, and have one hard link. Symlinks and unsafe overrides are
refused. If a previous version created the state directory with mode `0755`,
first verify that it is a root-owned directory and contains the expected installer
state, then explicitly restrict that directory to mode `0700` before rerunning.
The installer does not change permissions on an arbitrary existing directory.

Database passwords live under `/var/lib/amp-moodle/credentials/`. Reruns reuse the
saved password, including when the database is missing but its user still exists.
A trusted root-owned `0600` legacy `/tmp/<database-user>-db_password` file is copied
into private storage without changing its value or deleting the original. An
existing database user without a trusted saved credential requires password
recovery; the installer stops instead of generating a replacement or deleting
its database. PostgreSQL reruns create only roles and databases that are absent.

Credential-bearing commands suppress their child output because errors can echo
password arguments. Failures are reported without those values. Dry-run mode
skips private writes as well as credential-bearing mutations.

Local security regressions exercise function definitions with synthetic values
and fake database/PHP commands. They do not run the installer entry point:

```sh
python3 -m unittest discover -s tests/security -p 'test_*.py' -v
```

Bash 4 or newer is required by the test harness. Set `amp-moodle_TEST_BASH` when
`bash` on the development machine is an older version.

A new admin credential is staged privately as `moodle-admin-credentials.env.pending`
before the CLI install. The canonical file changes only after installation or an
explicit password reset succeeds. An already-installed response keeps the previous
canonical credential. A failed install leaves the pending file for recovery and
reports its path without printing the password.
