---
name: verify-laemp
description: Safely verify LAEMP's CLI entry points without installing services or changing the host.
---

# Verify LAEMP

Run from the repository root with `make verify-dry-run`, `make verify-test`, or `make verify`. `make verify` checks the actual host before starting: on non-Ubuntu/Debian hosts it records a blocker and stops before invoking installer code. On supported hosts it copies the current `laemp.sh` into isolated run state, executes its `--help` path and unsupported-database refusal path, and keeps outputs under `${VERIFY_EVIDENCE_ROOT:-${TMPDIR:-/tmp}/verify-laemp-evidence}/<run-id>`. `make verify-help` runs only the safe help path from a temporary copy on any host.

Cleanup removes only the copied script and run state. Evidence remains available after the run.

This check does not provision PHP, a web server, a database, Moodle, certificates, monitoring, or containers. It does not validate a deployed Moodle site. The installer requires Ubuntu or Debian and should only be run on a deliberately provisioned, attended test host.
