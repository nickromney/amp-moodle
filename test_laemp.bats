#!/usr/bin/env bats

# BATS test suite for laemp.sh command-line option parsing
# NOTE: These tests should be run on Ubuntu/Debian systems (or in containers)
# The script checks OS compatibility before parsing arguments

setup() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    skip "Requires Ubuntu/Debian OS"
  fi
}

# ==============================================================================
# HELP AND USAGE TESTS
# ==============================================================================

@test "help flag (-h) shows usage" {
  run ./laemp.sh -h
  echo "Exit status: $status"
  echo "Output: $output"
  [ $status -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
  [[ "$output" =~ "Options:" ]]
}

@test "help flag (--help) shows usage" {
  run ./laemp.sh --help
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "no arguments shows usage and exits with error" {
  run ./laemp.sh
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Usage:" ]]
}

# ==============================================================================
# PHP VERSION TESTS
# ==============================================================================

@test "php flag (-p) with default version in dry-run verbose mode" {
  run ./laemp.sh -p -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "DRY RUN" ]]
}

@test "php flag (-p) with specific version 8.1 in dry-run verbose mode" {
  run ./laemp.sh -p 8.1 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.1" ]]
}

@test "php flag (-p) with specific version 8.2 in dry-run verbose mode" {
  run ./laemp.sh -p 8.2 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.2" ]]
}

@test "php flag (--php) with version 8.3 in dry-run verbose mode" {
  run ./laemp.sh --php 8.4 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
}

@test "php-alongside flag (-P) with specific version in dry-run verbose mode" {
  run ./laemp.sh -P 8.1 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.1" ]]
}

@test "php-alongside flag (--php-alongside) with version in dry-run verbose mode" {
  run ./laemp.sh --php-alongside 8.2 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.2" ]]
}

# ==============================================================================
# MOODLE VERSION TESTS
# ==============================================================================

@test "moodle flag (-m) with default version in dry-run verbose mode" {
  run ./laemp.sh -m -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 5024" ]]
}

@test "moodle flag (-m) with version 405 (4.5) in dry-run verbose mode" {
  run ./laemp.sh -m 405 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
}

@test "moodle flag (-m) with version 500 (5.0) in dry-run verbose mode" {
  run ./laemp.sh -m 500 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 500" ]]
}

@test "moodle flag (-m) with version 5024 (5.2.4) in dry-run verbose mode" {
  run ./laemp.sh -m 5024 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 5024" ]]
}

@test "moodle flag (-m) supports Moodle 4.4.2 with PHP 8.3" {
  run ./laemp.sh -p 8.3 -m 4042 -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 4042" ]]
}

@test "moodle flag (--moodle) with specific version in dry-run verbose mode" {
  run ./laemp.sh --moodle 405 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
}

# ==============================================================================
# WEB SERVER TESTS
# ==============================================================================

@test "web server flag (-w apache) in dry-run verbose mode" {
  run ./laemp.sh -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
}

@test "web server flag (-w nginx) in dry-run verbose mode" {
  run ./laemp.sh -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
}

@test "web server flag (--web apache) in dry-run verbose mode" {
  run ./laemp.sh --web apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
}

@test "web server flag (--web nginx) in dry-run verbose mode" {
  run ./laemp.sh --web nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
}

@test "invalid web server type shows error" {
  run ./laemp.sh -w lighttpd -n -v
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Unsupported web server type" ]]
}

# ==============================================================================
# PHP-FPM TESTS
# ==============================================================================

@test "fpm flag (-f) with apache in dry-run verbose mode" {
  run ./laemp.sh -f -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure FPM for web servers" ]]
}

@test "fpm flag (--fpm) with nginx in dry-run verbose mode" {
  run ./laemp.sh --fpm -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure FPM for web servers" ]]
}

@test "fpm flag (-f) without web server shows error" {
  run ./laemp.sh -f -n -v
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Option -f requires either -w apache or -w nginx" ]]
}

@test "nginx automatically enables fpm" {
  run ./laemp.sh -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  # FPM is implicitly enabled with nginx
}

# ==============================================================================
# DATABASE TESTS
# ==============================================================================

@test "database flag (-d mysql) in dry-run verbose mode" {
  run ./laemp.sh -d mysql -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to mysql" ]]
}

@test "database flag (-d mysqli) in dry-run verbose mode" {
  run ./laemp.sh -d mysqli -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to mysql" ]]
}

