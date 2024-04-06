#!/usr/bin/env bash
# This shebang line uses the env command to locate the bash interpreter in the user's PATH
#  environment variable. This means that the script will be executed with the bash interpreter
#  that is found first in the user's PATH. This approach is more flexible and portable because
#  it relies on the system's PATH to find the appropriate interpreter.
#  It can be particularly useful in situations where the exact path to the interpreter
#  might vary across different systems.

# Set up error handling
set -euo pipefail

# Set locale to avoid issues with apt
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

# Define default options
# I tend to leave these as false, and set with command line options
DRY_RUN_CHANGES=false
APACHE_ENSURE=false
FPM_ENSURE=false
MEMCACHED_ENSURE=false
MOODLE_ENSURE=false
NGINX_ENSURE=false
PHP_ENSURE=false
DEFAULT_MOODLE_VERSION="311"
DEFAULT_PHP_VERSION="7.2"
MOODLE_VERSION="${DEFAULT_MOODLE_VERSION}"
PHP_VERSION="${DEFAULT_PHP_VERSION}"
APACHE_NAME="apache2" # Change to "httpd" for CentOS

# Moodle database
DB_TYPE="mysqli"
DB_HOST="localhost"
DB_NAME="moodle"
DB_USER="moodle"
DB_PASS="moodle"
DB_PREFIX="mdl_"

# Users
webserverUser="www-data"
moodleUser="moodle"

# Site name
moodleSiteName="moodle.romn.co"

# Directories
documentRoot="/var/www/html"
moodleDir="${documentRoot}/${moodleSiteName}"
moodleDataDir="/home/${moodleUser}/moodledata"

# Logging
declare -a LOG_LEVELS
LOG_LEVELS=("error" "info" "verbose" "debug")
LOG_LEVEL="info"
log_to_file=true # Control constant to determine if logging to file

# Used internally by the script
USE_SUDO=false
CI_MODE=false

# Get script directory and filename
SCRIPT_DIRECTORY=$(dirname "$0")
SCRIPT_NAME=$(basename "$0")

# Supported distributions
readonly DISTRO
readonly CODENAME

# helper functions

function echo_usage() {
  log info "Usage: $0 [options]"
  log info "Options:"
  log info "  -c, --ci         Run in CI mode (no prompts)"
  log info "  -d, --database   Database type (default: MySQL, supported: [mysql, pgsql])"
  log info "  -f, --fpm        Enable FPM for the web server (requires -w apache (-w nginx sets fpm by default))"
  log info "  -h, --help       Display this help message"
  log info "  -m, --moodle     Ensure Moodle of specified version is installed (default: ${MOODLE_VERSION})"
  log info "  -M, --memcached  Ensure Memcached is installed"
  log info "  -n, --nop        Dry run (show commands without executing)"
  log info "  -p, --php        Ensure PHP is installed. If not, install specified version (default: ${PHP_VERSION})"
  log info "  -s, --sudo       Use sudo for running commands (default: false)"
  log info "  -v, --verbose    Enable verbose output"
  log info "  -w, --web        Web server type (default: apache, supported: [apache, nginx])"
  log info "  Note: Options -d, -m, and -p require an argument but have defaults."
}

# Set up logging
log_init() {
  # Check if the log file is writable
  if [[ $log_to_file = true ]]; then
    LOG_DIRECTORY="${SCRIPT_DIRECTORY}/logs"
    # Create log directory if needed
    mkdir -p "$LOG_DIRECTORY"
    LOG_FILE="${LOG_DIRECTORY}/${SCRIPT_NAME}_$(date +'%Y-%m-%dT%H:%M:%S%z').log"
    if ! touch "$LOG_FILE" 2>/dev/null; then
      echo "Log file is not writable. Disabling file logging."
      log_to_file=false
    fi
  fi
}

log() {

  local log_level="$1"
  local message="$2"

  # if $LOG_LEVEL is not set default it to info
  if [[ -z ${LOG_LEVEL+x} ]]; then
    LOG_LEVEL="info"
  fi

  # Filter log level
  case ${LOG_LEVEL} in
  error)
    if [[ ${log_level} != "error" ]]; then
      return
    fi
    ;;

  info)
    if [[ ${log_level} == "verbose" || ${log_level} == "debug" ]]; then
      return
    fi
    ;;

  verbose)
    if [[ ${log_level} == "debug" ]]; then
      return
    fi
    ;;
  esac

  # Build log message
  local log_msg

  if [[ ${LOG_LEVEL} == "debug" ]]; then
    log_msg="[$(date +'%Y-%m-%dT%H:%M:%S%z')] "
    local source="${BASH_SOURCE[1]}:${BASH_LINENO[1]}"
    log_msg+="${source} "
  fi

  if [[ ${log_level} == "error" ]]; then
    log_msg+="[ERROR] "
  fi

  log_msg+="${message}"

  # Output log message
  if [[ ${log_level} == "error" ]]; then
    echo "${log_msg}" >&2
  else
    echo "${log_msg}"
  fi

  # Log to file
  if [[ ${log_to_file} == "true" ]]; then
    printf '%s\n' "${log_msg}" >>"${LOG_FILE}"
  fi

}

