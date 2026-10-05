"""Exercise copied installer functions with harmless sentinel credentials.

By default, extract this repository's current laemp.sh prefix into a
temporary directory. INSTALLER_TEST_ROOT can override that fixture root.
Each functions.sh is laemp.sh before its '# Script
evaluation starts here' marker. No main entry point is invoked. The only
executed installer paths are local fixture credential writes; service,
database and PHP calls are fake Bash functions. All assertions include a
pseudo-terminal because run_command's verbose command logging checks -t 1.
"""
import os
import pty
import select
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

DEFAULT_PROJECT = "amp-moodle"
_prefix_fixture = None
if os.environ.get("INSTALLER_TEST_ROOT"):
    TEST_ROOT = Path(os.environ["INSTALLER_TEST_ROOT"])
    PROJECTS = (DEFAULT_PROJECT,)
else:
    import atexit
    _prefix_fixture = tempfile.TemporaryDirectory(prefix="installer-functions-")
    atexit.register(_prefix_fixture.cleanup)
    TEST_ROOT = Path(_prefix_fixture.name).resolve()
    repository = Path(__file__).resolve().parents[2]
    source = (repository / "laemp.sh").read_text()
    marker = "\n# Script evaluation starts here\n"
    if source.count(marker) != 1:
        raise RuntimeError("installer main-entry marker must occur exactly once")
    prefix = TEST_ROOT / DEFAULT_PROJECT / "functions.sh"
    prefix.parent.mkdir()
    prefix.write_text(source.split(marker)[0])
    PROJECTS = (DEFAULT_PROJECT,)
BASH_BINARY = os.environ.get("INSTALLER_TEST_BASH") or (
    "/opt/homebrew/bin/bash" if Path("/opt/homebrew/bin/bash").is_file()
    else shutil.which("bash") or "/bin/bash"
)
SENTINEL = "SYNTHETIC_CREDENTIAL_ONLY_20261004"


class InstallerSecrecyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()

    def run_functions(self, project, commands, *, level="verbose", credentials=None):
        project = DEFAULT_PROJECT
        folder = self.root / f"{project}-{level}"
        folder.mkdir(exist_ok=True)
        credential_file = credentials or folder / "state" / "moodle-admin-credentials.env"
        log_file = folder / "progress.log"
        prefix = shlex.quote(str(TEST_ROOT / project / "functions.sh"))
        fixture = f"""
export LC_ALL=C LANG=C
export LAEMP_STATE_DIR={shlex.quote(str(folder / 'state'))}
export MOODLE_ADMIN_CREDENTIALS_FILE={shlex.quote(str(credential_file))}
source {prefix}
export LC_ALL=C LANG=C
LOG_LEVEL={shlex.quote(level)}
LOG_FILE={shlex.quote(str(log_file))}
log_to_file=true
USE_SUDO=false
DRY_RUN_CHANGES=false
DB_TYPE=mariadb
DB_PASS={shlex.quote(SENTINEL)}
moodleAdminPassword={shlex.quote(SENTINEL)}
moodleAdminCredentialsFile={shlex.quote(str(credential_file))}
moodleAdminUsername=admin
moodleAdminEmail=fixture@example.invalid
moodleSiteName=fixture.example.invalid
moodlePort=''
moodleDisplayName='Fixture only'
generate_password() {{ printf '%s\\n' {shlex.quote(SENTINEL)}; }}
tool_exists() {{ return 0; }}
mysqladmin() {{ return 0; }}
pg_isready() {{ return 0; }}
package_ensure() {{ return 0; }}
service_manage() {{ return 0; }}
flock() {{ return 0; }}
php() {{
  case "$1" in
    *check_database_schema.php) printf '%s\\n' 'fixture not installed' ;;
    *) printf '%s\\n' 'safe PHP fixture completed' ;;
  esac
}}
sed() {{
  if [[ "${{1:-}}" == '-i' ]]; then
    /usr/bin/python3 - "$2" "$3" <<'PY'
import pathlib,sys
script,path=sys.argv[1:]
_,old,new,_=script.split('|')
p=pathlib.Path(path);p.write_text(p.read_text().replace(old,new))
PY
  else
    /usr/bin/sed "$@"
  fi
}}
{commands}
"""
        script = folder / "fixture.sh"
        script.write_text(fixture)
        master, slave = pty.openpty()
        try:
            child = subprocess.Popen([BASH_BINARY, str(script)], stdout=slave, stderr=slave)
            os.close(slave)
            slave = None
            chunks = []
            deadline = time.monotonic() + 15
            while True:
                if time.monotonic() > deadline:
                    child.kill()
                    child.wait()
                    self.fail("fixture exceeded its 15-second bound")
                ready, _, _ = select.select([master], [], [], 0.2)
                if ready:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    chunks.append(chunk)
                elif child.poll() is not None:
                    break
            status = child.wait(timeout=10)
        finally:
            os.close(master)
            if slave is not None:
                os.close(slave)
        output = b"".join(chunks).decode(errors="replace")
        logged = log_file.read_text() if log_file.exists() else ""
        return status, output, logged, credential_file

    def assert_secret_absent(self, output, logged):
        self.assertNotIn(SENTINEL, output, "ordinary terminal progress exposed a credential")
        self.assertNotIn(SENTINEL, logged, "persistent progress log exposed a credential")

    def test_successful_moodle_install_keeps_admin_secret_out_of_default_and_verbose_progress(self):
        for project in PROJECTS:
            for level in ("info", "verbose"):
                with self.subTest(project=project, level=level):
                    status, output, logged, _ = self.run_functions(
                        project, "moodle_install_database /fixture/moodle", level=level
                    )
                    self.assertEqual(status, 0, output)
                    self.assert_secret_absent(output, logged)

    def test_database_config_replacement_keeps_secret_out_of_tty_command_logs_and_value_logs(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                config = self.root / f"{project}-config.php"
                config.write_text("before\n")
                command = f"replace_file_value before {shlex.quote(SENTINEL)} {shlex.quote(str(config))}"
                status, output, logged, _ = self.run_functions(project, command)
                self.assertEqual(status, 0, output)
                self.assertEqual(config.read_text(), SENTINEL + "\n")
                self.assert_secret_absent(output, logged)

    def test_private_admin_file_is_usable_without_heredoc_command_logging(self):
        status, output, logged, credentials = self.run_functions(
            "laemp", f"write_moodle_admin_credentials admin {shlex.quote(SENTINEL)}"
        )
        self.assertEqual(status, 0, output)
        self.assertIn(SENTINEL, credentials.read_text())
        self.assertEqual(credentials.stat().st_mode & 0o777, 0o600)
        self.assertEqual(credentials.parent.stat().st_mode & 0o777, 0o700)
        self.assert_secret_absent(output, logged)

    @unittest.skip("AMP installer does not expose an explicit reset function")
    def test_explicit_admin_reset_does_not_log_password_argument(self):
        moodle = self.root / "fixture-moodle"
        (moodle / "admin" / "cli").mkdir(parents=True)
        (moodle / "admin" / "cli" / "reset_password.php").write_text("<?php // fixture only\n")
        status, output, logged, _ = self.run_functions(
            "laemp", f"reset_moodle_admin_password {shlex.quote(str(moodle))} admin {shlex.quote(SENTINEL)}"
        )
        self.assertEqual(status, 0, output)
        self.assert_secret_absent(output, logged)

    def test_sensitive_child_output_is_suppressed_and_failure_status_is_preserved(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                command = f"""
secret_echo() {{ printf '%s\\n' {shlex.quote(SENTINEL)}; printf '%s\\n' {shlex.quote(SENTINEL)} >&2; return 17; }}
run_sensitive_command --makes-changes secret_echo
"""
                status, output, logged, _ = self.run_functions(project, command)
                self.assertEqual(status, 17, output)
                self.assert_secret_absent(output, logged)

    def test_sensitive_capture_retains_diagnostics_only_in_memory(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                command = f"""
secret_echo() {{ printf '%s\\n' {shlex.quote(SENTINEL)}; }}
captured=$(run_sensitive_command --capture-output --makes-changes secret_echo)
[[ "$captured" == {shlex.quote(SENTINEL)} ]] || exit 44
"""
                status, output, logged, _ = self.run_functions(project, command)
                self.assertEqual(status, 0, output)
                self.assert_secret_absent(output, logged)

    def test_already_present_database_response_keeps_idempotent_moodle_branch(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                command = f"""
moodleAdminPassword=''
php() {{
  case "$1" in
    *check_database_schema.php) printf '%s\\n' 'fixture not installed' ;;
    *) printf '%s\\n' 'Database tables already present' {shlex.quote(SENTINEL)}; return 1 ;;
  esac
}}
moodle_install_database /fixture/moodle
"""
                status, output, logged, credentials = self.run_functions(project, command)
                self.assertEqual(status, 0, output)
                self.assertFalse(credentials.exists(), "ordinary existing-install branch must not reset credentials")
                self.assert_secret_absent(output, logged)

    def test_actual_php_failure_preserves_last_good_credentials_and_does_not_log_child_output(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                parent = self.root / f"last-good-{project}"
                parent.mkdir(mode=0o700)
                credentials = parent / "admin.env"
                credentials.write_text("LAST GOOD ADMIN CREDENTIAL\n")
                credentials.chmod(0o600)
                command = f"""
moodleAdminPassword=''
php() {{
  case "$1" in
    *check_database_schema.php) printf '%s\\n' 'fixture not installed' ;;
    *) printf '%s\\n' {shlex.quote(SENTINEL)}; printf '%s\\n' {shlex.quote(SENTINEL)} >&2; return 19 ;;
  esac
}}
moodle_install_database /fixture/moodle
"""
                status, output, logged, _ = self.run_functions(project, command, credentials=credentials)
                self.assertNotEqual(status, 0)
                self.assertEqual(credentials.read_text(), "LAST GOOD ADMIN CREDENTIAL\n")
                pending = Path(str(credentials) + ".pending")
                self.assertTrue(pending.exists(), "failed install needs its private recovery credential")
                self.assertEqual(pending.stat().st_mode & 0o777, 0o600)
                self.assertIn(SENTINEL, pending.read_text())
                self.assert_secret_absent(output, logged)

    def test_already_present_database_preserves_last_good_admin_credentials(self):
        for project in PROJECTS:
            with self.subTest(project=project):
                parent = self.root / f"already-good-{project}"
                parent.mkdir(mode=0o700)
                credentials = parent / "admin.env"
                credentials.write_text("LAST GOOD ADMIN CREDENTIAL\n")
                credentials.chmod(0o600)
                command = f"""
moodleAdminPassword=''
php() {{
  case "$1" in
    *check_database_schema.php) printf '%s\\n' 'fixture not installed' ;;
    *) printf '%s\\n' 'Database tables already present' {shlex.quote(SENTINEL)}; return 1 ;;
  esac
}}
moodle_install_database /fixture/moodle
"""
                status, output, logged, _ = self.run_functions(project, command, credentials=credentials)
                self.assertEqual(status, 0, output)
                self.assertEqual(credentials.read_text(), "LAST GOOD ADMIN CREDENTIAL\n")
                self.assertFalse(Path(str(credentials) + ".pending").exists())
                self.assert_secret_absent(output, logged)

    def test_admin_credential_symlink_is_rejected_without_overwriting_target(self):
        target = self.root / "unrelated-file"
        target.write_text("KEEP THIS FILE\n")
        credentials = self.root / "credential-symlink"
        credentials.symlink_to(target)
        status, output, logged, _ = self.run_functions(
            "laemp", f"write_moodle_admin_credentials admin {shlex.quote(SENTINEL)}", credentials=credentials
        )
        self.assertNotEqual(status, 0, "unsafe pre-existing symlink was accepted")
        self.assertEqual(target.read_text(), "KEEP THIS FILE\n")
        self.assert_secret_absent(output, logged)

    def test_permissive_existing_admin_file_is_refused_without_truncation(self):
        parent = self.root / "owned-credential-dir"
        parent.mkdir(mode=0o700)
        credentials = parent / "admin.env"
        credentials.write_text("KEEP EXISTING CREDENTIAL\n")
        credentials.chmod(0o644)
        status, output, logged, _ = self.run_functions(
            "laemp", f"write_moodle_admin_credentials admin {shlex.quote(SENTINEL)}", credentials=credentials
        )
        self.assertNotEqual(status, 0, "broadly readable old credential was accepted")
        self.assertEqual(credentials.read_text(), "KEEP EXISTING CREDENTIAL\n")
        self.assert_secret_absent(output, logged)

    def test_world_writable_admin_directory_is_refused_without_truncation(self):
        parent = self.root / "unsafe-credential-dir"
        parent.mkdir()
        parent.chmod(0o777)
        credentials = parent / "admin.env"
        credentials.write_text("KEEP EXISTING CREDENTIAL\n")
        credentials.chmod(0o600)
        status, output, logged, _ = self.run_functions(
            "laemp", f"write_moodle_admin_credentials admin {shlex.quote(SENTINEL)}", credentials=credentials
        )
        self.assertNotEqual(status, 0, "world-writable parent was accepted")
        self.assertEqual(credentials.read_text(), "KEEP EXISTING CREDENTIAL\n")
        self.assert_secret_absent(output, logged)

    def test_admin_credential_hardlink_is_rejected_without_overwriting_other_name(self):
        target = self.root / "unrelated-hardlinked-file"
        target.write_text("KEEP THIS FILE\n")
        credentials = self.root / "credential-hardlink"
        os.link(target, credentials)
        status, output, logged, _ = self.run_functions(
            "laemp", f"write_moodle_admin_credentials admin {shlex.quote(SENTINEL)}", credentials=credentials
        )
        self.assertNotEqual(status, 0, "unsafe multiply linked credential file was accepted")
        self.assertEqual(target.read_text(), "KEEP THIS FILE\n")
        self.assert_secret_absent(output, logged)


if __name__ == "__main__":
    unittest.main()
