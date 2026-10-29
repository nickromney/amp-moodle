#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  awk '/^php_security_verify_version\(\)/,/^}/; /^php_security_verify_backport\(\)/,/^}/; /^php_security_verify_binary\(\)/,/^}/; /^php_security_verify_fpm\(\)/,/^}/; /^php_security_verify_apache_module\(\)/,/^}/; /^php_verify\(\)/,/^}/; /^php_ensure\(\)/,/^}/' "$ROOT/laemp.sh" > "$BATS_TEST_TMPDIR/functions.sh"
  cat > "$BATS_TEST_TMPDIR/bin/php" <<'SH'
#!/bin/bash
printf 'PHP %s (cli)\n' "$MOCK_CLI"
SH
  cat > "$BATS_TEST_TMPDIR/bin/php-fpm8.4" <<'SH'
#!/bin/bash
printf 'PHP %s (fpm-fcgi)\n' "$MOCK_FPM"
SH
  cat > "$BATS_TEST_TMPDIR/bin/dpkg-query" <<'SH'
#!/bin/bash
[[ "$*" == *libapache2-mod-php8.4 ]] || exit 1
printf '%s' "${MOCK_MODULE:-installed 8.4.27-1}"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" MOCK_CLI=8.4.27 MOCK_FPM=8.4.27
}

run_check() {
  run /bin/bash -c 'source "$1"; log() { printf "%s\n" "$*"; }; tool_exists() { command -v "$1" >/dev/null; }; PHP_VERSION_MAJOR_MINOR=8.4; PHP_ALONGSIDE=false; SKIP_PACKAGE_INSTALLS=false; DRY_RUN_CHANGES=false; eval "$2"' _ "$BATS_TEST_TMPDIR/functions.sh" "$1"
}

@test "existing PHP below the floor cannot satisfy php_ensure" {
  export MOCK_CLI=8.4.26
  run_check 'php_ensure'
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected patched PHP 8.4"* ]]
}

@test "fixed existing PHP succeeds without installing packages" {
  run_check 'package_ensure() { exit 99; }; php_ensure'
  [ "$status" -eq 0 ]
}

@test "CLI and FPM must both match the selected branch and floor" {
  export MOCK_FPM=8.4.26
  run_check 'php_verify --exit-on-failure; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.3.36
  run_check 'php_security_verify_fpm'
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.4.28
  run_check 'php_security_verify_fpm'
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.4.27
  run_check 'php_verify --exit-on-failure; php_security_verify_fpm'
  [ "$status" -eq 0 ]
}

@test "Apache module must be installed, fixed and match CLI" {
  for MOCK_MODULE in 'installed 8.4.26-1' 'installed 8.4.28-1' 'installed 8.4.27~rc1-1' 'installed 8.4.27-rc1' 'installed 8.4.27RC1-1' 'not-installed 8.4.27-1' garbage; do
    export MOCK_MODULE
    run_check 'php_security_verify_apache_module'
    [ "$status" -ne 0 ] || { echo "$MOCK_MODULE unexpectedly accepted"; return 1; }
  done
  export MOCK_MODULE='installed 8.4.27-1~deb13u1'
  run_check 'php_security_verify_apache_module'
  [ "$status" -eq 0 ]
}

