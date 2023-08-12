#!/usr/bin/env bash
# This shebang line uses the env command to locate the bash interpreter in the user's PATH
#  environment variable. This means that the script will be executed with the bash interpreter
#  that is found first in the user's PATH. This approach is more flexible and portable because
#  it relies on the system's PATH to find the appropriate interpreter.
#  It can be particularly useful in situations where the exact path to the interpreter
#  might vary across different systems.

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset

# Set locale to avoid issues with apt-get
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8


#####################################################
# USE_COMMAND_LINE_OPTS determines whether to get flags (opts) from the command line
# USE_COMMAND_LINE_OPTS='true'
# Control logic defaults
# These are set as defaults
# If USE_COMMAND_LINE_OPTS='true', then they may be overridden by command-line input

declare -A options

# Initialize default options
options=(
  ["USE_COMMAND_LINE_OPTS"]=true
  ["DRY_RUN"]=false
  ["ENSURE_BINARIES"]=false
  ["ENSURE_FPM"]=false
  ["ENSURE_LOCAL_DATABASE_SERVER"]=false
  ["ENSURE_PHP"]=false
  ["ENSURE_REPOSITORY"]=false
  ["ENSURE_ROLES"]=false
  ["ENSURE_SSL"]=false
  ["ENSURE_VIRTUALHOST"]=false
  ["ENSURE_WEBSERVER"]=false
  ["SHOW_USAGE"]=false
  ["VERBOSE"]=false
  ["DATABASE_ENGINE"]='mariadb'
  ["SSL_ENGINE"]='openssl'
  ["WEBSERVER_ENGINE"]='apache'
)

# Handle command-line options
handle_options() {
  while getopts ":b:dD:fhm:np:P:r:s:vw:" flag; do
    case "${flag}" in
      b) options["ENSURE_BINARIES"]=true; binariesToEnsure="$OPTARG" ;;
      d) options["ENSURE_LOCAL_DATABASE_SERVER"]=true ;;
      D) options["DATABASE_ENGINE"]=$OPTARG ;;
      f) options["ENSURE_FPM"]=true ;;
      h) options["SHOW_USAGE"]=true ;;
      m) options["MOODLE_VERSION"]=$OPTARG ;;
      n) options["DRY_RUN"]=true ;;
      p) options["ENSURE_PHP"]=true; desiredPhpVersion="$OPTARG" ;;
      P) options["ENSURE_REPOSITORY"]=true; repositoriesToEnsure="$OPTARG" ;;
      r) options["ENSURE_ROLES"]=true; rolesToEnsure="$OPTARG" ;;
      s) options["ENSURE_SSL"]=true; sslEngine="$OPTARG" ;;
      v) options["ENSURE_VIRTUALHOST"]=true; domain="$OPTARG" ;;
      w) options["ENSURE_WEBSERVER"]=true; webserverType="$OPTARG" ;;
      \?) echo_stderr "Invalid Option: -${OPTARG}" && exit 1 ;;
      :) echo_stderr "Invalid Option: -${OPTARG} requires an argument" && exit 1 ;;
    esac
  done
}


declare -a packagesToEnsure

# Used internally by the script
DATABASE_ENGINE_OPTIONS='mariadb mysql'
SSL_ENGINE_OPTIONS='openssl ubuntusnakeoil'
WEBSERVER_ENGINE_OPTIONS='apache nginx nginxproxyingapache'
USER_REQUIRES_PASSWORD_TO_SUDO='true'
NON_ROOT_USER='true'


# Users
apacheUser="www-data"
moodleUser="moodle"

# Site name
moodleSiteName="moodle.romn.co"

# Directories
apacheDocumentRoot="/var/www/html"
moodleDir="${apacheDocumentRoot}/${moodleSiteName}"
moodleDataDir="/home/${moodleUser}/moodledata"