# Validate LOG_LEVEL
check_log_level() {
  log debug "Entered function: ${FUNCNAME[0]}"
  # check that $LOG_LEVEL is set and not empty
  if [[ -z "$LOG_LEVEL" ]]; then
    log error "Log level not set"
    # shellcheck disable=SC2153
    log info "Valid log levels are: ${LOG_LEVELS[*]}"
    echo_usage
    exit 1
  fi

  if ! printf '%s\0' "${LOG_LEVELS[@]}" | grep -Fxqz -- "$LOG_LEVEL"; then
    log error "Invalid log level: $LOG_LEVEL"
    log info "Valid log levels are: ${LOG_LEVELS[*]}"
    echo_usage
    exit 1
  fi
  log verbose "LOG_LEVEL: $LOG_LEVEL"
  log debug "Exited function: ${FUNCNAME[0]}"
}

function apply_template() {
  local template="$1"
  shift
  local substitutions=("$@")

  for substitution in "${substitutions[@]}"; do
    IFS="=" read -r key value <<<"$substitution"
    template="${template//\{\{$key\}\}/$value}"
  done

  echo "$template"
}

function check_command() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  if [[ "$1" == "--exit-on-failure" ]]; then
    exit_on_failure=true
    shift # Remove the flag from the arguments list
  fi

  for command in "$@"; do
    if type -P "${command}" &>/dev/null; then
      log verbose "Dependency is present: ${command}"
    else
      log error "Dependency not found: ${command}, please install it and run this script again."
      if [[ "$exit_on_failure" == true ]]; then
        exit 1
      fi
    fi
  done
}

function package_manager_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  if check_command apt; then
    package_manager="apt"
  else
    log error "Error: Package manager not found."
    exit 1
  fi
}

function package_ensure() {
  local no_install_recommends_flag=""
  if [ "$1" == "--no-install-recommends" ]; then
    shift
    if [ "$package_manager" == "apt" ]; then
      no_install_recommends_flag="--no-install-recommends"
    else
      log error "Warning: --no-install-recommends flag is not supported for this package manager."
    fi
  fi

  local packages=("$@")
  local missing_packages=()

  for package in "${packages[@]}"; do
    case "$package_manager" in
    apt)
      if ! dpkg -s "$package" >/dev/null 2>&1; then
        missing_packages+=("$package")
      fi
      ;;
    *)
      log error "Error: Unsupported package manager."
      exit 1
      ;;
    esac
  done

  if [ ${#missing_packages[@]} -gt 0 ]; then
    log verbose "Installing missing packages: ${missing_packages[*]}"

    case "$package_manager" in
    apt)
      run_command --makes-changes apt-get update
      run_command --makes-changes apt-get install --yes $no_install_recommends_flag "${missing_packages[@]}"
      ;;
    *)
      log error "Error: Unsupported package manager."
      exit 1
      ;;
    esac
  else
    log verbose "All packages are already installed."
  fi
}

function repository_ensure() {
  local repositories=("$@")
  local missing_repositories=()

  case "$package_manager" in
  apt)
    for repository in "${repositories[@]}"; do
      if ! run_command grep -q "^deb .*$repository" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
        missing_repositories+=("$repository")
      fi
    done
    ;;
  *)
    log error "Error: Repositories management for this package manager is not supported."
    exit 1
    ;;
  esac

  if [ ${#missing_repositories[@]} -gt 0 ]; then
    log verbose "Adding missing repositories: ${missing_repositories[*]}"

    case "$package_manager" in
    apt)
      for repository in "${missing_repositories[@]}"; do
        run_command --makes-changes add-apt-repository "$repository"
      done
      run_command --makes-changes apt-get update
      ;;
    *)
      log error "Error: Unsupported package manager."
      exit 1
      ;;
    esac
  else
    log verbose "All repositories are already added."
  fi
}

function replace_file_value() {

  local current_value="$1"
  local new_value="$2"
  local file_path="$3"

  # Acquire lock on file
  exec 200>"$file_path"
  flock -x 200 || exit 1

  if [ -f "$file_path" ]; then

    # Check if current value already exists
    if run_command grep -q "$current_value" "$file_path"; then

      log verbose "Value $current_value already set in $file_path"

    else

      # Value not present, go ahead and replace
      run_command --makes-changes sed -i "s|$current_value|$new_value|" "$file_path"
      log verbose "Replaced $current_value with $new_value in $file_path"

    fi

  fi

  # Release lock
  flock -u 200

}

