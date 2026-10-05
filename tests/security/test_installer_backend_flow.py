"""Run only bounded authored credential-provisioning blocks with fake SQL.

No whole database ensure function is invoked: those functions write /etc and
manage services. Marker extraction fails closed if the bounded block changes
into system provisioning. All files and SQL traces are synthetic fixtures.
"""
import shlex
import unittest
import uuid
from pathlib import Path

import test_installer_secrecy as harness


class InstallerBackendFlowTests(unittest.TestCase):
    setUp = harness.InstallerSecrecyTests.setUp
    run_functions = harness.InstallerSecrecyTests.run_functions
    assert_secret_absent = harness.InstallerSecrecyTests.assert_secret_absent

    def block(self, project, backend):
        source = (harness.TEST_ROOT / project / "functions.sh").read_text()
        if backend == "mysql":
            start = "    # Check if database and user already exist"
            end = "    # Configure MySQL/MariaDB for Moodle"
        else:
            start = "    # A rerun must not rotate a role's password or replace its saved credential."
            end = "    # Configure PostgreSQL for Moodle"
        self.assertEqual(source.count(start), 1)
        self.assertEqual(source.count(end), 1)
        block = source.split(start)[1].split(end)[0]
        for forbidden in ("/etc/", "service_manage", "package_ensure", "function "):
            self.assertNotIn(forbidden, block, "bounded fixture must not perform system provisioning")
        return block

    def fixture(self, project, backend, *, db_exists, fail_query=False):
        state = self.root / f"state-{project}-{backend}-{uuid.uuid4().hex}"
        state.mkdir(mode=0o700)
        user = "backendfixture_" + uuid.uuid4().hex
        credentials = state / "credentials"
        password = credentials / f"{user}-db_password"
        if not fail_query:
            credentials.mkdir(mode=0o700)
            password.write_text(harness.SENTINEL + "\n")
            password.chmod(0o600)
        trace = state / "sql-trace"
        query_status = 29 if fail_query else 0
        command = f"""
AMP_MOODLE_STATE_DIR={shlex.quote(str(state))}
LAEMP_STATE_DIR={shlex.quote(str(state))}
DB_USER={user}
DB_NAME=fixture_database
DB_HOST=localhost
MYSQL_SSL_FLAGS=()
openssl() {{ printf '%s\\n' 'UNEXPECTED_RANDOM_GENERATION' >&2; return 42; }}
export -f openssl
fixture_sql() {{
  local query="${{@: -1}}"
  case "$query" in
    *SELECT*SCHEMATA*|*SELECT*pg_database*)
      printf '%s\\n' QUERY_DATABASE >> {shlex.quote(str(trace))}
      [[ {query_status} == 0 ]] || return {query_status}
      printf '%s\\n' {db_exists} ;;
    *SELECT*mysql.user*|*SELECT*pg_roles*)
      printf '%s\\n' QUERY_USER >> {shlex.quote(str(trace))}
      [[ {query_status} == 0 ]] || return {query_status}
      printf '%s\\n' 1 ;;
    *CREATE*USER*)
      [[ "$query" == *{harness.SENTINEL}* ]] || return 51
      printf '%s\\n' CREATE_USER >> {shlex.quote(str(trace))}
      printf '%s\\n' {harness.SENTINEL}; printf '%s\\n' {harness.SENTINEL} >&2 ;;
    *CREATE*DATABASE*) printf '%s\\n' CREATE_DATABASE >> {shlex.quote(str(trace))} ;;
    *GRANT*) printf '%s\\n' GRANT >> {shlex.quote(str(trace))} ;;
    *FLUSH*) printf '%s\\n' FLUSH >> {shlex.quote(str(trace))} ;;
    *) printf '%s\\n' 'unexpected fixture SQL' >&2; return 52 ;;
  esac
}}
mysql() {{ fixture_sql "$@"; }}
psql() {{ fixture_sql "$@"; }}
sudo() {{
  [[ "${{1:-}}" == -u && "${{2:-}}" == postgres && "${{3:-}}" == psql ]] || return 53
  shift 3
  psql "$@"
}}
provision_fixture() {{
{self.block(project, backend)}
}}
provision_fixture
[[ "$DB_PASS" == {shlex.quote(harness.SENTINEL)} ]] || exit 54
"""
        status, output, logged, _ = self.run_functions(project, command)
        operations = trace.read_text().splitlines() if trace.exists() else []
        return status, output, logged, credentials, password, operations

    def test_existing_role_and_missing_database_reuses_saved_password(self):
        for project in harness.PROJECTS:
            for backend in ("mysql", "postgres"):
                with self.subTest(project=project, backend=backend):
                    status, output, logged, _, password, operations = self.fixture(project, backend, db_exists=0)
                    self.assertEqual(status, 0, output)
                    self.assertEqual(password.read_text(), harness.SENTINEL + "\n")
                    self.assertIn("CREATE_DATABASE", operations)
                    if backend == "postgres":
                        self.assertNotIn("CREATE_USER", operations)
                    self.assert_secret_absent(output, logged)

    def test_existing_postgres_role_and_database_do_not_issue_create_statements(self):
        for project in harness.PROJECTS:
            with self.subTest(project=project):
                status, output, logged, _, password, operations = self.fixture(project, "postgres", db_exists=1)
                self.assertEqual(status, 0, output)
                self.assertEqual(password.read_text(), harness.SENTINEL + "\n")
                self.assertNotIn("CREATE_USER", operations)
                self.assertNotIn("CREATE_DATABASE", operations)
                self.assert_secret_absent(output, logged)

    def test_query_failure_stops_before_credential_storage_generation_or_create(self):
        for project in harness.PROJECTS:
            for backend in ("mysql", "postgres"):
                with self.subTest(project=project, backend=backend):
                    status, output, logged, credentials, _, operations = self.fixture(project, backend, db_exists=0, fail_query=True)
                    self.assertNotEqual(status, 0)
                    self.assertFalse(credentials.exists(), "query failure must stop before credential helper")
                    self.assertFalse(any(operation.startswith("CREATE") for operation in operations))
                    self.assertNotIn("UNEXPECTED_RANDOM_GENERATION", output)
                    self.assert_secret_absent(output, logged)


if __name__ == "__main__":
    unittest.main()
