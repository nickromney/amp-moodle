# Docs

Current docs are kept small and operational:

- [`container-testing.md`](./container-testing.md): container-first testing guidance for Docker/Podman.
- [`dockerfile-prereqs.md`](./dockerfile-prereqs.md): why the stock and prereqs images both exist.
- [`archive/README.md`](./archive/README.md): historical notes and generated planning docs that are not current source of truth.

The repo-level docs are:

- [`README.md`](../README.md): project overview and the canonical entry points.
- [`HANDOVER.md`](../HANDOVER.md): current Slicer notes.
- [`next-steps.md`](../next-steps.md): active follow-up work, currently focused on Docker parity with the Slicer-proven path.

## Current installer and verification map

| Concern | Owner / focused command | Acceptance boundary |
| --- | --- | --- |
| Named PHP/database/Moodle tuple | `laemp.sh`; `bats test_laemp.bats` | Parsing and dry-run fixture behavior, without host installation |
| Smoke/help | `bats test_smoke.bats` | CLI help and syntax |
| TLS prerequisites | `bats test_tls_preflight.bats` | Stubbed certificate/preflight behavior |
| Container bootstrap | `make docker-baseline`; `docs/container-testing.md` | Package/application bootstrap in a container; downloads and runtime required |
| Real service lifecycle | `tests/README.md` Slicer strand | Attended guest with systemd, install and verifier/browser evidence |
| Ansible alternative | `ansible/README.md` | A separate implementation strand, not proof of Bash parity |

Use Moodle `5024` examples with PHP 8.4 and the selected supported database,
as in the current root README. Historical `501` examples do not identify the
current baseline. Consult `HANDOVER.md` and `next-steps.md` for current work;
`docs/archive/` is dated evidence.