function run_command() {
  if [[ ! -t 0 ]]; then
    cat
  fi

  local makes_changes=false # Default to false

  if [[ "$1" == "--makes-changes" ]]; then
    makes_changes=true
    shift # Remove the flag from the arguments list
  fi

  local cmd=("$@")

  # if $USE_SUDO is not set default it to false
  if [[ -z ${USE_SUDO+x} ]]; then
    USE_SUDO=false
  fi
  # Decide whether to use sudo based on the global USE_SUDO setting
  if $USE_SUDO; then
    cmd=("sudo" "${cmd[@]}")
  fi
  # Convert cmd array to string for logging
  printf -v cmd_str '%q ' "${cmd[@]}"

  # if $DRY_RUN_CHANGES is not set default it to false
  if [[ -z ${DRY_RUN_CHANGES+x} ]]; then
    DRY_RUN_CHANGES=false
  fi

  if [[ $makes_changes == true && $DRY_RUN_CHANGES == true ]]; then
    if [[ -t 1 ]]; then
      log verbose "DRY RUN: Would execute: ${cmd_str}"
    fi
    return 0
  else
    # Check if output is being captured
    if [[ -t 1 ]]; then
      log verbose "Preparing to execute: ${cmd_str}"
    fi

    # if $log_to_file is not set default it to false
    if [[ -z ${log_to_file+x} ]]; then
      log_to_file=false
    fi

    if [[ "${log_to_file}" == "true" ]]; then
      "${cmd[@]}" | tee -a "${LOG_FILE}"
    else
      "${cmd[@]}"
    fi
    return $?
  fi
}

function acme_cert_provider() {
  local provider=""
  case "$1" in
  staging) provider="https://acme-staging-v02.api.letsencrypt.org/directory" ;;
  production) provider="https://acme-v02.api.letsencrypt.org/directory" ;;
  *)
    log error "Invalid provider option: $1"
    exit 1
    ;;
  esac
  echo "$provider"
}

function acme_cert_request() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local domain=""
  local email=""
  local san_entries=""
  local challenge_type="dns"
  local provider="https://acme-staging-v02.api.letsencrypt.org/directory" # Default to Let's Encrypt sandbox

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --domain)
      shift
      domain="$1"
      shift
      ;;
    --email)
      shift
      email="$1"
      shift
      ;;
    --san)
      shift
      san_entries="$1"
      shift
      ;;
    --challenge)
      shift
      challenge_type="$1"
      shift
      ;;
    --provider)
      shift
      provider="$1"
      shift
      ;;
    *)
      log error "Invalid option: $1"
      exit 1
      ;;
    esac
  done

  if [ -z "$domain" ] || [ -z "$email" ]; then
    log error "Missing or incomplete parameters. Usage: ${FUNCNAME[0]} --domain example.com --email admin@example.com [--san \"www.example.com,sub.example.com\"] [--challenge http] [--provider \"https://acme-v02.api.letsencrypt.org/directory\"]"
    exit 1
  fi

  # Check if Certbot and python3-certbot-apache are installed
  package_ensure certbot python3-certbot-apache

  # Prepare SAN entries
  local san_flag=""
  if [ -n "$san_entries" ]; then
    san_flag="--expand --cert-name $domain"
  fi

  # Request SSL certificate
  run_command certbot --apache -d "${domain}" "${san_flag}" -m "${email}" --agree-tos --"${challenge_type}"-challenge --server "${provider}"
}

function apache_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if Apache is installed
  if check_command "$APACHE_NAME"; then
    log verbose "Apache is installed."
    run_command apache2ctl -v # Use apache2ctl to get the version
  else
    log verbose "Apache is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi

  # Check for loaded modules using apache2ctl
  log verbose "Checking for loaded Apache modules:"
  run_command apache2ctl -M

  # Check Apache configuration for syntax errors
  log verbose "Checking Apache configuration for syntax errors:"
  run_command apache2ctl configtest
}

