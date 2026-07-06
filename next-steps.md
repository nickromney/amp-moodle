# Next Steps

The next pass should stay narrow: one Docker baseline that anyone can run, while Slicer remains the VM-faithful confidence path.

## Current Position

- Slicer is still the trusted path for real Ubuntu and VPS-like behavior.
- Docker or Podman is the accessible path for quick bootstrap validation.
- The two paths should complement each other, not pretend to prove the same things.

## Immediate Goal

Keep the Docker path centered on the one container case that has a clear purpose:

- `php 8.4 + nginx + mariadb + moodle 5021 + self-signed`

That case is useful because it tells us whether `laemp.sh` can bootstrap a realistic Debian-based host image in a way that is likely to transfer to a VPS.

## What To Keep Building

### 1. A repo-owned Docker baseline runner

The container path should be runnable without hand-held context:

- build the Debian stock image if needed
- start an isolated container
- execute `laemp.sh` with the baseline flags
- capture logs and verification artifacts
- return pass or fail clearly

### 2. A clear boundary document

Keep one short document that states what Docker can prove here and what still needs Slicer.

## What Not To Force

- a broad Docker matrix if the cases are not honest in containers
- a fake Ubuntu compose matrix that does not reflect how contributors will really run it
- a FrankenPHP path unless `laemp.sh` explicitly grows a `caddy` or `frankenphp` backend

## FrankenPHP Note

The official FrankenPHP image is interesting for a future container-specific path, but it is not a drop-in substrate for the current `laemp.sh` baseline. The script currently targets nginx or Apache with system packages and service management, while FrankenPHP is a separate Caddy-based runtime.

## Exit Criteria

This Docker pass is complete when:

1. the Debian stock baseline is reproducible by another developer
2. the baseline command and artifacts are documented explicitly
3. Docker remains a quick validation path, not a pretend substitute for real VM coverage
