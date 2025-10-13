#!/usr/bin/env bats
# Fast smoke tests for laemp.sh
# These tests should run in < 1 second each and catch obvious problems
#
# NOTE: These are static analysis tests. The script requires Ubuntu/Debian
# to run, so we focus on syntax checks, code quality, and structure validation.
# For functional tests, see test_laemp.bats (run in containers).

setup() {
  export SCRIPT="./laemp.sh"
  export OS_CHECK_REQUIRED=true

  # Detect if we're on a supported OS
  if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
      OS_CHECK_REQUIRED=false
    fi
  fi
}

# ============================================================================
# Basic Script Validity
# ============================================================================

@test "script file exists" {
  [ -f "$SCRIPT" ]
}

@test "script has correct shebang" {
  run head -n 1 "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == "#!/usr/bin/env bash" ]]
}

@test "script is executable" {
  [ -x "$SCRIPT" ]
}

@test "script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script passes shellcheck" {
  if ! command -v shellcheck &> /dev/null; then
    skip "shellcheck not installed"
  fi
  run shellcheck "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Error Handling
# ============================================================================

@test "script uses set -e for error handling" {
  run grep -E "^set -[a-z]*e" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script uses set -u for undefined variable detection" {
  run grep -E "^set -[a-z]*u" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script uses set -o pipefail for pipeline error handling" {
  run grep "^set -[a-z]*o pipefail" "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Help and Usage
# ============================================================================

@test "help flag works (-h)" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "help flag works (--help)" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Usage:" ]]
}

@test "help shows all main options" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" =~ "-a" || "$output" =~ "--acme-cert" ]]
  [[ "$output" =~ "-m" || "$output" =~ "--moodle" ]]
  [[ "$output" =~ "-p" || "$output" =~ "--php" ]]
  [[ "$output" =~ "-w" || "$output" =~ "--web" ]]
  [[ "$output" =~ "-n" || "$output" =~ "--nop" ]]
  [[ "$output" =~ "-v" || "$output" =~ "--verbose" ]]
}

# ============================================================================
# Dry Run Mode
# ============================================================================

@test "dry run flag is recognized (-n)" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "DRY RUN" || "$output" =~ "Dry run" ]]
}

@test "dry run with verbose shows options" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Options chosen:" ]]
}

# ============================================================================
# Logging System
# ============================================================================

@test "script defines log function" {
  run grep -E "^(function )?log\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script defines log levels" {
  run grep "LOG_LEVELS=" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script has log_init function" {
  run grep -E "^(function )?log_init\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "verbose mode enables additional logging" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -v -n
  [ "$status" -eq 0 ]
  # Should show more output in verbose mode
}

@test "script uses log verbose in functions" {
  run grep -c "log verbose" "$SCRIPT"
  [ "$status" -eq 0 ]
  # Should have at least 100 verbose log statements
  [ "$output" -gt 100 ]
}

@test "script uses log debug for function entry/exit" {
  run grep "log debug.*Entered function" "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Function Definitions
# ============================================================================

@test "all critical functions are defined" {
  critical_functions=(
    "echo_usage"
    "log"
    "log_init"
    "run_command"
    "package_ensure"
    "apache_ensure"
    "nginx_ensure"
    "php_ensure"
    "moodle_ensure"
    "main"
  )

  for func in "${critical_functions[@]}"; do
    run grep -E "^(function )?${func}\(\)" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "functions use consistent naming convention" {
  # Check that functions use lowercase with underscores
  run grep -E "^function [A-Z]" "$SCRIPT"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Variable Safety
# ============================================================================

@test "script declares all global variables at top" {
  # Check for common default variables
  defaults=(
    "DRY_RUN_CHANGES"
    "APACHE_ENSURE"
    "NGINX_ENSURE"
    "PHP_ENSURE"
    "MOODLE_ENSURE"
    "DEFAULT_PHP_VERSION_MAJOR_MINOR"
    "DEFAULT_MOODLE_VERSION"
  )

  for var in "${defaults[@]}"; do
    run grep "^${var}=" "$SCRIPT"
    [ "$status" -eq 0 ]
  done
}

@test "script uses quotes around variable expansions" {
  # This is a heuristic check - look for common patterns
  # Count unquoted variables should be minimal
  unquoted_vars=$(grep -c '\$[A-Z_][A-Z_0-9]*[^"]' "$SCRIPT" || true)
  # This is a weak check but helps catch obvious issues
  [ "$unquoted_vars" -lt 1000 ]
}

@test "script avoids deprecated backtick syntax" {
  # Should use $() instead of ``
  run grep '`[^`]*`' "$SCRIPT"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Common Bash Pitfalls
# ============================================================================

@test "script uses [[ ]] instead of [ ] for conditionals" {
  # Modern bash prefers [[ ]]
  double_bracket=$(grep -c '\[\[' "$SCRIPT" || echo 0)
  single_bracket=$(grep -c '\[ ' "$SCRIPT" || echo 0)
  # Should have more double brackets than single
  [ "$double_bracket" -gt "$single_bracket" ]
}

@test "script avoids dangerous 'rm -rf' without quotes" {
  # This is a safety check
  run grep 'rm -rf \$[A-Za-z_]' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "script uses 'local' for function variables" {
  # Functions should declare local variables
  run grep -c '^  local ' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" -gt 50 ]
}

@test "script avoids 'eval' command" {
  # eval is dangerous and should be avoided
  run grep -w 'eval' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "script uses 'command -v' or 'type' to check for commands" {
  # Modern way to check for command existence
  run grep -E '(command -v|type -P)' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Path and File Handling
# ============================================================================

@test "script gets its own directory correctly" {
  run grep 'SCRIPT_DIRECTORY.*dirname' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script gets its own filename correctly" {
  run grep 'SCRIPT_NAME.*basename' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script creates log directory if needed" {
  run grep 'mkdir -p.*LOG_DIRECTORY' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Command-Line Argument Parsing
# ============================================================================

@test "script uses while loop for argument parsing" {
  # Script doesn't use getopt, it uses a while loop
  run grep 'while \[\[ \$# -gt 0 \]\]' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script handles unknown options gracefully" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" --invalid-option
  # Should fail with non-zero exit
  [ "$status" -ne 0 ]
}

@test "script handles multiple short options" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -nvh
  # Should work (help overrides, so exit 0)
  [ "$status" -eq 0 ]
}

# ============================================================================
# Web Server Options
# ============================================================================

@test "web server option accepts apache" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -w apache -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Apache" || "$output" =~ "apache" ]]
}

@test "web server option accepts nginx" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -w nginx -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Nginx" || "$output" =~ "nginx" ]]
}

# ============================================================================
# PHP Version Handling
# ============================================================================

@test "php option accepts version number" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -p 8.3 -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "8.3" ]]
}

@test "php option works without version (uses default)" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -p -n -v
  [ "$status" -eq 0 ]
}

# ============================================================================
# Moodle Version Handling
# ============================================================================

@test "moodle option accepts version number" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -m 405 -n -v
  [ "$status" -eq 0 ]
  [[ "$output" =~ "405" || "$output" =~ "4.5" || "$output" =~ "Moodle" ]]
}

@test "moodle option works without version (uses default)" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -m -n -v
  [ "$status" -eq 0 ]
}