# Function to ensure Apache web server is installed and configured
function apache_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Check if PHP is installed
  # and exit if not
  php_verify --exit-on-failure

  # Verify if Apache is already installed
  # Do not exit if not installed
  apache_verify

  service_command="systemctl"

  # Install Apache and necessary modules for non-macOS systems
  package_ensure "${APACHE_NAME}"
  package_ensure libapache2-mod-headers
  package_ensure libapache2-mod-deflate
  package_ensure libapache2-mod-expires

  # Enable essential Apache modules
  run_command --makes-changes a2enmod ssl
  run_command --makes-changes a2enmod headers
  run_command --makes-changes a2enmod rewrite
  run_command --makes-changes a2enmod deflate
  run_command --makes-changes a2enmod expires

  if $FPM_ENSURE; then
    log verbose "Installing PHP FPM for non-macOS systems..."
    package_ensure "php${PHP_VERSION}-fpm"
    package_ensure "libapache2-mod-fcgid"

    log verbose "Configuring Apache for FPM..."
    run_command --makes-changes a2enmod proxy_fcgi setenvif
    run_command --makes-changes a2enconf "php${PHP_VERSION}-fpm"

    # Enable and start PHP FPM service
    run_command --makes-changes $service_command enable "php${PHP_VERSION}-fpm"
    run_command --makes-changes $service_command start "php${PHP_VERSION}-fpm"
  else
    log verbose "Configuring Apache without FPM..."
    package_ensure "libapache2-mod-php${PHP_VERSION}"
  fi

  run_command --makes-changes $service_command enable "${APACHE_NAME}"
  run_command --makes-changes $service_command restart "${APACHE_NAME}"

  log verbose "Apache installation and configuration completed."
}

function apache_create_vhost() {
  log verbose "Entered function ${FUNCNAME[0]}"

  apache_verify --exit-on-failure

  declare -n config=$1
  local logDir="${APACHE_LOG_DIR:-/var/log/apache2}"

  # Check if required configuration options are provided
  local required_options=("site-name" "document-root" "admin-email" "ssl-cert-file" "ssl-key-file")
  for option in "${required_options[@]}"; do
    if [[ -z "${config[$option]}" ]]; then
      log error "Missing required configuration option: $option"
      exit 1
    fi
  done

  local vhost_template="
<VirtualHost *:80>
    ServerName {{site_name}}
    Redirect / https://{{site_name}}/
</VirtualHost>

<IfModule mod_ssl.c>
<VirtualHost *:443>
    ServerAdmin {{admin_email}}
    DocumentRoot {{document_root}}
    ServerName {{site_name}}
    ErrorLog ${logDir}/error.log
    CustomLog ${logDir}/access.log combined
    SSLCertificateFile {{ssl_cert_file}}
    SSLCertificateKeyFile {{ssl_key_file}}
    {{include_file}}
</VirtualHost>
</IfModule>
"

  local vhost_config
  vhost_config=$(
    apply_template "$vhost_template" \
      "site_name=${config["site-name"]}" \
      "document_root=${config["document-root"]}" \
      "admin_email=${config["admin-email"]}" \
      "ssl_cert_file=${config["ssl-cert-file"]}" \
      "ssl_key_file=${config["ssl-key-file"]}" \
      "include_file=${config["include-file"]:+Include ${config["include-file"]}}"
  )

  echo "$vhost_config" >"/etc/apache2/sites-available/${config["site-name"]}.conf"
  run_command --makes-changes a2ensite "${config["site-name"]}"
}

function moodle_dependencies() {
  # From https://github.com/moodlehq/moodle-php-apache/blob/master/root/tmp/setup/php-extensions.sh
  log verbose "Entered function ${FUNCNAME[0]}"
  declare -a runtime=("ghostscript"
    "libaio1"
    "libcurl4"
    "libgss3"
    "libicu72"
    "libmcrypt-dev"
    "libxml2"
    "libxslt1.1"
    "libzip-dev"
    "sassc"
    "unzip"
    "zip")

  package_ensure "${runtime[@]}"

  if [ "${DB_TYPE}" == "pgsql" ]; then
    # Add php-pgsql extension for PostgreSQL
    declare -a database=("libpq5")
  else
    # Add php-mysqli extension for MySQL and MariaDB
    # Note php-mysql is deprecated in PHP 7.0 and removed in PHP 7.2
    # Note we are not supporting all the different database types that Moodle supports
    declare -a database=("libmariadb3")
  fi

  package_ensure "${database[@]}"
}