@test "shared standalone check rejects a vulnerable or mismatched FPM" {
  export MOCK_FPM=8.4.28
  run /bin/bash "$ROOT/laemp.sh" --check-php-security
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.4.26
  run /bin/bash "$ROOT/laemp.sh" --check-php-security
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.4.27
  run /bin/bash "$ROOT/laemp.sh" --check-php-security
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "missing CLI or FPM is refused, including skip-install mode" {
  printf '#!/bin/bash\nexit 127\n' > "$BATS_TEST_TMPDIR/bin/php-fpm8.4"
  run_check 'SKIP_PACKAGE_INSTALLS=true; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  printf '#!/bin/bash\nexit 127\n' > "$BATS_TEST_TMPDIR/bin/php"
  run_check 'SKIP_PACKAGE_INSTALLS=true; php_ensure'
  [ "$status" -ne 0 ]
}

@test "skip-install mode checks an unversioned FPM fallback" {
  rm "$BATS_TEST_TMPDIR/bin/php-fpm8.4"
  cat > "$BATS_TEST_TMPDIR/bin/php-fpm" <<'SH'
#!/bin/bash
printf 'PHP %s (fpm-fcgi)\n' "$MOCK_FPM"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/php-fpm"
  export MOCK_FPM=8.4.28
  run_check 'SKIP_PACKAGE_INSTALLS=true; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  export MOCK_FPM=8.4.27
  run_check 'SKIP_PACKAGE_INSTALLS=true; php_security_verify_fpm'
  [ "$status" -eq 0 ]
}

@test "both prerequisite Dockerfiles run the shared postcondition after PHP installation" {
  for file in "$ROOT/Dockerfile.prereqs.debian" "$ROOT/Dockerfile.prereqs.ubuntu"; do
    run awk '/^COPY laemp.sh \/usr\/local\/bin\/laemp.sh/ { copied=NR } /    php8.4-fpm/ { installed=NR } /bash \/usr\/local\/bin\/laemp.sh --check-php-security/ { checked=NR } END { exit !(copied && installed > copied && checked > installed) }' "$file"
    [ "$status" -eq 0 ] || { echo "$file has no ordered postcondition"; return 1; }
  done
}

@test "unknown, prerelease, and unverified backport versions fail closed" {
  for MOCK_CLI in 8.4.27RC1 8.4.27-dev 8.4.26-1+backport 8.6.0 garbage; do
    export MOCK_CLI
    run_check 'php_verify --exit-on-failure'
    [ "$status" -ne 0 ]
  done
}

@test "branch-specific floors reject old patches and accept fixed patches" {
  for pair in 8.2:35 8.3:36 8.4:27 8.5:12; do
    branch="${pair%:*}" floor="${pair#*:}"
    export MOCK_CLI="$branch.$((floor - 1))"
    run_check "PHP_VERSION_MAJOR_MINOR=$branch; php_security_verify_binary php"
    [ "$status" -ne 0 ]
    export MOCK_CLI="$branch.$floor"
    run_check "PHP_VERSION_MAJOR_MINOR=$branch; php_security_verify_binary php"
    [ "$status" -eq 0 ]
  done
}

@test "documented Ubuntu backport requires exact package, ownership and integrity" {
  cp "$BATS_TEST_TMPDIR/bin/php-fpm8.4" "$BATS_TEST_TMPDIR/bin/php-fpm8.3"
  printf 'mock Apache module\n' > "$BATS_TEST_TMPDIR/libphp8.3.so"
  export MOCK_CLI_MD5 MOCK_FPM_MD5 MOCK_MODULE_MD5
  MOCK_CLI_MD5="$(md5sum "$BATS_TEST_TMPDIR/bin/php" | awk '{print $1}')"
  MOCK_FPM_MD5="$(md5sum "$BATS_TEST_TMPDIR/bin/php-fpm8.3" | awk '{print $1}')"
  MOCK_MODULE_MD5="$(md5sum "$BATS_TEST_TMPDIR/libphp8.3.so" | awk '{print $1}')"
  cat > "$BATS_TEST_TMPDIR/bin/lsb_release" <<'SH'
#!/bin/bash
case "$1" in -is) echo Ubuntu ;; -rs) echo 24.04 ;; *) exit 1 ;; esac
SH
  cat > "$BATS_TEST_TMPDIR/bin/dpkg-query" <<'SH'
#!/bin/bash
arg="${!#}"
case "$1" in
  -W) printf 'installed %s' "${MOCK_BACKPORT_PACKAGE:-8.3.6-0ubuntu0.24.04.13}" ;;
  --control-show)
    case "$2" in
      php8.3-cli) file="${BATS_TEST_TMPDIR#/}/bin/php"; digest="$MOCK_CLI_MD5" ;;
      php8.3-fpm) file="${BATS_TEST_TMPDIR#/}/bin/php-fpm8.3"; digest="$MOCK_FPM_MD5" ;;
      libapache2-mod-php8.3) file="${BATS_TEST_TMPDIR#/}/libphp8.3.so"; digest="$MOCK_MODULE_MD5" ;;
      *) exit 1 ;;
    esac
    [[ "${MOCK_NO_CHECKSUM:-false}" != true ]] && printf '%s  %s\n' "$digest" "$file" ;;
  -S) case "$arg" in
      */php) package=php8.3-cli ;;
      */php-fpm8.3) package=php8.3-fpm ;;
      */libphp8.3.so) package=libapache2-mod-php8.3 ;;
      *) exit 1 ;;
    esac
    printf '%s: %s' "${MOCK_OWNER:-$package}" "$arg" ;;
  *) exit 1 ;;
