"""Safe-storage contracts tested using copied definitions and temporary files.

The only /tmp paths created are unique synthetic legacy credential fixtures.
Ownership failure is simulated at the metadata boundary without changing UID.
No database, installer main entry point, container or system state is touched.
"""
import os
import shlex
import unittest
import uuid
from pathlib import Path

import test_installer_secrecy as harness


class InstallerStorageTests(unittest.TestCase):
    setUp = harness.InstallerSecrecyTests.setUp
    run_functions = harness.InstallerSecrecyTests.run_functions
    assert_secret_absent = harness.InstallerSecrecyTests.assert_secret_absent

    def directory(self, name="credentials"):
        result = self.root / name
        result.mkdir(mode=0o700)
        return result

    def private(self, directory, user, content=harness.SENTINEL):
        result = directory / f"{user}-db_password"
        result.write_text(content + "\n")
        result.chmod(0o600)
        return result

    def user(self):
        return "credentialfixture_" + uuid.uuid4().hex

    def legacy(self, user, content=harness.SENTINEL):
        path = Path("/tmp") / f"{user}-db_password"
        # Exclusive creation ensures no existing user's path is touched.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as target:
            target.write(content + "\n")
        self.addCleanup(path.unlink, missing_ok=True)
        return path

    def load(self, directory, user, exists=1, expected=harness.SENTINEL, before=""):
        return f"""
{before}
openssl() {{ printf '%s\\n' 'UNEXPECTED_RANDOM_GENERATION' >&2; return 42; }}
export -f openssl
value=$(run_credential_helper load_or_create_database_password {shlex.quote(str(directory))} {shlex.quote(user)} {exists})
[[ "$value" == {shlex.quote(expected)} ]] || exit 43
printf '%s\\n' 'Loaded expected fixture credential'
"""

    def test_existing_private_password_is_reused_even_when_user_must_be_created(self):
        for project in harness.PROJECTS:
            for exists in (0, 1):
                with self.subTest(project=project, user_exists=exists):
                    directory = self.directory(f"private-{project}-{exists}")
                    user = self.user()
                    file = self.private(directory, user)
                    status, output, logged, _ = self.run_functions(project, self.load(directory, user, exists))
                    self.assertEqual(status, 0, output)
                    self.assertEqual(file.read_text(), harness.SENTINEL + "\n")
                    self.assert_secret_absent(output, logged)

    def test_existing_user_without_trusted_password_fails_without_generation(self):
        for project in harness.PROJECTS:
            with self.subTest(project=project):
                directory = self.directory(f"missing-{project}")
                status, output, logged, _ = self.run_functions(project, self.load(directory, self.user()))
                self.assertNotEqual(status, 0)
                self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)
                self.assertEqual(list(directory.iterdir()), [])
                self.assert_secret_absent(output, logged)

    def test_safe_legacy_migration_preserves_bytes_and_legacy_file(self):
        for project in harness.PROJECTS:
            with self.subTest(project=project):
                directory = self.directory(f"legacy-{project}")
                user = self.user()
                legacy = self.legacy(user)
                status, output, logged, _ = self.run_functions(project, self.load(directory, user))
                self.assertEqual(status, 0, output)
                private = directory / legacy.name
                self.assertEqual(private.read_bytes(), legacy.read_bytes())
                self.assertEqual(private.stat().st_mode & 0o777, 0o600)
                self.assert_secret_absent(output, logged)

    def test_malformed_legacy_password_does_not_publish_a_private_file(self):
        for project in harness.PROJECTS:
            for invalid in ("a'b", "a\\b", "first\nsecond", ""):
                with self.subTest(project=project, invalid=repr(invalid)):
                    directory = self.directory(f"invalid-{uuid.uuid4().hex}")
                    user = self.user()
                    legacy = self.legacy(user, invalid)
                    before = legacy.read_bytes()
                    status, output, _, _ = self.run_functions(project, self.load(directory, user))
                    self.assertNotEqual(status, 0)
                    self.assertFalse((directory / legacy.name).exists())
                    self.assertEqual(legacy.read_bytes(), before)
                    self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)

    def test_symlink_and_hardlink_legacy_credentials_are_refused(self):
        for project in harness.PROJECTS:
            for kind in ("symlink", "hardlink"):
                with self.subTest(project=project, kind=kind):
                    directory = self.directory(f"legacy-{project}-{kind}")
                    user = self.user()
                    unrelated = self.root / f"unrelated-{user}"
                    unrelated.write_text("KEEP THIS FILE\n")
                    unrelated.chmod(0o600)
                    legacy = Path("/tmp") / f"{user}-db_password"
                    if kind == "symlink":
                        legacy.symlink_to(unrelated)
                    else:
                        os.link(unrelated, legacy)
                    self.addCleanup(legacy.unlink, missing_ok=True)
                    status, output, _, _ = self.run_functions(project, self.load(directory, user))
                    self.assertNotEqual(status, 0)
                    self.assertEqual(unrelated.read_text(), "KEEP THIS FILE\n")
                    self.assertFalse((directory / legacy.name).exists())
                    self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)

    def test_foreign_owner_and_permissive_private_file_are_refused_without_regeneration(self):
        for project in harness.PROJECTS:
            for kind in ("foreign-owner", "permissive"):
                with self.subTest(project=project, kind=kind):
                    directory = self.directory(f"private-{project}-{kind}")
                    user = self.user()
                    file = self.private(directory, user)
                    before = ""
                    if kind == "foreign-owner":
                        before = f"""credential_stat() {{
  if [[ "$1" == %u && "$2" == {shlex.quote(str(file))} ]]; then
    printf '%s\\n' "$((EUID + 1))"
  else
    stat -c "$1" -- "$2" 2>/dev/null || stat -f "$3" "$2"
  fi
}}
"""
                    else:
                        file.chmod(0o644)
                    status, output, logged, _ = self.run_functions(project, self.load(directory, user, before=before))
                    self.assertNotEqual(status, 0)
                    self.assertEqual(file.read_text(), harness.SENTINEL + "\n")
                    self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)
                    self.assert_secret_absent(output, logged)

    def test_new_user_gets_a_private_password_and_rerun_reuses_it(self):
        for project in harness.PROJECTS:
            with self.subTest(project=project):
                directory = self.root / f"new-{project}"
                user = self.user()
                command = f"""
openssl() {{ printf '%s\\n' {shlex.quote(harness.SENTINEL)}; }}
export -f openssl
value=$(run_credential_helper load_or_create_database_password {shlex.quote(str(directory))} {user} 0)
[[ "$value" == {shlex.quote(harness.SENTINEL)} ]] || exit 43
"""
                status, output, logged, _ = self.run_functions(project, command)
                self.assertEqual(status, 0, output)
                private = directory / f"{user}-db_password"
                self.assertEqual(private.read_text(), harness.SENTINEL + "\n")
                self.assertEqual(private.stat().st_mode & 0o777, 0o600)
                self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
                self.assert_secret_absent(output, logged)
                status, output, logged, _ = self.run_functions(project, self.load(directory, user))
                self.assertEqual(status, 0, output)
                self.assert_secret_absent(output, logged)

    def test_invalid_user_path_is_rejected_before_creating_a_directory(self):
        directory = self.root / "not-created"
        status, output, _, _ = self.run_functions("laemp", self.load(directory, "../escaping"))
        self.assertNotEqual(status, 0)
        self.assertFalse(directory.exists())
        self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)

    def test_owned_but_nonprivate_leaf_is_not_silently_chmodded(self):
        directory = self.directory("old-state-leaf")
        directory.chmod(0o755)
        status, _, _, _ = self.run_functions("laemp", self.load(directory, self.user()))
        self.assertNotEqual(status, 0)
        self.assertEqual(directory.stat().st_mode & 0o777, 0o755)

    def test_failed_private_write_or_rename_keeps_previous_value(self):
        for project in harness.PROJECTS:
            for failure in ("cat", "mv"):
                with self.subTest(project=project, failure=failure):
                    directory = self.directory(f"rollback-{project}-{failure}")
                    user = self.user()
                    file = self.private(directory, user, "KEEP PREVIOUS VALUE")
                    fake = "printf 'PARTIAL WRITE'; return 1" if failure == "cat" else "return 1"
                    command = f"""
{failure}() {{ {fake}; }}
export -f {failure}
printf '%s\\n' {shlex.quote(harness.SENTINEL)} | run_credential_helper publish_private_credentials {shlex.quote(str(file))}
"""
                    status, output, logged, _ = self.run_functions(project, command)
                    self.assertNotEqual(status, 0)
                    self.assertEqual(file.read_text(), "KEEP PREVIOUS VALUE\n")
                    self.assertEqual(list(directory.glob(".credential.*")), [])
                    self.assert_secret_absent(output, logged)


if __name__ == "__main__":
    unittest.main()
