#!/bin/bash
#set -Eeuxo pipefail  # From https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
# Set locale to avoid issues with apt-get
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
#####################################################
# USE_GETOPTS determines whether to get flags (opts) from the command line
USE_GETOPTS=true
# Control logic defaults
# These are set as defaults
# If USE_GETOPTS=true, then they may be overridden by command-line input
DATABASE_ENGINE='mariadb'
DRY_RUN=false
ENSURE_BINARIES=false
ENSURE_FPM=false
ENSURE_MOODLE=false
ENSURE_REPOSITORY=false
ENSURE_ROLES=false
ENSURE_SSL=false
ENSURE_VIRTUALHOST=false
ENSURE_WEBSERVER=false
SHOW_USAGE=false
VERBOSE=false
WEBSERVER_ENGINE='apache'
declare -a packagesToEnsure

USER_CAN_SUDO_WITHOUT_PASSWORD=false
USER_IS_ROOT=false


# Users
apacheUser="www-data"
moodleUser="moodle"

# Site name
moodleSiteName="moodle.romn.co"

# Directories
apacheDocumentRoot="/var/www/html"
moodleDir="${apacheDocumentRoot}/${moodleSiteName}"
moodleDataDir="/home/${moodleUser}/moodledata"

# moodleVersion="39"
moodleVersion="310"

# PHP Modules

#php_apache="php libapache2-mod-php"
# List from https://docs.moodle.org/310/en/PHP
#php_modules_moodle_required="php-{curl,ctype,dom,iconv,json,mbstring,pcre,simplexml,spl,xml,zip}"
#php_modules_moodle_recommended="php-{intl,gd,openssl,soap,tokenizer,xmlrpc}"
# php_modules_moodle_conditional="php-mysql php-odbc php-pgsql php-ldap php-ntlm"
#php_modules_moodle_conditional="php-mysql"
#php_modules_memcached="php-memcached"
#php_modules_opensharing="php-{apcu,bz2,geoip,gmp,msgpack,pear,xml}"

# SSL option

#sslType="ubuntuSnakeoil"
#sslType="opensslSelfSigned"
#sslType="letsEncrypt"
#sslType="userProvidedAWSParameterStore"
#sslType="userProvidedAWSS3"

# AWS settings
#parameterStorePrefix="/prod/moodle/"
#s3BackupBucketName=""

#################
# Functions

apache_ensure_present() {
  system_packages_ensure apache2
  service_enable apache2
  service_start apache2
}

apache_get_status() {
  log "Apache - get service status"
  service_action status apache2
  log "Apache - get version"
  run_command apache2 -V
  log "Apache - list loaded/enabled modules"
  run_command apache2ctl -M
  log "Apache - list enabled sites"
  run_command apachectl -S
  log "Apache - check configuration files for errors"
  run_command apache2ctl -t
}

apache_ensure_fpm() {
  php_get_version
  if [[ "${ENSURE_FPM}" = true ]]; then
    log "Enabling Apache modules and config for ENSURE_FPM."
    run_command a2enmod proxy_fcgi setenvif
    run_command a2enconf "php${PHP_VERSION}-fpm"
    system_packages_ensure "libapache2-mod-fcgid"
  else
    log "ENSURE_FPM is not required."
    system_packages_ensure "libapache2-mod-php${PHP_VERSION}"
  fi
}

check_is_command_available() {
  local commandToCheck="$1"
  if command -v "${commandToCheck}" &> /dev/null; then
    log "${commandToCheck} command available"
  else
    # propagate error to caller
    return $?
  fi
}

check_user_is_root() {
  log "Test if UID is 0 (root)"
  if [[ "${UID}" -eq 0 ]]; then
    log "Setting USER_IS_ROOT to true"
    USER_IS_ROOT=true
  fi
  log "UID value: ${UID}"
  log "USER_IS_ROOT value: ${USER_IS_ROOT}"
}