esac
SH
  cat > "$BATS_TEST_TMPDIR/bin/dpkg" <<'SH'
#!/bin/bash
[[ "$1" == -V ]] || exit 1
printf '%s' "${MOCK_INTEGRITY:-}"
SH
  cat > "$BATS_TEST_TMPDIR/bin/readlink" <<'SH'
#!/bin/bash
[[ "$1" == -f ]] || exit 1
if [[ "$2" == /usr/lib/apache2/modules/libphp8.3.so ]]; then
  printf '%s\n' "$BATS_TEST_TMPDIR/libphp8.3.so"
else
  printf '%s\n' "$2"
fi
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/lsb_release" "$BATS_TEST_TMPDIR/bin/dpkg-query" "$BATS_TEST_TMPDIR/bin/dpkg" "$BATS_TEST_TMPDIR/bin/readlink"
  export MOCK_CLI=8.3.6 MOCK_FPM=8.3.6 MOCK_INTEGRITY='??5?????? c /etc/php/8.3/fpm/pool.d/www.conf'
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm && php_security_verify_apache_module'
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  export MOCK_BACKPORT_PACKAGE=8.3.6-0ubuntu0.24.04.12
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  export MOCK_BACKPORT_PACKAGE=8.3.6-0ubuntu0.24.04.13+unknown
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  unset MOCK_BACKPORT_PACKAGE
  export MOCK_OWNER=unknown-package
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  unset MOCK_OWNER
  printf '# modified executable\n' >> "$BATS_TEST_TMPDIR/bin/php-fpm8.3"
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm'
  [ "$status" -ne 0 ]
  cp "$BATS_TEST_TMPDIR/bin/php-fpm8.4" "$BATS_TEST_TMPDIR/bin/php-fpm8.3"
  export MOCK_NO_CHECKSUM=true
  run_check 'PHP_VERSION_MAJOR_MINOR=8.3; php_security_verify_fpm'
  [ "$status" -ne 0 ]
}

@test "dry run does not claim to verify FPM or execute it" {
  rm "$BATS_TEST_TMPDIR/bin/php-fpm8.4"
  run_check 'DRY_RUN_CHANGES=true; php_security_verify_fpm'
  [ "$status" -eq 0 ]
}

@test "new package installation must pass the same CLI postcondition" {
  export MOCK_CLI=8.4.26
  run_check 'tool_exists() { [[ -f "$BATS_TEST_TMPDIR/installed" ]]; }; repository_ensure() { :; }; package_ensure() { touch "$BATS_TEST_TMPDIR/installed"; }; DISTRO=Ubuntu; package_manager=apt; php_ensure'
  [ "$status" -ne 0 ]
  [ -f "$BATS_TEST_TMPDIR/installed" ]
  rm "$BATS_TEST_TMPDIR/installed"
  export MOCK_CLI=8.4.27
  run_check 'tool_exists() { [[ -f "$BATS_TEST_TMPDIR/installed" ]]; }; repository_ensure() { :; }; package_ensure() { touch "$BATS_TEST_TMPDIR/installed"; }; DISTRO=Ubuntu; package_manager=apt; php_ensure'
  [ "$status" -eq 0 ]
}

@test "alongside mode checks the versioned CLI rather than the default CLI" {
  cp "$BATS_TEST_TMPDIR/bin/php" "$BATS_TEST_TMPDIR/bin/php8.4"
  export MOCK_CLI=8.4.26
  run_check 'PHP_ALONGSIDE=true; php_verify --exit-on-failure'
  [ "$status" -ne 0 ]
  export MOCK_CLI=8.4.27
  run_check 'PHP_ALONGSIDE=true; php_verify --exit-on-failure'
  [ "$status" -eq 0 ]
}