# MOODLE_VERSION="39"
MOODLE_VERSION="310"

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
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  system_packages_ensure apache2
  service_enable apache2
  service_start apache2
}

apache_get_status() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  echo_stdout_verbose "Apache - get service status"
  service_action status apache2
  echo_stdout_verbose "Apache - get version"
  run_command apache2 -V
  echo_stdout_verbose "Apache - list loaded/enabled modules"
  run_command apache2ctl -M
  echo_stdout_verbose "Apache - list enabled sites"
  run_command apachectl -S
  echo_stdout_verbose "Apache - check configuration files for errors"
  run_command apache2ctl -t
}

apache_php_integration() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  php_get_version
  if ${ENSURE_FPM}; then
    echo_stdout_verbose "Enabling Apache modules and config for ENSURE_FPM."
    run_command a2enmod proxy_fcgi setenvif
    run_command a2enconf "php${DISCOVERED_PHP_VERSION}-fpm"
    system_packages_ensure "libapache2-mod-fcgid"
  else
    echo_stdout_verbose "ENSURE_FPM is not required."
    system_packages_ensure "libapache2-mod-php${DISCOVERED_PHP_VERSION}"
  fi
}

check_is_command_available() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local commandToCheck="$1"
  if command -v "${commandToCheck}" &> /dev/null; then
    echo_stdout_verbose "${commandToCheck} command available"
  else
    # propagate error to caller
    return $?
  fi
}

check_is_true() {
  local valueToCheck="$1"
  if [[ ${valueToCheck} = 'true' ]]; then
    return 0
  else
    return 1
  fi
}

check_user_is_root() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  echo_stdout_verbose "Test if UID is 0 (root)"
  if [[ "${UID}" -eq 0 ]]; then
    echo_stdout_verbose "Setting NON_ROOT_USER to true"
    NON_ROOT_USER='true'
  fi
  echo_stdout_verbose "UID value: ${UID}"
  echo_stdout_verbose "NON_ROOT_USER value: ${NON_ROOT_USER}"
}

check_user_can_sudo_without_password_entry() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  echo_stdout_verbose "Test if user can sudo without entering a password"
  if sudo -v &> /dev/null; then
    USER_REQUIRES_PASSWORD_TO_SUDO='false'
    echo_stdout_verbose "USER_REQUIRES_PASSWORD_TO_SUDO value: ${USER_REQUIRES_PASSWORD_TO_SUDO}"
    return 0
  else
    echo_stdout_verbose "USER_REQUIRES_PASSWORD_TO_SUDO value: ${USER_REQUIRES_PASSWORD_TO_SUDO}"
    return 1
  fi
}

echo_stderr() {
  local message="${*}"
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ERROR: ${message}" >&2
}

echo_stdout() {
  local message="${*}"
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: ${message}" >&1
}

echo_stdout_verbose() {
  local message="${*}"
  if check_is_true "${VERBOSE}"; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: VERBOSE: ${message}" >&1
  fi
}

# list_includes_item "10 11 12" "2"
list_includes_item() {
  local list="$1"
  local item="$2"
  [[ $list =~ (^|[[:space:]])"$item"($|[[:space:]]) ]]
  # exit code 0 for "yes, list does include item"
}

moodle_configure_directories() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
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
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  # Download and extract Moodle
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${MOODLE_VERSION}/moodle-latest-${MOODLE_VERSION}.tgz"
  echo_stdout_verbose "Downloading and extracting ${moodleArchive}"
  run_command mkdir -p ${moodleDir}
  run_command wget -qO - "${moodleArchive}" | tar zx -C ${moodleDir} --strip-components 1
  run_command chown -R root:${apacheUser} ${moodleDir}
  run_command chmod -R 0755 ${moodleDir}
}

moodle_write_config() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
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
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  # Extract installed PHP version
  DISCOVERED_PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
  echo_stdout_verbose "PHP version is ${DISCOVERED_PHP_VERSION}"
}