check_user_can_sudo_without_password_entry() {
  log "Test if user can sudo without entering a password"
  if sudo -v &> /dev/null; then
    ${USER_CAN_SUDO_WITHOUT_PASSWORD}=true
    log "USER_CAN_SUDO_WITHOUT_PASSWORD value: ${USER_CAN_SUDO_WITHOUT_PASSWORD}"
  else
    log "USER_CAN_SUDO_WITHOUT_PASSWORD value: ${USER_CAN_SUDO_WITHOUT_PASSWORD}"
    # propagate error to caller
    return $?
  fi
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

log() {
  if [[ "${VERBOSE}" = true ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
  fi
}

moodle_configure_directories() {
  # Add moodle user for moodledata / Change ownerships and permissions
  run_command adduser --system ${moodleUser}
  run_command mkdir -p ${moodleDataDir}
  run_command chown -R ${apacheUser}:${apacheUser} ${moodleDataDir}
  run_command chmod 0777 ${moodleDataDir}
  run_command mkdir -p ${moodleDir}
  run_command chown -R root:${apacheUser} ${moodleDir}
  run_command chmod -R 0755 ${moodleDir}
}

moodle_download_extract() {
  # Download and extract Moodle
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz"
  log "Downloading and extracting ${moodleArchive}"
  run_command mkdir -p ${moodleDir}
  run_command wget -qO - "${moodleArchive}" | tar zx -C ${moodleDir} --strip-components 1
  run_command chown -R root:${apacheUser} ${moodleDir}
  run_command chmod -R 0755 ${moodleDir}
}

moodle_write_config() {
  FILE_CONFIG="${moodleDir}/config.php"
  echo "Writing file ${moodleDir}/config.php"

run_command tee "$FILE_CONFIG" > /dev/null << EOF
<?php  // Moodle configuration file

unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype  = 'mysql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost  = 'localhost';
\$CFG->dbname  = 'test_db';
\$CFG->dbuser  = 'root';
\$CFG->dbpass  = 'root';
\$CFG->prefix  = 'mdl_';
\$CFG->dboptions = array (
  'dbpersist' => 0,
  'dbport' => '3306',
  'dbsocket' => '',
  'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'https://${moodleSiteName}';
\$CFG->dataroot  = '${moodleDataDir}';
\$CFG->admin   = 'admin';

\$CFG->directorypermissions = 0777;
EOF

#if memcached_enabled=1
#Append
run_command tee -a "$FILE_CONFIG" > /dev/null << EOF
\$CFG->session_handler_class = '\core\session\memcached';
\$CFG->session_memcached_save_path = '${memcachedServer}:11211';
\$CFG->session_memcached_prefix = 'memc.sess.key.';
\$CFG->session_memcached_acquire_lock_timeout = 120;
\$CFG->session_memcached_lock_expire = 7200;
EOF

run_command tee -a "$FILE_CONFIG" > /dev/null << EOF
require_once(__DIR__ . '/lib/setup.php');

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!
EOF
}

php_get_version() {
  # Extract installed PHP version
  PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
  log "PHP version is ${PHP_VERSION}"
}

php_ensure_present() {
  if ! check_is_command_available php; then
    echo "PHP is not yet available. Adding."
    packagesToEnsure=("${packagesToEnsure[@]}" "php")
  else
    log "PHP is already available"
  fi
  if [[ "${ENSURE_FPM}" = true ]]; then
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-fcgid")
  else
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-php${PHP_VERSION}")
  fi
  system_repositories_ensure ppa:ondrej/php
  packagesToEnsure=("${packagesToEnsure[@]}" "${PHP_VERSION}-common")
  system_packages_ensure
  if [[ "${ENSURE_FPM}" == 1 ]]; then
    localServiceName="php${PHP_VERSION}-fpm"
  log "Starting ${localServiceName}"
    service_start "${localServiceName}"
  fi
}

php_get_status() {
  if ! check_is_command_available php; then
    err "PHP is not yet available. Exiting."
    exit
  else
    log "List all compiled PHP modules"
    php -m
  log "List all PHP modules installed by package manager"
    dpkg --get-selections | grep -i php
  fi
}

run_command() {
  if [[ ! -t 0 ]]; then
    cat
  fi
  printf -v cmd_str '%q ' "$@"
  if [[ "${DRY_RUN}" = true ]]; then
    log "DRY RUN: Not executing: ${SUDO}${cmd_str}" >&2
  else
    if [[ "${VERBOSE}" = true ]]; then
      log "VERBOSE: Preparing to execute: ${SUDO}${cmd_str}"
    fi
    ${SUDO} "$@"
  fi
}

service_action() {
  local action="$1"
  local service="$2"
  run_command systemctl "${action}" "${service}"
}

system_packages_ensure() {
  #uses global array "${packagesToEnsure[@]}"
  #log "Checking presence of packages ${packagesToEnsure}"
  targetvalue=( "${packagesToEnsure[@]}" )
  declare -p targetvalue
  #echo "use apt list --installed"
  apt -qq list "${packagesToEnsure[@]}" --installed
  # Install if not present, but don't upgrade if present
  run_command apt-get -qy install --no-upgrade "${packagesToEnsure[@]}"
}

system_repositories_ensure() {
  local repositoriesToEnsure="$1"

  run_command add-apt-repository "${repositoriesToEnsure}"
}

system_packages_repositories_update() {
  log "Updating package repositories"
  run_command apt-get -qq update
}

usage() {
  # Display the usage
  echo "Usage: ${0} [-fhlmnp] [-b binaries] [-d engine] [-r repository] [-s SSL provider] [-v virtualhost] [-w webservertype]" >&2
  echo "  -f FILE  Use FILE for the list of servers. Default: ${SERVER_LIST}." >&2
  echo '  -n       Dry run mode. Display the COMMAND that would have been executed and exit.' >&2
  echo '  -s       Execute the COMMAND using sudo on the remote server.' >&2
  echo '  -b                      Ensure binaries are present' >&2
  echo '  -d                      Specify database engine (mariadb)' >&2
  echo '  -f                      Use ENSURE_FPM with PHP and Webserver' >&2
  echo '  -h                      Print this help text and exit' >&2
  echo '  -l                      Local database server (uses option -d)' >&2
  echo '  -m                      Install and configure Moodle' >&2
  echo "  -n                      Dry run (don't make any changes)" >&2
  echo '  -p                      Ensure PHP is present' >&2
  echo '  -r                      Add repository to apt' >&2
  echo '  -s                      Use SSL (openssl)' >&2
  echo '  -v                      Ensure Virtualhost is present' >&2
  echo '  -V       Verbose mode. Displays the server name before executing COMMAND.' >&2
  echo '  -w                      Ensure Webserver is present (apache)' >&2
}

main() {

  # Check for ${#} - the number of positional parameters supplied
  if [[ ${#} -eq 0 && "${USE_GETOPTS}" = true ]]; then
    err "USE_GETOPTS=true, but no command-line options provided"
    usage
    exit 1
  fi

    while getopts ":fhlnVb:d:m:p:r:s:v:w:" flag; do
      case "${flag}" in
        b)
          ENSURE_BINARIES=true
          log "Command-line opt: ENSURE_BINARIES set to ${ENSURE_BINARIES}"
          binariesToEnsure=$OPTARG
          ;;
        d)
          DATABASE_ENGINE=$OPTARG
          log "Command-line opt: DATABASE_ENGINE set to ${DATABASE_ENGINE}"
          ;;
        f)
          ENSURE_FPM=true
          log "Command-line opt: ENSURE_FPM set to ${ENSURE_FPM}"
          ;;
        h)
          SHOW_USAGE=true
          log "Command-line opt: SHOW_USAGE set to ${SHOW_USAGE}"
          ;;
        l )
          databaseInstallLocalServer=true
          log "Command-line opt: databaseInstallLocalServer set to ${databaseInstallLocalServer}"
          ;;
        m)
          ENSURE_MOODLE=true
          log "Command-line opt: ENSURE_MOODLE set to ${ENSURE_MOODLE}"
          moodleOpts=$OPTARG
          ;;
        n)
          DRY_RUN=true
          log "Command-line opt: DRY_RUN set to ${DRY_RUN}"
          ;;
        p)
          ENSURE_REPOSITORY=true
          log "Command-line opt: ENSURE_REPOSITORY set to ${ENSURE_REPOSITORY}"
          repositoriesToEnsure=$OPTARG
          ;;
        r)
          ENSURE_ROLES=true
          log "Command-line opt: ENSURE_ROLES set to ${ENSURE_ROLES}"
          rolesToEnsure=$OPTARG
          ;;
        s)
          ENSURE_SSL=true
          log "Command-line opt: ENSURE_SSL set to ${ENSURE_SSL}"
          sslEngine=$OPTARG
          ;;
        v)
          ENSURE_VIRTUALHOST=true
          log "Command-line opt: ENSURE_VIRTUALHOST set to ${ENSURE_VIRTUALHOST}"
          virtualhostOptions=$OPTARG
          ;;
        V)
          VERBOSE=true
          log "Command-line opt: VERBOSE set to ${VERBOSE}"
          ;;
        w)
          ENSURE_WEBSERVER=true
          log "Command-line opt: ENSURE_WEBSERVER set to ${ENSURE_WEBSERVER}"
          webserverType=$OPTARG
          ;;
        \? )
          err "Invalid Option: -$OPTARG" 1>&2
          exit 1
          ;;
        : )
          err "Invalid Option: -$OPTARG requires an argument" 1>&2
          exit 1
          ;;
      esac
    done

  for opt in  USE_GETOPTS DRY_RUN VERBOSE SHOW_USAGE DATABASE_ENGINE ENSURE_BINARIES ENSURE_FPM ENSURE_MOODLE ENSURE_REPOSITORY \
              ENSURE_ROLES ENSURE_SSL ENSURE_VIRTUALHOST WEBSERVER_ENGINE; do
    readonly ${opt}
    log "${opt} set to ${!opt}"
  done

  #Set constants to read only
  #Set an array of constants
  #Set to readonly
  #Log values

  if [[ "${SHOW_USAGE}" = true ]]; then
    usage
    exit 1
  fi
  check_user_is_root
  if [[ "${USER_IS_ROOT}" = false ]]; then
    log "this user is not root"
    check_user_can_sudo_without_password_entry
    if [[ "${USER_CAN_SUDO_WITHOUT_PASSWORD}" = false ]]; then
      err "User requires a password to issue sudo commands. Exiting"
      err "Please re-run the script as root, or having sudo'd with a password"
      usage
      exit 1
    else
      SUDO='sudo '
      log "User can issue sudo commands without entering a password. Continuing"
    fi
  fi
  for opt in  USER_IS_ROOT USER_CAN_SUDO_WITHOUT_PASSWORD; do
    readonly ${opt}
    log "${opt} set to ${!opt}"
  done
  if [[ "${ENSURE_REPOSITORY}" = true ]]; then
    packagesToEnsure=("${packagesToEnsure[@]}" "software-properties-common")
    system_repositories_ensure "${repositoriesToEnsure}"
    system_packages_ensure
    system_packages_repositories_update
  else
    system_packages_repositories_update
  fi
  if [[ "${ENSURE_BINARIES}" = true ]]; then
    packagesToEnsure=("${packagesToEnsure[@]}" "${binariesToEnsure}")
    system_packages_ensure
  fi
  # apache_ensure_present
  # #apache_get_status
  # # With PHP enabled by GitHub Actions
  # #php_ensure_present
  # apache_ensure_fpm
  # #php_get_status
  # # Write sample website with PHPInfo
  # # Automated download
  # # Download Moodle
  # # Write config
  # # Install Database
  # moodle_configure_directories
  # moodle_download_extract
  # moodle_write_config
}