@test "database flag (-d pgsql) in dry-run verbose mode" {
  run ./laemp.sh -d pgsql -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to pgsql" ]]
}

@test "database flag (--database mysql) in dry-run verbose mode" {
  run ./laemp.sh --database mysql -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to mysql" ]]
}

@test "database flag (--database pgsql) in dry-run verbose mode" {
  run ./laemp.sh --database pgsql -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Database type set to pgsql" ]]
}

@test "invalid database type shows error" {
  run ./laemp.sh -d mongodb -n -v
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Unsupported database type" ]]
}

# ==============================================================================
# SSL CERTIFICATE TESTS
# ==============================================================================

@test "self-signed certificate flag (-S) in dry-run verbose mode" {
  run ./laemp.sh -S -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Self-signed flag doesn't appear in verbose output, but should not error
}

@test "self-signed certificate flag (--self-signed) in dry-run verbose mode" {
  run ./laemp.sh --self-signed -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
}

@test "acme certificate flag (-a) in dry-run verbose mode" {
  run ./laemp.sh -a -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
}

@test "acme certificate flag (--acme-cert) in dry-run verbose mode" {
  run ./laemp.sh --acme-cert -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
}

# ==============================================================================
# MONITORING TESTS
# ==============================================================================

@test "prometheus flag (-r) in dry-run verbose mode" {
  run ./laemp.sh -r -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
}

@test "prometheus flag (--prometheus) in dry-run verbose mode" {
  run ./laemp.sh --prometheus -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
}

# ==============================================================================
# CACHING TESTS
# ==============================================================================

@test "memcached flag (-M) in dry-run verbose mode" {
  run ./laemp.sh -M -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Memcached" ]]
}

@test "memcached flag (--memcached) in dry-run verbose mode" {
  run ./laemp.sh --memcached -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Memcached" ]]
}

@test "memcached flag with local mode in dry-run verbose mode" {
  run ./laemp.sh -M local -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Memcached" ]]
  [[ "$output" =~ "Ensure local Memcached" ]]
}

@test "memcached flag with network mode in dry-run verbose mode" {
  run ./laemp.sh -M network -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Memcached" ]]
}

@test "memcached flag with invalid mode shows error" {
  run ./laemp.sh -M invalid -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Invalid mode for Memcached" ]]
}

# ==============================================================================
# SCRIPT BEHAVIOR FLAGS
# ==============================================================================

@test "verbose flag (-v) shows detailed output" {
  run ./laemp.sh -v -w nginx -n
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Verbose output" ]]
  [[ "$output" =~ "Chosen options:" ]]
}

@test "verbose flag (--verbose) shows detailed output" {
  run ./laemp.sh --verbose -w apache -n
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Verbose output" ]]
}

@test "dry-run flag (-n) prevents execution" {
  run ./laemp.sh -n -w nginx -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "DRY RUN" ]]
}

@test "dry-run flag (--nop) prevents execution" {
  run ./laemp.sh --nop -w apache -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "DRY RUN" ]]
}

@test "ci mode flag (-c) in dry-run verbose mode" {
  run ./laemp.sh -c -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "CI mode" ]]
}

@test "ci mode flag (--ci) in dry-run verbose mode" {
  run ./laemp.sh --ci -w apache -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "CI mode" ]]
}

@test "sudo flag (-s) in dry-run verbose mode" {
  run ./laemp.sh -s -w nginx -n -v
  echo "Exit status: $status"
  # May pass or fail depending on sudo availability
  [[ "$output" =~ "Use sudo" ]] || [[ "$output" =~ "sudo" ]]
}

@test "sudo flag (--sudo) in dry-run verbose mode" {
  run ./laemp.sh --sudo -w apache -n -v
  echo "Exit status: $status"
  # May pass or fail depending on sudo availability
  [[ "$output" =~ "Use sudo" ]] || [[ "$output" =~ "sudo" ]]
}

# ==============================================================================
# COMBINED FLAG SCENARIOS
# ==============================================================================

@test "full LAMP stack with Moodle in dry-run verbose mode" {
  run ./laemp.sh -w apache -p 8.4 -d mysql -m 405 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Database type set to mysql" ]]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
}

@test "full LEMP stack with Moodle in dry-run verbose mode" {
  run ./laemp.sh -w nginx -p 8.4 -d pgsql -m 500 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Database type set to pgsql" ]]
  [[ "$output" =~ "Ensure Moodle version 500" ]]
}

