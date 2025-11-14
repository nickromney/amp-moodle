# Ansible scaffolding for laemp containers

This directory keeps the minimum files required to aim Ansible at the same Podman containers that `laemp.sh` provisions. The goal is to compare bash vs IaC outcomes with as little friction as possible.

## Layout

| File/Dir | Purpose |
| --- | --- |
| `ansible.cfg` | Points Ansible at the local inventory, enables useful callbacks. |
| `requirements.yml` | Roles and collections (Moodle role + Podman connection plugin). |
| `inventory/containers.ini` | Static inventory entries for the Podman containers created by `compose.yml`. |
| `group_vars/all.yml` | Shared defaults so Ansible and laemp agree on domains, paths, DB creds. |
| `playbooks/container-verify.yml` | Collects service/package/file data + runs `verify-moodle.sh`, writing JSON snapshots for diffing. |
| `.artifacts/` | Auto-created directory where snapshots live. |

## Usage

1. Provision a container with `laemp.sh` (the Makefile targets `debian`, `ubuntu`, etc. already do this).
2. Install Ansible dependencies once: `ansible-galaxy install -r ansible/requirements.yml`.
3. Run the verify playbook against the running container:

   ```bash
   cd ansible
   ansible-playbook playbooks/container-verify.yml
   ```

   This produces JSON dumps under `ansible/.artifacts/` for each host, capturing:

   - Output from `/usr/local/bin/verify-moodle.sh`
   - Checksums/ownership for `config.php` and `moodledata`
   - Running services (`nginx`, `php*-fpm`, etc.)
   - Installed packages list (for high-level parity)
   - HTTP probe results against `https://localhost:8443` inside the container

4. Re-run after applying your Ansible playbook (or laemp run) and diff the JSON files to spot drift:

   ```bash
   diff -u .artifacts/laemp-test-debian-*.json  # pick the two snapshots
   ```

## Next steps

- Drop in your `site.yml`/roles beside `playbooks/container-verify.yml` and use the same inventory to configure the containers via Ansible.
- Extend the verify playbook with `copy`/`synchronize` tasks to export entire directories if you need byte-for-byte comparisons.
- Wire a `make ansible-verify` target that runs the container, executes Ansible, and compares snapshots end-to-end.