php_ensure_present() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  if ! check_is_command_available php; then
    echo "PHP is not yet available. Adding."
    packagesToEnsure=("${packagesToEnsure[@]}" "php")
  else
    echo_stdout_verbose "PHP is already available"
  fi
  if check_is_true "${ENSURE_FPM}"; then
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-fcgid")
  else
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-php${DISCOVERED_PHP_VERSION}")
  fi
  system_repositories_ensure ppa:ondrej/php
  packagesToEnsure=("${packagesToEnsure[@]}" "${DISCOVERED_PHP_VERSION}-common")
  system_packages_ensure
  if check_is_true "${ENSURE_FPM}"; then
    localServiceName="php${DISCOVERED_PHP_VERSION}-fpm"
  echo_stdout_verbose "Starting ${localServiceName}"
    service_start "${localServiceName}"
  fi
}

php_get_status() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  if ! check_is_command_available php; then
    echo_stderr "PHP is not yet available. Exiting."
    exit
  else
    echo_stdout_verbose "List all compiled PHP modules"
    php -m
  echo_stdout_verbose "List all PHP modules installed by package manager"
    dpkg --get-selections | grep -i php
  fi
}

run_command() {
  if [[ ! -t 0 ]]; then
    cat
  fi
  printf -v cmd_str '%q ' "$@"
  if check_is_true "${DRY_RUN}"; then
    echo_stdout_verbose "DRY RUN: Not executing: ${SUDO}${cmd_str}"
  else
    if check_is_true "${VERBOSE}"; then
      echo_stdout_verbose "Preparing to execute: ${SUDO}${cmd_str}"
    fi
    ${SUDO} "$@"
  fi
}

service_action() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local action="$1"
  local service="$2"
  run_command systemctl "${action}" "${service}"
}

system_packages_ensure() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  #uses global array "${packagesToEnsure[@]}"
  #echo_stdout_verbose "Checking presence of packages ${packagesToEnsure}"
  targetvalue=( "${packagesToEnsure[@]}" )
  declare -p targetvalue
  #echo "use apt list --installed"
  apt -qq list "${packagesToEnsure[@]}" --installed
  # Install if not present, but don't upgrade if present
  run_command apt-get -qy install --no-upgrade "${packagesToEnsure[@]}"
}

system_repositories_ensure() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local repositoriesToEnsure="$1"

  run_command add-apt-repository "${repositoriesToEnsure}"
}

system_packages_repositories_update() {
  echo_stdout_verbose "Updating package repositories"
  run_command apt-get -qq update
}

usage() {
  # Display the usage
  echo_stdout "Usage: ${0} [-b binaries] [-d] [-D engine] [-f] [-h] [-m version] [-M option] [-n] [-p version] [-P repository] [-r role] [-s SSL provider] [-v virtualhost] [-w webservertype]"
  echo_stdout '  -b       Ensure binaries are present'
  echo_stdout '  -d       Local database server (uses engine from option -D)'
  echo_stdout '  -D       Specify database engine (mariadb)'
  echo_stdout '  -f       Use ENSURE_FPM with PHP and Webserver'
  echo_stdout '  -h       Print this help text and exit'
  echo_stdout '  -m       Install and configure Moodle'
  echo_stdout '  -M       Moodle option'
  echo_stdout '  -n       Dry run mode. Display the COMMAND that would have been executed and exit.'
  echo_stdout '  -p       Ensure PHP is present. Specify version'
  echo_stdout '  -P       Add repository to apt'
  echo_stdout '  -r       Add role'
  echo_stdout '  -s       Execute the COMMAND using sudo on the remote server.'
  echo_stdout '  -v       Verbose mode. Displays the server name before executing COMMAND.'
  echo_stdout '  -w       Ensure Webserver is present (apache)'
}

