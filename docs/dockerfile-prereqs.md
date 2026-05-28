# Stock vs Prereqs Dockerfiles

This repo keeps two container image styles because they test different parts of `laemp.sh`.

## Stock images

Files:

- `Dockerfile.ubuntu`
- `Dockerfile.debian`

Purpose:

- full bootstrap testing
- repository setup
- package installation
- service wiring on a minimal base image

Typical use:

```bash
docker build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
docker build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .
CONTAINER_RUNTIME=docker bats test_integration.bats
```

Use stock images when the question is "can `laemp.sh` build this machine from near-zero?"

## Prereqs images

Files:

- `Dockerfile.prereqs.ubuntu`
- `Dockerfile.prereqs.debian`

Purpose:

- last-mile configuration testing
- faster iteration on web, PHP, Moodle, and config generation logic
- situations where package bootstrap is already known or intentionally out of scope

Typical use:

```bash
docker build --platform linux/amd64 -f Dockerfile.prereqs.ubuntu -t amp-moodle-prereqs-ubuntu .
docker run -it --rm amp-moodle-prereqs-ubuntu
sudo ./laemp.sh -c -w nginx -d mariadb -m 5013 -S
```

Use prereqs images when the question is "does the remaining configuration logic still work once the packages already exist?"

## Why Keep Both

- Stock images catch bootstrap regressions that prereqs images hide.
- Prereqs images shorten the edit-test loop for configuration work.
- Slicer still remains the VM-faithful path for real Ubuntu behavior.

The right long-term test model is:

1. quick CLI checks on the host
2. stock container tests for accessible bootstrap coverage
3. prereqs container tests for fast last-mile coverage
4. Slicer for VM-faithful release confidence