function moodle_config_files() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local configDir="${1}"
  local configDist="${configDir}/config-dist.php"
  configFile="${configDir}/config.php"

  if [ -f "${configDist}" ]; then
    if [ -f "${configFile}" ]; then
      log verbose "${configFile} already exists. Skipping configuration setup."
    else
      # Copy config-dist.php to config.php
      run_command --makes-changes cp "${configDist}" "${configFile}"
      log verbose "${configFile} copied from ${configDist}."
    fi
    log verbose "Setting up database configuration in ${configFile}..."
    # Modify values in config.php using sed (if config.php was copied)
    if [ -f "${configFile}" ]; then

      replace_file_value "\$CFG->dbtype\s*=\s*'pgsql';" "\$CFG->dbtype = '${DB_TYPE}';" "$configFile"
      replace_file_value "\$CFG->dbhost\s*=\s*'localhost';" "\$CFG->dbhost = '${DB_HOST}';" "$configFile"
      replace_file_value "\$CFG->dbname\s*=\s*'moodle';" "\$CFG->dbname = '${DB_NAME}';" "$configFile"
      replace_file_value "\$CFG->dbuser\s*=\s*'username';" "\$CFG->dbuser = '${DB_USER}';" "$configFile"
      replace_file_value "\$CFG->dbpass\s*=\s*'password';" "\$CFG->dbpass = '${DB_PASS}';" "$configFile"
      replace_file_value "\$CFG->prefix\s*=\s*'mdl_';" "\$CFG->prefix = '${DB_PREFIX}';" "$configFile"
      replace_file_value "\$CFG->wwwroot.*" "\$CFG->wwwroot   = 'https://${moodleSiteName}';" "$configFile"
      replace_file_value "\$CFG->dataroot.*" "\$CFG->dataroot  = '${moodleDataDir}';" "$configFile"

      log verbose "Configuration file changes completed."
    fi
  else
    log error "Error: ${configDist} does not exist."
    if [ "${DRY_RUN_CHANGES}" != "true" ]; then
      exit 1
    fi
  fi
}

function moodle_configure_directories() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local moodleUser="${1}"
  local webserverUser="${2}"
  local moodleDataDir="${3}"
  local moodleDir="${4}"

  log verbose "Entered function ${FUNCNAME[0]}"
  # Add moodle user for moodledata / Change ownerships and permissions
  run_command --makes-changes adduser --system "${moodleUser}"
  run_command --makes-changes mkdir -p "${moodleDataDir}"
  run_command --makes-changes chown -R "${webserverUser}:${webserverUser}" "${moodleDataDir}"
  run_command --makes-changes chmod 0777 "${moodleDataDir}"
  run_command --makes-changes mkdir -p "${moodleDir}"
  run_command --makes-changes chown -R root:"${webserverUser}" "${moodleDir}"
  run_command --makes-changes chmod -R 0755 "${moodleDir}"
}

function moodle_download_extract() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"
  local webserverUser="${2}"
  local moodleVersion="${3}"
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz"

  # Check if Moodle directory already exists
  if [ -d "${moodleDir}" ]; then
    log verbose "Moodle directory ${moodleDir} already exists. Skipping download and extraction."
    return
  fi

  # Check if local download already exists
  if [ -f "moodle-latest-${moodleVersion}.tgz" ]; then
    log verbose "Local Moodle archive moodle-latest-${moodleVersion}.tgz already exists. Skipping download."
  else
    # Download Moodle
    log verbose "Downloading ${moodleArchive}"
    # Use -O to not overwrite existing file
    run_command --makes-changes wget -O "moodle-latest-${moodleVersion}.tgz" "${moodleArchive}"

  fi

  # Check if Moodle archive has been extracted
  if [ -d "${moodleDir}/lib" ]; then
    log verbose "Moodle archive has already been extracted. Skipping extraction."
  else
    # Extract Moodle
    log verbose "Extracting ${moodleArchive}"
    run_command --makes-changes mkdir -p "${moodleDir}"
    run_command --makes-changes tar zx -C "${moodleDir}" --strip-components 1 -f "moodle-latest-${moodleVersion}.tgz"
    run_command --makes-changes chown -R root:"${webserverUser}" "${moodleDir}"
    run_command --makes-changes chmod -R 0755 "${moodleDir}"
  fi
}