main() {
  if check_is_true ${USE_COMMAND_LINE_OPTS}; then
    echo_stdout "USE_COMMAND_LINE_OPTS=${USE_COMMAND_LINE_OPTS}"
    # Check for ${#} - the number of positional parameters supplied
    if [[ ${#} -eq 0 ]]; then
      echo_stdout "No command-line options provided"
      usage
      exit 1
    else
      echo_stdout_verbose "Parse command line opts"
      while getopts ":dfhnvb:D:m:p:P:r:s:w:" flag; do
        case "${flag}" in
          b)
            ENSURE_BINARIES='true'
            echo_stdout_verbose "ENSURE_BINARIES use command-line opt of ${ENSURE_BINARIES}"
            binariesToEnsure=$OPTARG
            ;;
          d)
            ENSURE_LOCAL_DATABASE_SERVER='true'
            echo_stdout_verbose "ENSURE_LOCAL_DATABASE_SERVER use command-line opt of ${ENSURE_LOCAL_DATABASE_SERVER}"
            ;;
          D)
            DATABASE_ENGINE=$OPTARG
            echo_stdout_verbose "DATABASE_ENGINE use command-line opt of ${DATABASE_ENGINE}"
            ;;
          f)
            ENSURE_FPM='true'
            echo_stdout_verbose "ENSURE_FPM use command-line opt of ${ENSURE_FPM}"
            ;;
          h)
            SHOW_USAGE='true'
            echo_stdout_verbose "SHOW_USAGE use command-line opt of ${SHOW_USAGE}"
            ;;
          m)
            MOODLE_VERSION=${OPTARG}
            echo_stdout_verbose "MOODLE_VERSION use command-line opt of ${MOODLE_VERSION}"
            ;;
          n)
            DRY_RUN='true'
            echo_stdout_verbose "DRY_RUN use command-line opt of ${DRY_RUN}"
            ;;
          p)
            ENSURE_PHP='true'
            echo_stdout_verbose "ENSURE_PHP use command-line opt of ${ENSURE_PHP}"
            DESIRED_PHP_VERSION=${OPTARG}
            ;;
          P)
            ENSURE_REPOSITORY='true'
            echo_stdout_verbose "ENSURE_REPOSITORY use command-line opt of ${ENSURE_REPOSITORY}"
            repositoriesToEnsure=${OPTARG}
            ;;
          r)
            ENSURE_ROLES='true'
            echo_stdout_verbose "ENSURE_ROLES use command-line opt of ${ENSURE_ROLES}"
            rolesToEnsure=${OPTARG}
            ;;
          s)
            ENSURE_SSL='true'
            echo_stdout_verbose "ENSURE_SSL use command-line opt of ${ENSURE_SSL}"
            SSL_ENGINE=${OPTARG}
            ;;
          v)
            VERBOSE='true'
            echo_stdout_verbose "VERBOSE use command-line opt of ${VERBOSE}"
            ;;
          w)
            ENSURE_WEBSERVER='true'
            echo_stdout_verbose "ENSURE_WEBSERVER use command-line opt of ${ENSURE_WEBSERVER}"
            WEBSERVER_ENGINE=${OPTARG}
            ;;
          \? )
            echo_stderr "Invalid Option: -${OPTARG}"
            exit 1
            ;;
          : )
            echo_stderr "Invalid Option: -${OPTARG} requires an argument"
            exit 1
            ;;
        esac
      done
    fi
  fi

  for opt in  USE_COMMAND_LINE_OPTS DRY_RUN VERBOSE SHOW_USAGE ENSURE_BINARIES ENSURE_FPM ENSURE_REPOSITORY \
              MOODLE_VERSION ENSURE_ROLES ENSURE_SSL ENSURE_VIRTUALHOST; do
    readonly ${opt}
    echo_stdout_verbose "${opt} has value: ${!opt} ; Setting readonly"
  done

  # option validation - check values and combinations
  if [[ -n ${DATABASE_ENGINE} ]]; then
    if list_includes_item "${DATABASE_ENGINE_OPTIONS}" "${DATABASE_ENGINE}" ; then
      echo_stdout_verbose "${DATABASE_ENGINE} present in list ${DATABASE_ENGINE_OPTIONS}"
    else
      echo_stderr "${DATABASE_ENGINE} not found in list ${DATABASE_ENGINE_OPTIONS}"
      exit 1
    fi
  fi
  if check_is_true "${ENSURE_SSL}"; then
    if list_includes_item "${SSL_ENGINE_OPTIONS}" "${SSL_ENGINE}" ; then
      echo_stdout_verbose "${SSL_ENGINE} present in list ${SSL_ENGINE_OPTIONS}"
    else
      echo_stderr "${SSL_ENGINE} not found in list ${SSL_ENGINE_OPTIONS}"
      exit 1
    fi
  fi
  if [[ -n ${WEBSERVER_ENGINE} ]]; then
    if list_includes_item "${WEBSERVER_ENGINE_OPTIONS}" "${WEBSERVER_ENGINE}" ; then
      echo_stdout_verbose "${WEBSERVER_ENGINE} present in list ${WEBSERVER_ENGINE_OPTIONS}"
    else
      echo_stderr "${WEBSERVER_ENGINE} not found in list ${WEBSERVER_ENGINE_OPTIONS}"
      exit 1
    fi
  fi
  if check_is_true "${SHOW_USAGE}"; then
    usage
    exit 1
  fi
  check_user_is_root
  if check_is_true "${NON_ROOT_USER}"; then
    check_user_can_sudo_without_password_entry
    if check_is_true "${USER_REQUIRES_PASSWORD_TO_SUDO}"; then
      echo_stderr "User requires a password to issue sudo commands. Exiting"
      echo_stderr "Please re-run the script as root, or having sudo'd with a password"
      usage
      exit 1
    else
      SUDO='sudo '
      echo_stdout_verbose "User can issue sudo commands without entering a password. Continuing"
    fi
  fi
  # if check_is_true ${ENSURE_REPOSITORY}; then
  #   echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_REPOSITORY"
  #   packagesToEnsure=("${packagesToEnsure[@]}" "software-properties-common")
  #   system_repositories_ensure "${repositoriesToEnsure}"
  #   system_packages_ensure
  #   system_packages_repositories_update
  # else
  #   system_packages_repositories_update
  # fi
  if check_is_true "${ENSURE_BINARIES}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_BINARIES"
    packagesToEnsure=("${packagesToEnsure[@]}" "${binariesToEnsure}")
    system_packages_ensure
  fi
  if check_is_true "${ENSURE_WEBSERVER}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_WEBSERVER"
    apache_ensure_present
    apache_get_status
    apache_php_integration
  fi
  if check_is_true "${ENSURE_PHP}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_PHP"
    php_ensure_present
    php_get_status
  fi
  if check_is_true "${ENSURE_SSL}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_SSL"
  fi
  if check_is_true "${ENSURE_VIRTUALHOST}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_VIRTUALHOST"
  fi
  if check_is_true "${ENSURE_ROLES}"; then
    echo_stdout_verbose "Entered function ${FUNCNAME[0]} - ENSURE_ROLES"
    # # Write sample website with PHPInfo
    # # Automated download
    # # Download Moodle
    # # Write config
    # # Install Database
    # moodle_configure_directories
    # moodle_download_extract
    # moodle_write_config
  fi
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

## To do
# Support multi roles
# Support multi binaries
# Make packagesToEnsure per-function, rather than global
# Implement SSL Functions
# Non-getopts options
# Install a local database
# - test for a server
# - handle password generation
# Virtualhosts
# - domain, owner
# - download, extract
# - add PHP info test
# - curl/wget test
# - write config function (awk/sed/template/HEREDOC)
# Add backup scripts
# Add cron
#