main "$@"

# LINKS
# https://www.howtogeek.com/howto/30184/10-ways-to-generate-a-random-password-from-the-command-line/
# https://serversforhackers.com/c/installing-mysql-with-debconf
# https://gist.github.com/Mins/4602864
# https://gercogandia.blogspot.com/2012/11/automatic-unattended-install-of.html
# https://github.com/moodlehq/moodle-php-apache/blob/master/root/tmp/setup/php-extensions.sh
# https://stackoverflow.com/questions/1298066/check-if-an-apt-get-package-is-installed-and-then-install-it-if-its-not-on-linu
# https://ovirium.com/blog/how-to-make-mysql-work-in-your-github-actions/
# https://github.com/RoverWire/virtualhost
# https://google.github.io/styleguide/shellguide.html
# https://stackoverflow.com/questions/7069682/how-to-get-arguments-with-flags-in-bash
# https://www.cyberciti.biz/faq/how-to-declare-boolean-variables-in-bash-and-use-them-in-a-shell-script/

# Usage

# No parameters - reports help
# Suggested:
# amp.sh -b awscli curl git wget -d mariadb -f -r moodle php webserver -s openssl -w apache -m 3.9 createcourse createusers localmemcached moosh populatedatabase

# -b = install binaries
# -b awscli curl git wget
# -d = database engine (MySQL, MariaDB, PosgreSQL)
# -f = use ENSURE_FPM (affects webserver, PHP)
# -h = help
# -l = local database (name, user, password, collation)
# -m = moodle options
# -m version createcourse createdatabase createusers localmemcached moosh populatedatabase
# -n = dry run
# -p = use package repository
# -p ppa:ondrej
# -r = roles
# -r database moodle php webserver
# -s = use SSL
# -s SSL type (letsencrypt, openssl)
# -v = virtualhost
# -v domain rootDirectory (honours "s" for SSL)
# -w webserver type (apache, nginx, both)

# Moodle will:
# create local database (calls database function itself)
# install memcached locally
# populate database
# install Moosh locally
