# PHP installation security check

The installer checks the selected PHP CLI against the PHP2Shell upstream floors:
8.2.35, 8.3.36, 8.4.27, and 8.5.12. For FPM it also requires the binary's
major, minor, and patch to match the CLI. Apache without FPM checks the installed
`libapache2-mod-php` package version and requires the same upstream patch as the
CLI. `--check-php-security` checks the default 8.4 CLI and FPM without installing
packages. Both prerequisite Dockerfiles run it after installing PHP.

The checks inspect local binaries and package metadata. They do not establish the
version of a running service or a deployed image. Dry runs skip binary checks and
must not be treated as proof of installed versions.

One below-floor backport is accepted: [Ubuntu USN-8948-1](https://ubuntu.com/security/notices/USN-8948-1)
identifies `8.3.6-0ubuntu0.24.04.13` for Ubuntu 24.04 CLI, FPM, and Apache
packages as fixed for CVE-2026-109618 and CVE-2026-109619. The check requires
that exact release and installed package version, ownership of the selected
binary or module, and an actual file checksum matching exactly one recorded
package checksum for that file. It trusts the local operating system and dpkg metadata, as the
installer already trusts its package manager. It is not remote attestation.
Unrecognized versions, unowned files, missing checksums, and modified executable
files are refused. Other backports remain blocked until separately reviewed.