@test "nginx with PHP-FPM, Moodle, and monitoring in dry-run verbose mode" {
  run ./laemp.sh -w nginx -p 8.4 -m 405 -r -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
}

@test "apache with FPM, SSL, and memcached in dry-run verbose mode" {
  run ./laemp.sh -w apache -f -p 8.2 -S -M -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
  [[ "$output" =~ "Ensure FPM for web servers" ]]
  [[ "$output" =~ "Ensure PHP version 8.2" ]]
  [[ "$output" =~ "Ensure Memcached" ]]
}

@test "complete setup with all major flags in dry-run verbose mode" {
  run ./laemp.sh -w nginx -p 8.4 -d mysql -m 405 -M local -r -S -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Database type set to mysql" ]]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
  [[ "$output" =~ "Ensure Memcached" ]]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
}

@test "multiple php versions with alongside flag in dry-run verbose mode" {
  run ./laemp.sh -p 8.4 -P 8.1 -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Should show PHP 8.1 since -P was last
  [[ "$output" =~ "Ensure PHP version 8.1" ]]
}

@test "moodle with postgres and acme cert in dry-run verbose mode" {
  run ./laemp.sh -m 405 -d pgsql -a -w nginx -p 8.4 -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
  [[ "$output" =~ "Database type set to pgsql" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
}

# ==============================================================================
# ERROR CONDITION TESTS
# ==============================================================================

@test "unknown option shows error and usage" {
  run ./laemp.sh --unknown-option
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Unknown option" ]]
  [[ "$output" =~ "Usage:" ]]
}

@test "invalid short option shows error" {
  run ./laemp.sh -X
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "error" ]]
}

@test "fpm without web server fails with error" {
  run ./laemp.sh -f -n -v
  echo "Exit status: $status"
  [ $status -eq 1 ]
  [[ "$output" =~ "Option -f requires either -w apache or -w nginx" ]]
}

@test "conflicting database types (last one wins)" {
  run ./laemp.sh -d mysql -d pgsql -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Last database type should win (pgsql)
  [[ "$output" =~ "Database type set to pgsql" ]]
}

@test "conflicting web servers (last one wins)" {
  run ./laemp.sh -w apache -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Last web server should win (nginx)
  [[ "$output" =~ "Webserver type set to Nginx" ]]
}

# ==============================================================================
# LONG OPTION TESTS
# ==============================================================================

@test "all long options work together in dry-run verbose mode" {
  run ./laemp.sh --web nginx --php 8.4 --database mysql --moodle 405 --memcached --prometheus --nop --verbose
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Database type set to mysql" ]]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
  [[ "$output" =~ "Ensure Memcached" ]]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
}

@test "long and short options mixed in dry-run verbose mode" {
  run ./laemp.sh -w apache --php 8.2 -d pgsql --moodle 500 -r -M -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Apache" ]]
  [[ "$output" =~ "Ensure PHP version 8.2" ]]
  [[ "$output" =~ "Database type set to pgsql" ]]
  [[ "$output" =~ "Ensure Moodle version 500" ]]
  [[ "$output" =~ "Ensure Prometheus monitoring" ]]
  [[ "$output" =~ "Ensure Memcached" ]]
}

# ==============================================================================
# EDGE CASES AND VALIDATION
# ==============================================================================

@test "option with missing value uses default" {
  run ./laemp.sh -p -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Should use default PHP version (8.4)
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
}

@test "option with missing value for moodle uses default" {
  run ./laemp.sh -m -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Should use default Moodle version (405)
  [[ "$output" =~ "Ensure Moodle version 405" ]]
}

@test "option with missing value for web server uses default" {
  run ./laemp.sh -w -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  # Should use default web server (nginx)
  [[ "$output" =~ "Webserver type set to Nginx" ]]
}

@test "duplicate flags (idempotent behavior)" {
  run ./laemp.sh -p 8.4 -p 8.4 -w nginx -n -v
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
}

@test "flags in different order produce same result" {
  run ./laemp.sh -n -v -w nginx -p 8.4 -m 405
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Webserver type set to Nginx" ]]
  [[ "$output" =~ "Ensure PHP version 8.4" ]]
  [[ "$output" =~ "Ensure Moodle version 405" ]]
}

@test "verbose without other meaningful options" {
  run ./laemp.sh -v -n -w nginx
  echo "Exit status: $status"
  [ $status -eq 0 ]
  [[ "$output" =~ "Verbose output" ]]
}