# ============================================================================
# Safety Features
# ============================================================================

@test "run_command function exists for safe execution" {
  run grep -E "^(function )?run_command\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script respects DRY_RUN_CHANGES flag" {
  run grep 'DRY_RUN_CHANGES' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script has CI mode option" {
  if [ "$OS_CHECK_REQUIRED" = true ]; then
    skip "Requires Ubuntu/Debian OS"
  fi
  run "$SCRIPT" -c -n -v
  [ "$status" -eq 0 ]
}

# ============================================================================
# Locale Settings
# ============================================================================

@test "script sets LC_ALL for UTF-8" {
  run grep 'export LC_ALL=en_US.UTF-8' "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script sets LANG for UTF-8" {
  run grep 'export LANG=en_US.UTF-8' "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Code Quality
# ============================================================================

@test "script has reasonable line count" {
  lines=$(wc -l < "$SCRIPT")
  # Should be between 2000-3500 lines (current is ~2700)
  [ "$lines" -gt 2000 ]
  [ "$lines" -lt 3500 ]
}

@test "script has comments explaining complex sections" {
  comment_count=$(grep -c '^#' "$SCRIPT")
  # Should have at least 100 comment lines
  [ "$comment_count" -gt 100 ]
}

@test "no trailing whitespace in script" {
  run grep -n ' $' "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "script uses consistent indentation" {
  # Check for tab/space mixing issues (should use spaces)
  run grep -P '^\t' "$SCRIPT"
  [ "$status" -ne 0 ]
}

# ============================================================================
# Function-Specific Checks
# ============================================================================

@test "apache_ensure function exists" {
  run grep -E "^(function )?apache_ensure\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "nginx_ensure function exists" {
  run grep -E "^(function )?nginx_ensure\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "php_ensure function exists" {
  run grep -E "^(function )?php_ensure\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "moodle_ensure function exists" {
  run grep -E "^(function )?moodle_ensure\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "prometheus_ensure function exists" {
  run grep -E "^(function )?prometheus_ensure\(\)" "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ============================================================================
# Exit Code Validation
# ============================================================================

@test "script exits 0 on help" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
}

@test "script exits 0 on dry-run with valid options" {
  run "$SCRIPT" -n -p -w nginx -v
  [ "$status" -eq 0 ]
}

@test "script handles SIGPIPE gracefully" {
  # This tests if script can handle pipe failures
  run bash -c "$SCRIPT -h | head -n 1"
  [ "$status" -eq 0 ]
}