function moodle_ensure() {

  php_verify --exit-on-failure
  # Alphabetised version of the list from https://docs.moodle.org/310/en/PHP
  ## The ctype extension is required (provided by common)
  # The curl extension is required (required for networking and web services).
  ## The dom extension is required (provided by xml)
  # The gd extension is recommended (required for manipulating images).
  ## The iconv extension is required (provided by common)
  # The intl extension is recommended.
  # The json extension is required.
  # The mbstring extension is required.
  # The openssl extension is recommended (required for networking and web services).
  ## To use PHP's OpenSSL support you must also compile PHP --with-openssl[=DIR].
  # The pcre extension is required (The PCRE extension is a core PHP extension, so it is always enabled)
  ## The SimpleXML extension is required (provided by xml)
  # The soap extension is recommended (required for web services).
  ## The SPL extension is required (provided by core)
  ## The tokenizer extension is recommended (provided by core)
  # The xml extension is required.
  # The xmlrpc extension is recommended (required for networking and web services).
  # The zip extension is required.

  declare -a moodle_php_extensions=("php${PHP_VERSION}-common"
    "php${PHP_VERSION}-curl"
    "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-intl"
    "php${PHP_VERSION}-json"
    "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-soap"
    "php${PHP_VERSION}-xml"
    "php${PHP_VERSION}-xmlrpc"
    "php${PHP_VERSION}-zip")

  if [ "${DB_TYPE}" == "pgsql" ]; then
    # Add php-pgsql extension for PostgreSQL
    moodle_php_extensions+=("php${PHP_VERSION}-pgsql")
  else
    # Add php-mysqli extension for MySQL and MariaDB
    moodle_php_extensions+=("php${PHP_VERSION}-mysqli")
  fi

  php_extensions_ensure "${moodle_php_extensions[@]}"

  moodle_configure_directories "${moodleUser}" "${webserverUser}" "${moodleDataDir}" "${moodleDir}"
  moodle_download_extract "${moodleDir}" "${webserverUser}" "${MOODLE_VERSION}"
  moodle_dependencies
  moodle_config_files "${moodleDir}"
  provider=$(acme_cert_provider "staging")
  acme_cert_request --domain "${moodleSiteName}" --email "admin@example.com" --challenge "http" --provider "${provider}"

  declare -A vhost_config=(
    ["site-name"]="${moodleSiteName}"
    ["document-root"]="/var/www/html/${moodleSiteName}"
    ["admin-email"]="admin@${moodleSiteName}"
    ["ssl-cert-file"]="/etc/letsencrypt/live/${moodleSiteName}/fullchain.pem"
    ["ssl-key-file"]="/etc/letsencrypt/live/${moodleSiteName}/privkey.pem"
  )

  if $APACHE_ENSURE; then
    apache_verify --exit-on-failure
    apache_create_vhost vhost_config
  fi

  if $NGINX_ENSURE; then
    nginx_verify --exit-on-failure
    nginx_create_vhost vhost_config
  fi
}

function nginx_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if Nginx is installed
  if check_command "nginx"; then
    log verbose "Nginx is installed."
    run_command nginx -v

    # Display installed Nginx modules
    log verbose "Installed Nginx modules:"
    run_command nginx -V 2>&1 | grep --color=never -o -- '-\S\+' # Filter out the modules

    # Check if the Nginx configuration has errors
    log verbose "Checking Nginx configuration for errors:"
    if ! run_command nginx -t; then
      log error "Nginx configuration has errors!"
      if [[ "$exit_on_failure" == true ]]; then
        exit 1
      fi
    else
      log verbose "Nginx configuration is okay."
    fi

  else
    log verbose "Nginx is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi
}

function nginx_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  nginx_verify

  # Install Nginx if not already installed
  package_ensure nginx

  # Should always be true, but just in case
  if $FPM_ENSURE; then
    log verbose "Installing PHP FPM for Nginx..."
    package_ensure "php${PHP_VERSION}-fpm"
  fi

  # Enable and start PHP FPM
  run_command --makes-changes systemctl enable "php${PHP_VERSION}-fpm"
  run_command --makes-changes systemctl start "php${PHP_VERSION}-fpm"

  # Enable and restart Nginx
  run_command --makes-changes systemctl enable nginx
  run_command --makes-changes systemctl restart nginx

  log verbose "Nginx installation and configuration completed."
}

function nginx_create_vhost() {
  log verbose "Entered function ${FUNCNAME[0]}"

  nginx_verify --exit-on-failure

  declare -n config=$1
  local logDir="${NGINX_LOG_DIR:-/var/log/nginx}"

  # Check if required configuration options are provided
  local required_options=("site-name" "document-root" "admin-email" "ssl-cert-file" "ssl-key-file")
  for option in "${required_options[@]}"; do
    if [[ -z "${config[$option]}" ]]; then
      log error "Missing required configuration option: $option"
      exit 1
    fi
  done

  local vhost_template="
server {
    listen 80;
    server_name {{site_name}};
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name {{site_name}};

    root {{document_root}};
    index index.php;

    server_tokens off;
    ssl_certificate {{ssl_cert_file}};
    ssl_certificate_key {{ssl_key_file}};

    error_log ${logDir}/{{site_name}}.error.log;
    access_log ${logDir}/{{site_name}}.access.log;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }

    {{include_file}}
}
"

  local vhost_config
  vhost_config=$(
    apply_template "$vhost_template" \
      "site_name=${config["site-name"]}" \
      "document_root=${config["document-root"]}" \
      "admin_email=${config["admin-email"]}" \
      "ssl_cert_file=${config["ssl-cert-file"]}" \
      "ssl_key_file=${config["ssl-key-file"]}" \
      "include_file=${config["include-file"]}"
  )

  echo "$vhost_config" >"/etc/nginx/sites-available/${config["site-name"]}.conf"
  run_command --makes-changes ln -s "/etc/nginx/sites-available/${config["site-name"]}.conf" "/etc/nginx/sites-enabled/"
  run_command --makes-changes systemctl reload nginx
}