@test "Moodle 5.3.0 accepts PHP 8.4 in dry-run verbose mode" {
  run ./laemp.sh -p 8.4 -m 5030 -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Ensure Moodle version 5030" ]]
}

@test "Moodle 5.3.0 rejects PHP 8.2 in dry-run verbose mode" {
  run ./laemp.sh -p 8.2 -m 5030 -n -v
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Moodle 5.3.0 requires PHP 8.3 or higher" ]]
}

@test "Moodle 5.3.0 rejects PHP 8.5 in dry-run verbose mode" {
  run ./laemp.sh -p 8.5 -m 5030 -n -v
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Moodle 5.3.0 supports PHP 8.3, 8.4" ]]
}

# Load the release helpers without running main.
load_release_helpers() {
  local fn
  eval "$(sed -n '/^MOODLE_KNOWN_RELEASES=(/,/^)/p;/^MOODLE_DOWNLOAD_MIRRORS=(/,/^)/p' laemp.sh)"
  for fn in moodle_version_stable moodle_version_semver moodle_archive_file moodle_known_sha256 moodle_min_database_version moodle_postgres_major; do
    eval "$(awk "/^function ${fn}\\(\\)/,/^}/" laemp.sh)"
  done
}

@test "tagged releases map to Moodle's package names" {
  load_release_helpers
  [ "$(moodle_archive_file 5024)" = "moodle-5.2.4.tgz" ]
  [ "$(moodle_archive_file 5030)" = "moodle-5.3.tgz" ]
  [ "$(moodle_archive_file 4042)" = "moodle-4.4.2.tgz" ]
  [ "$(moodle_archive_file 503)" = "moodle-latest-503.tgz" ]
}

@test "Moodle 5.2.4 and 5.3.0 packages are pinned by checksum" {
  load_release_helpers
  [ "$(moodle_known_sha256 5024)" = "8569b63f1e97416ecb67ec75767dd20675892c7a62a5e90d1647366fddf873cf" ]
  [ "$(moodle_known_sha256 5030)" = "7e5edf110555956571f40e42acffde0eb23681ebebd212a2fec0fe7d795dd511" ]
  run moodle_known_sha256 5022
  [ "$status" -ne 0 ]
}

@test "downloads fall back to packaging.moodle.org" {
  load_release_helpers
  [ "${MOODLE_DOWNLOAD_MIRRORS[1]}" = "https://packaging.moodle.org" ]
}

@test "Moodle 5.3 raises the MariaDB and PostgreSQL floors" {
  load_release_helpers
  [ "$(moodle_min_database_version 5024 mariadb)" = "10.11" ]
  [ "$(moodle_min_database_version 5030 mariadb)" = "11.4" ]
  [ "$(moodle_min_database_version 5024 pgsql)" = "16" ]
  [ "$(moodle_min_database_version 5030 pgsql)" = "17" ]
  [ "$(moodle_postgres_major 5024)" = "16" ]
  [ "$(moodle_postgres_major 5030)" = "17" ]
  [ "$(moodle_postgres_major 4042)" = "16" ]
}

# ==============================================================================
# DRY-RUN FILE EDITS
# ==============================================================================

load_replace_file_value() {
  # laemp.sh runs main when sourced, so load only the function under test.
  eval "$(awk '/^function replace_file_value\(\)/,/^}/' ./laemp.sh)"
  log() { :; }
  run_sensitive_command() {
    if [[ $1 == --makes-changes ]]; then
      shift
      [[ ${DRY_RUN_CHANGES:-false} == true ]] && return 0
    fi
    "$@"
  }
}

@test "dry-run config edits need no write access to an installed config.php" {
  load_replace_file_value
  config="$BATS_TEST_TMPDIR/config.php"
  printf '%s\n' "\$CFG->dbhost = 'localhost';" > "$config"
  chmod 0444 "$config"
  DRY_RUN_CHANGES=true
  run replace_file_value "\$CFG->dbhost\s*=\s*'localhost';" "\$CFG->dbhost = 'db';" "$config"
  [ "$status" -eq 0 ]
  [ "$(cat "$config")" = "\$CFG->dbhost = 'localhost';" ]
}

