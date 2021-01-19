#!/bin/bash
#set -Eeuxo pipefail  # From https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

# Constants

## Namespace

# Leave empty if you want to parse options
namespace=""
#namespace=database
#namespace=moodle
#namespace=php
#namespace=tool
#namespace=webserver

### Database

databaseEngine=mysql
databaseInstallLocalServer=false
#databaseCreateLocalDatabase=false
#databaseCreateLocalUser=false

### Moodle

### PHP
phpUseFPM=1

### Virtualhost

### Webserver

webserverEngine=apache
webserverUseFPM=1

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
  system_packages_add apache2
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
  echo "Control variable apacheUseFPM is set to ${apacheUseFPM}"
  if [[ "${apacheUseFPM}" == 1 ]]; then
  echo "Enabling Apache modules and config for FPM."
  a2enmod proxy_fcgi setenvif
  a2enconf "php${PHP_VERSION}-fpm"
  system_packages_add "libapache2-mod-fcgid"
  else
  echo "FPM is not required."
  system_packages_add "libapache2-mod-php${PHP_VERSION}"
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
  packagesToInstall=()
  if ! check_is_command_available php; then
  echo "PHP is not yet available. Adding."
  packagesToInstall=("${packagesToInstall[@]}" "php")
  else
  echo "PHP is already available"
  fi
  if [[ "${phpUseFPM}" == 1 ]]; then
  packagesToInstall=("${packagesToInstall[@]}" "libapache2-mod-fcgid")
  else
  packagesToInstall=("${packagesToInstall[@]}" "libapache2-mod-php${PHP_VERSION}")
  fi
  system_packages_repositories_add ppa:ondrej/php
  packagesToInstall=("${packagesToInstall[@]}" "${PHP_VERSION}-common")
  system_packages_add "${packagesToInstall[@]}"
  if [[ "${phpUseFPM}" == 1 ]]; then
  localServiceName="php${PHP_VERSION}-fpm"
  echo "Starting ${localServiceName}"
  service_start "${localServiceName}"
  fi
}

php_get_status() {
  if ! check_is_command_available php; then
  echo "PHP is not yet available. Exiting."
	  exit
  else
  echo "List all compiled PHP modules"
  php -m
  echo "List all PHP modules installed by package manager"
  dpkg --get-selections | grep -i php
  fi
}

print_usage() {
  echo "Usage: $(basename ${0}) [database|moodle|php|virtualhost|webserver][-s schemaname] [-d databasename] [-u username] -f -t -h"
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

system_packages_add() {
  local packagesToCheck="$1"
  system_packages_repositories_update
  echo "Checking presence of packages ${packagesToCheck}"
  echo "use apt list --installed"
  apt -qq list "${packagesToCheck}" --installed
  # Install if not present, but don't upgrade if present
  apt-get -qy install --no-upgrade "${packagesToCheck}"
}

system_packages_repositories_add() {
  local repositoriesToAdd="$1"
  system_packages_add software-properties-common
  add-apt-repository "${repositoriesToAdd}"
}

system_packages_repositories_update() {
	echo "Updating package repositories"
	apt-get -qq update
}

# Control logic

# Mildly adapted from https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/

main() {
  if [[ -z "${namespace}" ]]; then
  echo "Namespace is not set. Parsing options"
  namespace=$1; shift  # Remove namespace from the argument list
  echo "Namespace is ${namespace}"
  case "${namespace}" in
    database)
    while getopts ":e:s" opt; do
      case ${opt} in
        e)
          databaseEngine=$OPTARG
          echo "database Engine $databaseEngine"
          ;;
        s )
          databaseInstallLocalServer=1
          echo "Install local database server $databaseInstallLocalServer"
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
    shift $((OPTIND -1))
    ;;
    php)
    while getopts ":f" opt; do
      case ${opt} in
        f)
          phpUseFPM=1
          echo "PHP fpm $phpUseFPM"
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
    shift $((OPTIND -1))
    ;;
    webserver)
      while getopts ":e:sv" opt; do
        case ${opt} in
          e)
            webserverEngine=$OPTARG
            echo "webserver Engine $webserverEngine"
            ;;
          s )
            webserverInstallLocalServer=1
            echo "Install local webserver $webserverInstallLocalServer"
            ;;
          v )
            createVirtualhost=1
            echo "create virtualhost $createVirtualhost"
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
      shift $((OPTIND -1))
      ;;
    *)
      echo "namespace is not permitted"
      exit 1
      ;;
  esac
  fi

  # check_can_sudo_without_password_entry
  # system_packages_repositories_update
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