function php_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if PHP is installed
  if check_command "php"; then
    log verbose "PHP is installed."
    run_command php -v
  else
    log verbose "PHP is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi
}

function php_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Verify if PHP is already installed
  php_verify

  # If PHP is already installed, simply return
  if check_command "php"; then
    return 0
  fi

  log verbose "Ensuring PHP repository..."

  if [ "$DISTRO" == "Ubuntu" ]; then
    php_repository="ppa:ondrej/php"
  elif [ "$DISTRO" == "Debian" ]; then
    php_repository="deb https://packages.sury.org/php/ $CODENAME main"
  else
    log error "Unsupported distro: $DISTRO"
    exit 1
  fi

  if [ "$package_manager" == "apt" ]; then
    repository_ensure "$php_repository"
  fi

  log verbose "Installing PHP core..."

  if [ "$DISTRO" == "Ubuntu" ]; then
    php_package="php${PHP_VERSION}-${CODENAME}"
  elif [ "$DISTRO" == "Debian" ]; then
    php_package="php${PHP_VERSION}-${CODENAME}"
  else
    log error "Unsupported distro: $DISTRO"
    exit 1
  fi

  package_install "$php_package"

  # Verify PHP installation at end of function
  php_verify --exit-on-failure
}

function php_extensions_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  php_verify --exit-on-failure
  local extensions=("$@")

  if [ ${#extensions[@]} -eq 0 ]; then
    log error "No PHP extensions provided. Aborting."
    exit 1
  fi

  package_ensure "${extensions[@]}"
}

# Main function
function main() {

  log verbose "Entered function ${FUNCNAME[0]}"

  package_manager_ensure

  log verbose "checking PHP_ENSURE"
  if $PHP_ENSURE; then
    log verbose "Ensuring PHP..."
    php_ensure
  fi

  log verbose "checking APACHE_ENSURE"
  if $APACHE_ENSURE; then
    log verbose "Ensuring Apache..."
    apache_ensure
  fi

  log verbose "checking NGINX_ENSURE"
  if $NGINX_ENSURE; then
    log verbose "Ensuring Nginx..."
    nginx_ensure
  fi

  log verbose "checking MEMCACHED_ENSURE"
  if $MOODLE_ENSURE; then
    log verbose "Ensuring Moodle..."
    moodle_ensure
  fi

}

# Define a function to detect the distribution and codename
function detect_distro_and_codename() {
  if command -v lsb_release &>/dev/null; then
    DISTRO="$(lsb_release -is)"
    CODENAME="$(lsb_release -sc)"
  elif [[ -f /etc/os-release ]]; then
    # Load values from /etc/os-release
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO="$ID"
    CODENAME="$VERSION_CODENAME"
  else
    log error "Unable to determine distribution."
    log error "Please run this script on a supported distribution."
    log error "Supported distributions are: Ubuntu, Debian."
    exit 1
  fi
}

# Script evaluation starts here

log_init

# detect_distro_and_codename

# Check if the necessary dependencies are available before proceeding
check_command --exit-on-failure tar unzip wget

# Parse command line options
if [[ $# -eq 0 ]]; then
  echo_usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -v | --verbose)
    LOG_LEVEL="verbose"
    shift
    ;;

  -c | --ci)
    CI_MODE=true
    shift
    ;;

  -d | --database)
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      case "$2" in
      mysql | pgsql)
        DB_TYPE="$2"
        shift # past value
        ;;
      *)
        log error "Unsupported database type: $2. Supported types are 'mysql' and 'pgsql'."
        echo_usage
        exit 1
        ;;
      esac
    else
      # Use the default value for DB_TYPE
      DB_TYPE="mysqli"
    fi
    shift # past argument
    ;;

  -f | --fpm)
    FPM_ENSURE=true
    shift
    ;;

  -h | --help)
    echo_usage
    exit 0
    ;;

  -M | --memcached)
    MEMCACHED_ENSURE=true
    if [[ -z "${2:-}" ]] || [[ "${2:-}" == "-"* ]]; then
      MEMCACHED_MODE="network"
    else
      case "$2" in
      local)
        MEMCACHED_MODE="local"
        ;;
      network)
        MEMCACHED_MODE="network"
        ;;
      *)
        log error "Invalid mode for Memcached: $2. Supported modes are 'local' and 'network'."
        exit 1
        ;;
      esac
      shift
    fi
    shift
    ;;

  -m | --moodle)
    MOODLE_ENSURE=true
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      MOODLE_VERSION="$2"
      shift # past value
    else
      MOODLE_VERSION="$DEFAULT_MOODLE_VERSION"
    fi
    shift # past argument
    ;;

  -n | --nop)
    DRY_RUN_CHANGES=true
    shift
    ;;

  -p | --php)
    PHP_ENSURE=true
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      PHP_VERSION="$2"
      shift # past value
    else
      PHP_VERSION="$DEFAULT_PHP_VERSION"
    fi
    shift # past argument
    ;;

  -s | --sudo)
    USE_SUDO=true
    shift
    ;;

  -w | --web)
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      case "$2" in
      apache)
        APACHE_ENSURE=true
        NGINX_ENSURE=false
        ;;
      nginx)
        APACHE_ENSURE=false
        NGINX_ENSURE=true
        FPM_ENSURE=true
        ;;
      *)
        log error "Unsupported web server type: $2. Supported types are 'apache' and 'nginx'."
        exit 1
        ;;
      esac
      shift 2
    else
      # Use the default web server (Apache)
      APACHE_ENSURE=true
      NGINX_ENSURE=false
      shift
    fi
    ;;

  *)
    log error "Unknown option: $1"
    echo_usage
    exit 1
    ;;
  esac
