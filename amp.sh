#!/bin/bash
#set -Eeuxo pipefail  # From https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
ensureBinaries=0
databaseEngine=mariadb
useFPM=0
showHelp=0
ensureMoodle=0
dryRun=0
ensureRepository=0
ensureRoles=0
useSSL=0
ensureVirtualhost=0
ensureWebserver=0
webserverEngine=apache
declare -a packagesToEnsure

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
  echo "Apache - get service status"
  service_get_status apache2
  echo "Apache - get version"
  apache2 -V
  echo "Apache - list loaded/enabled modules"
  apache2ctl -M
  echo "Apache - list enabled sites"
  apachectl -S
  echo "Apache - check configuration files for errors"
  apache2ctl -t
}

apache_ensure_fpm() {
  php_get_version
  echo "Control variable useFPM is set to ${useFPM}"
  if [[ "${useFPM}" == 1 ]]; then
    echo "Enabling Apache modules and config for FPM."
    a2enmod proxy_fcgi setenvif
    a2enconf "php${PHP_VERSION}-fpm"
    system_packages_ensure "libapache2-mod-fcgid"
  else
    echo "FPM is not required."
    system_packages_ensure "libapache2-mod-php${PHP_VERSION}"
  fi
}

check_is_command_available() {
  local commandToCheck="$1"
  if command -v "${commandToCheck}" &> /dev/null; then
    echo "${commandToCheck} command available"
  else
    # propagate error to caller
    return $?
  fi
}

check_can_sudo_without_password_entry() {
  if sudo -v &> /dev/null; then
    echo "This user is able to sudo without requiring a password"
  else
    # propagate error to caller
    return $?
  fi
}

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

moodle_configure_directories() {
  # Add moodle user for moodledata / Change ownerships and permissions
  adduser --system ${moodleUser}
  mkdir -p ${moodleDataDir}
  chown -R ${apacheUser}:${apacheUser} ${moodleDataDir}
  chmod 0777 ${moodleDataDir}
  mkdir -p ${moodleDir}
  chown -R root:${apacheUser} ${moodleDir}
  chmod -R 0755 ${moodleDir}
}

moodle_download_extract() {
  # Download and extract Moodle
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz"
  echo "Downloading and extracting ${moodleArchive}"
  mkdir -p ${moodleDir}
  wget -qO - "${moodleArchive}" | tar zx -C ${moodleDir} --strip-components 1
  chown -R root:${apacheUser} ${moodleDir}
  chmod -R 0755 ${moodleDir}
}

moodle_write_config() {
  FILE_CONFIG="${moodleDir}/config.php"
  echo "Writing file ${moodleDir}/config.php"

tee "$FILE_CONFIG" > /dev/null << EOF
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
tee -a "$FILE_CONFIG" > /dev/null << EOF
\$CFG->session_handler_class = '\core\session\memcached';
\$CFG->session_memcached_save_path = '${memcachedServer}:11211';
\$CFG->session_memcached_prefix = 'memc.sess.key.';
\$CFG->session_memcached_acquire_lock_timeout = 120;
\$CFG->session_memcached_lock_expire = 7200;
EOF

tee -a "$FILE_CONFIG" > /dev/null << EOF
require_once(__DIR__ . '/lib/setup.php');

// There is no php closing tag in this file,
// it is intentional because it prevents trailing whitespace problems!
EOF
}

php_get_version() {
  # Extract installed PHP version
  PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
  echo "PHP version is ${PHP_VERSION}"
}

php_ensure_present() {
  if ! check_is_command_available php; then
    echo "PHP is not yet available. Adding."
    packagesToEnsure=("${packagesToEnsure[@]}" "php")
  else
    echo "PHP is already available"
  fi
  if [[ "${useFPM}" == 1 ]]; then
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-fcgid")
  else
    packagesToEnsure=("${packagesToEnsure[@]}" "libapache2-mod-php${PHP_VERSION}")
  fi
  system_repositories_ensure ppa:ondrej/php
  packagesToEnsure=("${packagesToEnsure[@]}" "${PHP_VERSION}-common")
  system_packages_ensure
  if [[ "${useFPM}" == 1 ]]; then
    localServiceName="php${PHP_VERSION}-fpm"
  echo "Starting ${localServiceName}"
    service_start "${localServiceName}"
  fi
}

