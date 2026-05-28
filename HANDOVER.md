# Slicer Handover

This repo uses Slicer as the VM-faithful test path for `laemp.sh`.

The current direction is simple:

- keep this repo centered on `laemp.sh` as a sudo-requiring shell script
- use real Ubuntu guests or cloud VPS hosts for the most faithful validation
- use Docker or Podman where container testing is useful and honest
- do not treat Slicer and Docker as interchangeable

## Current Slicer Rules

- Use the system daemon under `~/slicer-mac`.
- Do not create repo-local Slicer runtime state.
- Prefer native `slicer vm exec`, `slicer vm cp`, and `slicer vm shell`.

The repo-owned Slicer entry points are:

- [`tests/slicer/run-test.sh`](/Users/nickromney/Developer/personal/amp-moodle/tests/slicer/run-test.sh)
- [`tests/slicer/test-laemp.sh`](/Users/nickromney/Developer/personal/amp-moodle/tests/slicer/test-laemp.sh)
- [`tests/slicer/run-matrix.sh`](/Users/nickromney/Developer/personal/amp-moodle/tests/slicer/run-matrix.sh)
- [`Makefile`](/Users/nickromney/Developer/personal/amp-moodle/Makefile)

## What Slicer Is For

Use Slicer when the question is:

- does this work on a real Ubuntu guest?
- do services come up correctly under `systemd`?
- do package post-install hooks behave correctly?
- does in-guest `mkcert` or Prometheus wiring work?

## What Docker Is For

Use Docker or Podman when the question is:

- can contributors run this easily without Slicer?
- does bootstrap logic still work on stock container images?
- does the last-mile config logic still work on prereqs images?

## Operational Notes

- The current browser host pattern is `moodle.test.<ip>.sslip.io`.
- The Moodle identity remains `moodle.test`.
- A 4 GiB guest was sufficient for the green `php 8.4 + nginx + moodle 5013` Slicer run.
- More headroom may still help heavier combinations such as monitoring plus browser checks.

## Practical Default

The healthy split for this repo is:

1. fast host-side checks for CLI and smoke coverage
2. Docker or Podman for accessible container coverage
3. Slicer for VM-faithful confidence before calling a path good