done

check_log_level
# check_log_level includes an verbose log message with the log level
# echo all opts which were set
log info "DRY_RUN_CHANGES: $DRY_RUN_CHANGES"

# If not in CI mode, do the sudo checks
if ! $CI_MODE; then
  log verbose "CI_MODE is false"
  # Check if user is root
  if [[ $EUID -eq 0 ]]; then
    USE_SUDO=false
    log verbose "Running as root."
  else
    # Check if sudo is available and the user has sudo privileges
    if $USE_SUDO && ! command -v sudo &>/dev/null; then
      log error "sudo command not found. Please run as root or install sudo."
      exit 1
    elif $USE_SUDO && ! sudo -n true 2>/dev/null; then
      log error "This script requires sudo privileges. Please run as root or with a user that has sudo privileges."
      exit 1
    fi
  fi
else
  log verbose "CI_MODE is true"
  # In CI mode, use sudo if not root
  if [[ $EUID -ne 0 ]]; then
    USE_SUDO=true
    log verbose "Running as non-root user."
  else
    USE_SUDO=false
    log verbose "Running as root."
  fi
fi

# Checking if -f is selected on its own without -w apache
if [[ "${FPM_ENSURE}" == "true" && "${APACHE_ENSURE}" != "true" && "${NGINX_ENSURE}" != "true" ]]; then
  log error "Option -f requires either -w apache or -w nginx to be selected."
  echo_usage
  exit 1
fi

if [[ "${LOG_LEVEL}" == "verbose" ]]; then
  chosen_options=""

  if $CI_MODE; then chosen_options+="-c: CI mode, "; fi
  if [[ -n "${DB_TYPE}" ]]; then chosen_options+="-d: Database type set to ${DB_TYPE}, "; fi
  if $FPM_ENSURE; then chosen_options+="-f: Ensure FPM for web servers, "; fi
  if $MOODLE_ENSURE; then chosen_options+="-m: Ensure Moodle version $MOODLE_VERSION, "; fi
  if $MEMCACHED_ENSURE; then
    chosen_options+="-M: Ensure Memcached support, "
    if [[ "$MEMCACHED_MODE" == "local" ]]; then
      chosen_options+="Ensure local Memcached instance, "
    fi
  fi
  if $DRY_RUN_CHANGES; then chosen_options+="-n: DRY RUN CHANGES, "; fi
  if $PHP_ENSURE; then chosen_options+="-p: Ensure PHP version $PHP_VERSION, "; fi
  if $USE_SUDO; then chosen_options+="-s: Use sudo, "; fi
  if [[ "${LOG_LEVEL}" == "verbose" ]]; then chosen_options+="-v: Verbose output, "; fi
  if $APACHE_ENSURE; then chosen_options+="-w: Webserver type set to Apache, "; fi
  if $NGINX_ENSURE; then chosen_options+="-w: Webserver type set to Nginx, "; fi
  chosen_options="${chosen_options%, }"

  log verbose "Chosen options: ${chosen_options}"
fi

# Run the main function
main

## Still to do
# Add option for memcached support
# Add option to install mysql locally
# Add option to install moodle with git rather than download

# [2023-08-13T09:07:03+0000]: VERBOSE: Preparing to execute: sudo certbot --apache -d moodle.romn.co -m admin@example.com --agree-tos --http-challenge --server https://acme-staging-v02.api.letsencrypt.org/directory
# usage:
#   certbot [SUBCOMMAND] [options] [-d DOMAIN] [-d DOMAIN] ...

# Certbot can obtain and install HTTPS/TLS/SSL certificates.  By default,
# it will attempt to use a webserver both for obtaining and installing the
# certificate.
# certbot: error: unrecognized arguments: --http-challenge
