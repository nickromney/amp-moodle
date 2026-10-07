# amp-moodle: agent operating model

Adopted 6 October 2026 from local source and command inspection.
Host-oriented LAMP/LEMP Moodle installer with container and VM validation.

## Read by intent

Start with the local agent guide and build manifest. For domain or behavior
changes, follow the owners below, then the relevant contract/test. These
documents retain product detail and historical evidence:

- [ansible/README.md](../ansible/README.md)
- [docs/README.md](README.md)
- [README.md](../README.md)
- [tests/README.md](../tests/README.md)

## System ownership

| Owner | Responsibility |
| --- | --- |
| [laemp.sh](../laemp.sh) | Host installation intent and package/service changes. |
| [verify-moodle.sh](../verify-moodle.sh) | CLI, database, browser and health acceptance. |
| [tests](../tests) | CLI, database, browser and health acceptance. |
| [test_laemp.bats](../test_laemp.bats) | CLI, database, browser and health acceptance. |
| [ansible](../ansible) | Alternative implementation and historical design. |
| [docs](../docs) | Alternative implementation and historical design. |

Intent selects the owning policy; that policy produces decisions or artifacts;
adapters perform effects; verification establishes the result. Change the
owner once and keep alternate surfaces on that same contract.

## Invariants

- Installer output is not independent verification.
- Containers cannot prove systemd VM lifecycle.

## Existing action interfaces

These are inspected command surfaces, not a report that they ran. Read current
help and recipes for arguments, dependencies and lifecycle hooks before use.
Examples containing placeholder paths or bracketed options are grammar.

| Command | Effects and evidence |
| --- | --- |
| `./laemp.sh -h` | Help only. |
| `./laemp.sh -n -v -p 8.4 -w nginx -d mariadb -m 5024 -S` | Installer preview; does not establish installed Moodle health. |
| `bats test_smoke.bats` | Fast host-side CLI checks. |
| `make docker-baseline` | Build/install/verify container baseline; runtime and downloads required. |

## Observe, verify and retain

Establish source revision, dirty state and relevant input identity before
choosing an action. Keep intended settings, cached artifacts and observed
runtime state distinct. An existing artifact is not a freshness or readiness
claim. Use the smallest deterministic fixture at the changed seam first;
expand to process, browser, device or deployment checks only when that
claim needs them. Record unavailable evidence explicitly.

Retain the command/configuration, source and input identity, result, limitation
and next discriminating check. Reuse evidence only while its relevant inputs
remain applicable. Promote a reproducible failure to a regression fixture,
a design decision to its owning document, and a repeated operator correction
to one concise guide rule. Keep private observations in private artifacts.

## Implemented plan for this pass

- [x] Map current source ownership and existing interfaces.
- [x] Make command effects and evidence limits discoverable.
- [x] Route agent work here and retain detailed product plans at their owners.

Acceptance: owner paths and document links resolve; current instructions
match inspected source; catalog hashes bind this context to the reviewed
bytes. This is documentation/control navigation acceptance. Product runtime
checks retain their own scope and are not certified by this pass.

## Project decisions

The product is laemp.sh; adapters and test platforms surround it. Use help and dry-run to identify the requested PHP/database/Moodle tuple, then use CLI tests for parsing changes, containers for bootstrap/last-mile checks and Slicer for systemd and real service lifecycle. Record the installer revision, OS/image, tuple, hostname, run time and verifier result with any readiness claim. Distinguish generated test identity from a deployable site domain. Keep the Ansible rewrite status separate from the maintained Bash path and link the current next-steps file instead of reactivating archived plans.
