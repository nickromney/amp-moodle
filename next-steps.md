# Next Steps: laemp.sh vs Ansible Container Parity

This checklist captures the work still outstanding so we can resume quickly next time.

## 1. Get the Systemd Container Stable

1. Rebuild the Debian image after ensuring `systemd/laemp-installer.service` exports `HOME=/root` (Composer needs it), then `podman-compose down` / `podman-compose up -d postgres-db moodle-test-debian`.
2. Watch `journalctl -u laemp-installer.service -f` inside the container until laemp either succeeds or fails, and capture `/usr/local/bin/logs/install.log`.
3. If the service still fails, check the last few lines of `install.log` and adjust `entrypoint-laemp.sh` / environment variables accordingly (e.g., confirm DB waits, policy-rc removal, etc.).

## 2. Capture a Fresh laemp Snapshot

1. Once laemp completes successfully, run:

   ```bash
   cd ansible
   ansible-playbook playbooks/container-verify.yml -l laemp-test-debian
   ```

2. Note the generated artifact path under `ansible/.artifacts/`—this is the “laemp baseline” for this cycle.

## 3. Run the Ansible Converge Play

1. Execute the shim converge play:

   ```bash
   cd ansible
   ansible-playbook playbooks/site.yml -l laemp-test-debian
   ```

2. Re-run the verify play to produce a second artifact, then `diff -u ansible/.artifacts/laemp-test-debian-*.json` to see what changed. The only expected drift right now is the diagnostic packages (`iproute2` family); anything else points to laemp vs Ansible differences.

## 4. Expand Beyond the Shim

1. Replace `playbooks/site.yml` with the real role stack (geoffreyvanwyk.moodle + support roles). Point it at the same Podman inventory so we exercise the actual IaC flow.
2. Update `group_vars/all.yml` to include git deployment variables, plugin lists, etc., mirroring laemp defaults.
3. Once the full playbook converges, repeat the verify/diff step to ensure Ansible brings the container to the same state as laemp.

## 5. Automate the Loop

1. Add a `make ansible-verify` target that performs:
   - `podman-compose down`
   - `podman-compose up -d postgres-db moodle-test-debian`
   - `ansible-playbook playbooks/container-verify.yml`
   - `ansible-playbook playbooks/site.yml`
   - Second verify + `diff`
2. Document the workflow in `README.md` so future runs are “make && inspect diff”.

## 6. Optional Follow-ups

- Add a Molecule scenario based on the new Dockerfile to validate laemp + Ansible end-to-end.
- Start wiring WordPress/Moodle git deployment variables (per the `ansible-role-moodle` instructions) once the baseline loop is stable.
- Consider shipping the systemd-enabled Debian image to a registry so CI can reuse it.