php_get_status() {
  if ! check_is_command_available php; then
    err "PHP is not yet available. Exiting."
    exit
  else
    echo "List all compiled PHP modules"
    php -m
  echo "List all PHP modules installed by package manager"
    dpkg --get-selections | grep -i php
  fi
}

service_enable() {
  local service="$1"
  systemctl enable "${service}"
}

service_reload() {
  local service="$1"
  systemctl reload "${service}"
}

service_restart() {
  local service="$1"
  systemctl restart "${service}"
}

service_start() {
  local service="$1"
  systemctl start "${service}"
}

service_get_status() {
  local service="$1"
  systemctl status "${service}"
}

service_stop() {
  local service="$1"
  systemctl stop "${service}"
}

system_packages_ensure() {
  #uses global array "${packagesToEnsure[@]}"
  system_packages_repositories_update
  #echo "Checking presence of packages ${packagesToEnsure}"
  targetvalue=( "${packagesToEnsure[@]}" )
  declare -p targetvalue
  #echo "use apt list --installed"
  #apt -qq list "${packagesToEnsure[@]}" --installed
  # Install if not present, but don't upgrade if present
  #apt-get -qy install --no-upgrade "${packagesToEnsure[@]}"
}

system_repositories_ensure() {
  local repositoriesToEnsure="$1"

  add-apt-repository "${repositoriesToEnsure}"
}

system_packages_repositories_update() {
  echo "Updating package repositories"
  apt-get -qq update
}

usage() {
  echo "Usage: sudo $(basename $0) [-b -d engine -f -h -l -m -n -p -r repo -s SSL provider -v details -w webserver type]" 2>&1
echo "
Options:
-b                      Ensure binaries are present
-d                      Specify database engine (mariadb)
-f                      Use FPM with PHP and Webserver
-h                      Print this help text and exit
-l                      Local database server (uses option -d)
-m                      Install and configure Moodle
-n                      Dry run (don't make any changes)
-p                      Ensure PHP is present
-r                      Add repository to apt
-s                      Use SSL (openssl)
-v                      Ensure Virtualhost is present
-w                      Ensure Webserver is present (apache)
" 2>&1
}
# Control logic

# Mildly adapted from https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

main() {

  if [[ ${#} -eq 0 ]]; then
    showHelp=1
  fi

  while getopts ":b:d:fhl:m:np:r:s:v:w:" flag; do
    case "${flag}" in
      b)
        ensureBinaries=1
        binariesToEnsure=$OPTARG
        ;;
      d)
        databaseEngine=$OPTARG
        echo "database Engine $databaseEngine"
        ;;
      f)
        useFPM=1
        ;;
      h)
        showHelp=1
        ;;
      l )
        databaseInstallLocalServer=1
        echo "Install local database server $databaseInstallLocalServer"
        ;;
      m)
        ensureMoodle=1
        moodleOpts=$OPTARG
        ;;
      n)
        dryRun=1
        ;;
      p)
        ensureRepository=1
        repositoriesToEnsure=$OPTARG
        ;;
      r)
        ensureRoles=1
        rolesToEnsure=$OPTARG
        ;;
      s)
        useSSL=1
        sslEngine=$OPTARG
        ;;
      v)
        ensureVirtualhost=1
        virtualhostOptions=$OPTARG
        ;;
      w)
        ensureWebserver=1
        webserverType=$OPTARG
        ;;
      \? )
        echo "Invalid Option: -$OPTARG" 1>&2
        exit 1
        ;;
      : )
        echo "Invalid Option: -$OPTARG requires an argument" 1>&2
        exit 1
        ;;
    esac
  done

  if [[ "${showHelp}" -eq 1 ]]; then
    usage
    exit 1
  fi
  check_can_sudo_without_password_entry
  if [[ "${ensureRepository}" -eq 1 ]]; then
    packagesToEnsure=("${packagesToEnsure[@]}" "software-properties-common")
    system_packages_ensure
    system_repositories_ensure "${repositoriesToEnsure}"
  fi
  system_packages_repositories_update
  if [[ "${ensureBinaries}" -eq 1 ]]; then
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

# Usage

# No parameters - reports help
# Suggested:
# amp.sh -b awscli curl git wget -d mariadb -f -r moodle php webserver -s openssl -w apache -m 3.9 createcourse createusers localmemcached moosh populatedatabase

# -b = install binaries
# -b awscli curl git wget
# -d = database engine (MySQL, MariaDB, PosgreSQL)
# -f = use FPM (affects webserver, PHP)
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
