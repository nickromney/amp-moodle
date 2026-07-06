# FrankenPHP Feasibility

This repo now has a rerunnable FrankenPHP spike for the narrow Docker baseline:

- PHP `8.4`
- Moodle `5.2.1`
- MariaDB
- plain HTTP in Docker

Run it with:

```bash
make docker-frankenphp-spike
```

or:

```bash
tests/docker/run-frankenphp-spike.sh
```

## What Works

The spike builds a `dunglas/frankenphp:php8.4-bookworm` image, installs the missing Moodle PHP extensions, installs Moodle `5.2.1`, provisions a MariaDB sidecar, runs the Moodle CLI installer, and verifies:

- `HTTP 200` from the running site
- a live login page
- at least `400` Moodle tables in the database

In local validation, the working run reached `489` Moodle tables.

## What Needed Changing

FrankenPHP was not a drop-in replacement for the existing `nginx` or `apache` branches.

The spike only worked after applying these FrankenPHP-specific choices:

- use a dedicated image with Moodle extensions added (`gd`, `intl`, `mysqli`, `pdo_mysql`, `soap`, `zip`, `ldap`)
- set PHP `max_input_vars=5000` and `memory_limit=256M`
- install Moodle with `--dbtype=mariadb`
- create the MariaDB database with `utf8mb4_unicode_ci`

That last point matters: MariaDB `11.8` accepts `utf8mb4_uca1400_ai_ci` as a database default, but Moodle's install-time Unicode check does not recognise that value reliably in this container path.

## Why This Is Not Yet A `laemp.sh` Backend

`laemp.sh` is currently shaped around real Debian or Ubuntu VMs:

- `apache` or `nginx`
- optional PHP-FPM
- `systemd` service management
- certbot or self-signed certificate flows
- host-level Prometheus exporters

FrankenPHP is a different runtime model:

- Caddy-based app server, not `nginx` or `apache`
- no PHP-FPM requirement in the normal path
- container-first operational model
- different TLS story
- different monitoring and service-management expectations

That makes FrankenPHP a good candidate for either:

- a separate `frankenphp-moodle` project, or
- a deliberate third backend in `laemp.sh` after a larger refactor

It does not look like a safe "add one more web flag" change.