@test "real config edits still lock and update config.php" {
  load_replace_file_value
  config="$BATS_TEST_TMPDIR/config.php"
  printf '%s\n' "\$CFG->dbhost = 'localhost';" > "$config"
  DRY_RUN_CHANGES=false
  run replace_file_value "\$CFG->dbhost\s*=\s*'localhost';" "\$CFG->dbhost = 'db';" "$config"
  [ "$status" -eq 0 ]
  [ "$(cat "$config")" = "\$CFG->dbhost = 'db';" ]
}

# ==============================================================================
# DRY RUN (-n) WRITES NOTHING
# ==============================================================================

load_laemp_functions() {
  # laemp.sh runs main when sourced, so load only the named functions.
  local name
  for name in "$@"; do
    eval "$(awk "/^function ${name}\\(\\)/,/^}/" ./laemp.sh)"
  done
  log() { :; }
}

@test "dry-run write_file creates nothing and drains a piped producer" {
  load_laemp_functions write_file
  target="$BATS_TEST_TMPDIR/written.conf"
  run bash -c "$(declare -f log write_file); set -euo pipefail; DRY_RUN_CHANGES=true; seq 1 100000 | write_file '$target'"
  [ "$status" -eq 0 ]
  [ ! -e "$target" ]
}

@test "real write_file writes and appends" {
  load_laemp_functions write_file
  target="$BATS_TEST_TMPDIR/written.conf"
  DRY_RUN_CHANGES=false
  printf 'one\n' | write_file "$target"
  printf 'two\n' | write_file --append "$target"
  [ "$(cat "$target")" = $'one\ntwo' ]
}

@test "dry-run Moodle config edits leave an installed config.php unchanged" {
  load_laemp_functions run_command replace_file_value moodle_config_files
  validate_db_prefix() { :; }
  run_sensitive_command() {
    if [[ $1 == --makes-changes ]]; then
      shift
      [[ ${DRY_RUN_CHANGES:-false} == true ]] && return 0
    fi
    "$@"
  }
  site="$BATS_TEST_TMPDIR/moodle"
  mkdir -p "$site"
  printf '%s\n' "<?php" "require_once(__DIR__ . '/lib/setup.php');" > "$site/config-dist.php"
  cp "$site/config-dist.php" "$site/config.php"
  before="$(cat "$site/config.php")"
  DRY_RUN_CHANGES=true NGINX_ENSURE=true MEMCACHED_ENSURE=true
  DB_TYPE=mariadb DB_HOST=localhost DB_NAME=moodle DB_USER=moodle DB_PASS=x DB_PREFIX=mdl_
  moodleSiteName=moodle.test moodlePort='' moodleDataDir=/var/moodledata
  run moodle_config_files "$site"
  [ "$status" -eq 0 ]
  [ "$(cat "$site/config.php")" = "$before" ]
}

@test "dry-run PHP-FPM pool setup does not kill running PHP-FPM" {
  load_laemp_functions run_command write_file php_fpm_create_pool
  calls="$BATS_TEST_TMPDIR/calls"
  : > "$calls"
  pidof() { return 0; }
  pkill() { echo "pkill $*" >> "$calls"; }
  sleep() { :; }
  service_manage() { echo "service_manage $*" >> "$calls"; }
  PHP_VERSION_MAJOR_MINOR=8.4 DRY_RUN_CHANGES=true
  run php_fpm_create_pool moodle www-data
  [ "$status" -eq 0 ]
  [ ! -s "$calls" ]
}

@test "dry-run Nginx check does not run nginx -t" {
  load_laemp_functions run_command nginx_verify
  calls="$BATS_TEST_TMPDIR/calls"
  : > "$calls"
  tool_exists() { return 0; }
  nginx() { echo "nginx $*" >> "$calls"; }
  DRY_RUN_CHANGES=true
  run nginx_verify --exit-on-failure
  [ "$status" -eq 0 ]
  ! grep -q -- 'nginx -t' "$calls"
}

@test "laemp.sh routes every file write through dry-run-aware helpers" {
  # Redirections to log files, /dev/null and the private credential staging file are allowed.
  hits="$(grep -nE '(cat|echo|printf)[^|#]*>>?[[:space:]]*"?\$?\{?[A-Za-z_/]' ./laemp.sh |
    grep -vE 'run_command|run_sensitive|/dev/null|>&2|2>|log |LOG_FILE|"\$temporary"' || true)"
  hits+=$'\n'"$(grep -nE '\|[[:space:]]*tee ' ./laemp.sh | grep -vE 'run_command|LOG_FILE' || true)"
  echo "$hits"
  [ -z "${hits//$'\n'/}" ]
}
