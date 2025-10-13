#!/usr/bin/env bash
# shellcheck disable=SC2289
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
PROMETHEUS_ENSURE=false
MYSQL_ENSURE=false
POSTGRES_ENSURE=false
# Moodle version format: 405 for 4.5, 500 for 5.0.0, 501 for 5.1.0, 5003 for 5.0.3, etc.
DEFAULT_MOODLE_VERSION="501"
DEFAULT_PHP_VERSION_MAJOR_MINOR="8.4"
MOODLE_VERSION="${DEFAULT_MOODLE_VERSION}"
PHP_VERSION_MAJOR_MINOR="${DEFAULT_PHP_VERSION_MAJOR_MINOR}"
PHP_ALONGSIDE=false
APACHE_NAME="apache2" # Change to "httpd" for CentOS
ACME_CERT=false
ACME_PROVIDER="staging"
SELF_SIGNED_CERT=false
SERVICE_COMMAND="service" # Change to "systemctl" for CentOS

# Moodle database
DB_TYPE="mysql"
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

# helper functions

function echo_usage() {
  log info "Usage: $0 [options]"
  log info "Options:"
  log info "  -a, --acme-cert     Request an ACME certificate for the specified domain"
  log info "  -c, --ci            Run in CI mode (no prompts)"
  log info "  -d, --database      Database type (default: mysql, supported: [mysql, pgsql])"
  log info "  -f, --fpm           Enable FPM for the web server (requires -w apache (-w nginx sets fpm by default))"
  log info "  -h, --help          Display this help message"
  log info "  -m, --moodle        Ensure Moodle of specified version is installed (default: ${MOODLE_VERSION}, e.g., 405 for 4.5, 500 for 5.0.0, 501 for 5.1.0)"
  log info "  -M, --memcached     Ensure Memcached is installed"
  log info "  -n, --nop           Dry run (show commands without executing)"
  log info "  -p, --php           Ensure PHP is installed. If not, install specified version (default: ${PHP_VERSION_MAJOR_MINOR})"
  log info "  -P, --php-alongside Ensure specified version of PHP is installed, regardless of whether PHP is already installed"
  log info "  -r, --prometheus    Install Prometheus monitoring with exporters for web server and PHP"
  log info "  -s, --sudo          Use sudo for running commands (default: false)"
  log info "  -S, --self-signed   Create a self-signed certificate for the specified domain"
  log info "  -v, --verbose       Enable verbose output"
  log info "  -w, --web           Web server type (default: nginx, supported: [apache, nginx])"
  log info "  Note:               Options -d, -m, -p, -w require an argument but have defaults."
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

# Check if a single tool exists
tool_exists() {
  log debug "Entered function: ${FUNCNAME[0]}"
  local name=$1

  log debug "Checking if tool ${name} exists"
  if ! type -P "${name}" &>/dev/null; then
    log debug "Exited function: ${FUNCNAME[0]}"
    return 1
  fi

  log debug "Exited function: ${FUNCNAME[0]}"
  return 0
}

# Service management wrapper that works in containers and traditional servers
# Usage: service_manage <service_name> <action>
# Actions: start, stop, restart, reload, enable, is-active
service_manage() {
  local service_name="$1"
  local action="$2"

  log debug "Managing service $service_name with action $action"

  # Check if systemctl is available and systemd is running
  if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
    log debug "Using systemctl for service management"
    case "$action" in
      is-active)
        systemctl is-active --quiet "$service_name"
        ;;
      *)
        systemctl "$action" "$service_name"
        ;;
    esac
  # Fall back to /etc/init.d/ scripts (works in containers without systemd)
  elif [ -f "/etc/init.d/$service_name" ]; then
    log debug "Using /etc/init.d/ for service management"
    case "$action" in
      enable)
        # Init scripts don't have enable, skip or use update-rc.d
        if command -v update-rc.d >/dev/null 2>&1; then
          update-rc.d "$service_name" defaults || { log verbose "Service $service_name enable failed"; return 0; }
        else
          log verbose "Skipping 'enable' for $service_name (init.d doesn't support it)"
        fi
        ;;
      is-active)
        /etc/init.d/"$service_name" status >/dev/null 2>&1 || { log verbose "Service $service_name is not active"; return 0; }
        ;;
      *)
        /etc/init.d/"$service_name" "$action" || { log verbose "Service $service_name $action failed (container environment)"; return 0; }
        ;;
    esac
  # Try service command as last resort
  elif command -v service >/dev/null 2>&1; then
    log debug "Using service command for service management"
    case "$action" in
      enable)
        log verbose "Skipping 'enable' for $service_name (service command doesn't support it)"
        ;;
      is-active)
        service "$service_name" status >/dev/null 2>&1 || { log verbose "Service $service_name is not active"; return 0; }
        ;;
      *)
        service "$service_name" "$action" || { log verbose "Service $service_name $action failed (container environment)"; return 0; }
        ;;
    esac
  else
    log verbose "Cannot manage service $service_name - no service manager available (container environment)"
    return 0
  fi
}

function package_manager_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  if tool_exists apt; then
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
        # Check if this is a PPA (Ubuntu format) or a deb line (Debian format)
        if [[ "$repository" =~ ^ppa: ]]; then
          # Ubuntu PPA format - requires add-apt-repository
          if ! command -v add-apt-repository >/dev/null 2>&1; then
            log error "add-apt-repository not found. Install software-properties-common first."
            exit 1
          fi
          run_command --makes-changes add-apt-repository -y "$repository"
        elif [[ "$repository" =~ ^deb ]]; then
          # Debian deb line format - write directly to sources.list.d
          local repo_name
          repo_name=$(echo "$repository" | sed 's|https://||;s|http://||;s|/| |g' | awk '{print $1}' | tr '.' '-')
          local sources_file="/etc/apt/sources.list.d/${repo_name}.list"
          log verbose "Writing repository to $sources_file"
          run_command --makes-changes bash -c "echo '$repository' > $sources_file"

          # Add GPG key if needed (for sury repositories)
          if [[ "$repository" =~ packages\.sury\.org ]]; then
            log verbose "Adding Sury GPG key..."
            run_command --makes-changes curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury-php-keyring.gpg
            # Update sources.list.d entry to reference the keyring
            run_command --makes-changes bash -c "sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/sury-php-keyring.gpg] |' $sources_file"
          fi
        else
          log error "Unknown repository format: $repository"
          exit 1
        fi
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

function get_cert_path() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local domain=""
  local cert_type="cert"  # "cert" or "key"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --domain)
      shift
      domain="$1"
      shift
      ;;
    --type)
      shift
      cert_type="$1"
      shift
      ;;
    *)
      log error "Invalid option: $1"
      exit 1
      ;;
    esac
  done

  if [ -z "$domain" ]; then
    log error "Missing domain parameter. Usage: ${FUNCNAME[0]} --domain example.com [--type cert|key]"
    exit 1
  fi

  # Return certificate paths based on which flags are set
  if $ACME_CERT; then
    if [ "$cert_type" = "key" ]; then
      echo "/etc/letsencrypt/live/${domain}/privkey.pem"
    else
      echo "/etc/letsencrypt/live/${domain}/fullchain.pem"
    fi
  elif $SELF_SIGNED_CERT; then
    if [ "$cert_type" = "key" ]; then
      echo "/etc/ssl/${domain}.key"
    else
      echo "/etc/ssl/${domain}.cert"
    fi
  else
    log error "Neither ACME_CERT nor SELF_SIGNED_CERT is enabled. Cannot determine certificate path."
    exit 1
  fi
}

function validate_certificates() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local domain=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --domain)
      shift
      domain="$1"
      shift
      ;;
    *)
      log error "Invalid option: $1"
      exit 1
      ;;
    esac
  done

  if [ -z "$domain" ]; then
    log error "Missing domain parameter. Usage: ${FUNCNAME[0]} --domain example.com"
    exit 1
  fi

  # Get certificate paths
  local cert_file
  local key_file
  cert_file=$(get_cert_path --domain "${domain}" --type cert)
  key_file=$(get_cert_path --domain "${domain}" --type key)

  # Check if certificate files exist
  if [ ! -f "$cert_file" ]; then
    log error "Certificate file does not exist: ${cert_file}"
    return 1
  fi

  if [ ! -f "$key_file" ]; then
    log error "Key file does not exist: ${key_file}"
    return 1
  fi

  log verbose "Certificate validation successful for domain: ${domain}"
  log verbose "  Certificate: ${cert_file}"
  log verbose "  Key: ${key_file}"
  return 0
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

  if ! tool_exists certbot; then
    log info "Certbot is not installed."
    package_ensure certbot python3-certbot-apache
  fi

  # Prepare SAN entries
  local san_flag=""
  if [ -n "$san_entries" ]; then
    san_flag="--expand --cert-name $domain"
  fi

  # Request SSL certificate
  #ignore ShellCheck warning for $san_flag
  #shellcheck disable=SC2086
  run_command --makes-changes certbot --apache -d "${domain}" ${san_flag} -m "${email}" --agree-tos --non-interactive --preferred-challenges "${challenge_type}" --server "${provider}"
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
  if tool_exists apache2ctl; then
    log verbose "Apache is installed."
    run_command apache2ctl -v # Use apache2ctl to get the version
    # Check for loaded modules using apache2ctl
    log verbose "Checking for loaded Apache modules:"
    run_command apache2ctl -M

    # Check Apache configuration for syntax errors
    log verbose "Checking Apache configuration for syntax errors:"
    run_command apache2ctl configtest
  else
    log verbose "Apache is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi

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

  if [[ "$DRY_RUN_CHANGES" == "true" ]]; then
    log verbose "DRY_RUN: Skipping repository setup and Apache installation"
  else
    log verbose "Setting up Apache repository..."
    if [ "$DISTRO" == "Ubuntu" ]; then
      log verbose "Adding Ondrej Apache2 repository for Ubuntu..."
      apache_repository="ppa:ondrej/apache2"
    elif [ "$DISTRO" == "Debian" ]; then
      log verbose "Adding Sury Apache2 repository for Debian..."
      apache_repository="deb https://packages.sury.org/apache2/ $CODENAME main"
    else
      log error "Unsupported distro: $DISTRO"
      exit 1
    fi

    if [ "$package_manager" == "apt" ]; then
      log verbose "Ensuring repository is added $apache_repository..."
      repository_ensure "$apache_repository"
    fi

    # Install Apache and necessary modules for non-macOS systems
    package_ensure "${APACHE_NAME}"

    # Enable essential Apache modules
    run_command --makes-changes a2enmod ssl
    run_command --makes-changes a2enmod headers
    run_command --makes-changes a2enmod rewrite
    run_command --makes-changes a2enmod deflate
    run_command --makes-changes a2enmod expires

    if $FPM_ENSURE; then
      log verbose "Installing PHP FPM for non-macOS systems..."
      package_ensure "php${PHP_VERSION_MAJOR_MINOR}-fpm"
      package_ensure "libapache2-mod-fcgid"

      log verbose "Configuring Apache for FPM..."
      run_command --makes-changes a2enmod proxy_fcgi setenvif
      run_command --makes-changes a2enconf "php${PHP_VERSION_MAJOR_MINOR}-fpm"

      # Enable and start PHP FPM service
      run_command --makes-changes service_manage "php${PHP_VERSION_MAJOR_MINOR}-fpm" start
    else
      log verbose "Configuring Apache without FPM..."
      package_ensure "libapache2-mod-php${PHP_VERSION_MAJOR_MINOR}"
    fi

    run_command --makes-changes service_manage "${APACHE_NAME}" restart

    log verbose "Apache installation and configuration completed."
  fi
}

function apache_create_vhost() {
  apache_verify --exit-on-failure

  declare -n config=$1
  local logDir="${APACHE_LOG_DIR:-/var/log/apache2}"

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
    Redirect permanent / https://{{site_name}}/
</VirtualHost>

<VirtualHost *:443>
    ServerName {{site_name}}
    DocumentRoot {{document_root}}

    ErrorLog ${logDir}/{{site_name}}-error.log
    CustomLog ${logDir}/{{site_name}}-access.log combined

    SSLEngine on
    SSLCertificateFile {{ssl_cert_file}}
    SSLCertificateKeyFile {{ssl_key_file}}

    <Directory {{document_root}}>
        AllowOverride All
        Require all granted
    </Directory>

    {{fpm_config}}
    {{include_file}}
</VirtualHost>
"

  # Add FPM configuration if FPM is enabled
  local fpm_config=""
  if $FPM_ENSURE; then
    fpm_config="
    # PHP-FPM Configuration
    <FilesMatch \\.php$>
        SetHandler \"proxy:unix:/run/php/php${PHP_VERSION_MAJOR_MINOR}-${config["site-name"]}.sock|fcgi://localhost\"
    </FilesMatch>"
  fi

  local vhost_config
  vhost_config=$(
    apply_template "$vhost_template" \
      "site_name=${config["site-name"]}" \
      "document_root=${config["document-root"]}" \
      "admin_email=${config["admin-email"]}" \
      "ssl_cert_file=${config["ssl-cert-file"]}" \
      "ssl_key_file=${config["ssl-key-file"]}" \
      "fpm_config=${fpm_config}" \
      "include_file=${config["include-file"]}"
  )

  echo "$vhost_config" >"/etc/apache2/sites-available/${config["site-name"]}.conf"
  run_command --makes-changes a2ensite "${config["site-name"]}"
  run_command --makes-changes service_manage "${APACHE_NAME}" reload
}

function moodle_dependencies() {
  # From https://github.com/moodlehq/moodle-php-apache/blob/main/root/tmp/setup/php-extensions.sh
  # Ran into issues with libicu, and it's not listed in https://docs.moodle.org/403/en/PHP#Required_extensions
  log verbose "Entered function ${FUNCNAME[0]}"

  # Determine libaio package name (Debian 13+ uses libaio1t64, earlier versions use libaio1)
  local libaio_package="libaio1"
  if apt-cache search libaio1t64 | grep -q "libaio1t64"; then
    libaio_package="libaio1t64"
  fi

  declare -a runtime=("ghostscript"
    "${libaio_package}"
    "libcurl4"
    "libgss3"
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

function moodle_composer_install() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"

  # Check if Composer is installed
  if ! tool_exists composer; then
    log info "Installing Composer..."
    run_command --makes-changes curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
    run_command --makes-changes php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
    run_command --makes-changes rm /tmp/composer-setup.php
    log info "Composer installed successfully"
  else
    log verbose "Composer is already installed"
  fi

  # Install Moodle Composer dependencies
  log info "Installing Moodle Composer dependencies..."
  run_command --makes-changes bash -c "cd ${moodleDir} && composer install --no-dev --classmap-authoritative"
  log info "Composer dependencies installed successfully"
}

function moodle_config_files() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local configDir="${1}"
  local configDist="${configDir}/config-dist.php"
  configFile="${configDir}/config.php"

  # Check if Moodle is installed
  if [ ! -f "${configDist}" ]; then
    log error "Error: ${configDist} does not exist."
    log error "Moodle may not be installed at ${configDir}."
    exit 1
  fi

  if [ -f "${configDist}" ]; then
    if [ -f "${configFile}" ] && [ -s "${configFile}" ]; then
      # File exists and has content
      log verbose "${configFile} already exists with content. Skipping configuration setup."
    else
      # File doesn't exist or is empty, copy from template
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

      # Add X-Sendfile configuration for Nginx if using Nginx
      if $NGINX_ENSURE; then
        # Check if xsendfile settings already exist
        if ! grep -q "CFG->xsendfile" "$configFile"; then
          # Add before the require_once line at the end of the file
          sed -i "/require_once(__DIR__ . '\/lib\/setup.php');/i\
\n\
// X-Sendfile configuration for Nginx\n\
\$CFG->xsendfile = 'X-Accel-Redirect';\n\
\$CFG->xsendfilealiases = array(\n\
    '${moodleDataDir}/' => '/dataroot/'\n\
);\n" "$configFile"
          log verbose "Added X-Sendfile configuration for Nginx"
        fi
      fi

      # Add Memcached session configuration if Memcached is enabled
      if $MEMCACHED_ENSURE; then
        # Check if memcached session settings already exist
        if ! grep -q "CFG->session_handler_class" "$configFile"; then
          # Add before the require_once line at the end of the file
          sed -i "/require_once(__DIR__ . '\/lib\/setup.php');/i\
\n\
// Memcached session configuration\n\
\$CFG->session_handler_class = '\\\\\\\\core\\\\\\\\session\\\\\\\\memcached';\n\
\$CFG->session_memcached_save_path = '127.0.0.1:11211';\n\
\$CFG->session_memcached_prefix = 'memc.sess.key.';\n\
\$CFG->session_memcached_acquire_lock_timeout = 120;\n\
\$CFG->session_memcached_lock_expire = 7200;\n" "$configFile"
          log verbose "Added Memcached session configuration"
        fi
      fi

      log verbose "Configuration file changes completed."
    fi
  else
    log error "Error: ${configDist} does not exist."
    if [ "${DRY_RUN_CHANGES}" == "true" ]; then
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

  # Check if Moodle is already installed (check for config-dist.php which is in every Moodle installation)
  if [ -f "${moodleDir}/config-dist.php" ]; then
    log verbose "Moodle is already installed at ${moodleDir}. Skipping download and extraction."
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

function generate_password() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Generate a secure random password (20 characters with letters, numbers, and special characters)
  local password
  password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
  echo "${password}"
}

function moodle_install_database() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"

  # Check if Moodle is already installed by checking database schema
  log verbose "Checking if Moodle is already installed..."
  if run_command php "${moodleDir}/admin/cli/check_database_schema.php" 2>&1 | grep -q "No errors found"; then
    log verbose "Moodle is already installed. Skipping database installation."
    return 0
  fi

  # Generate secure admin password
  local admin_password
  admin_password=$(generate_password)

  log info "Installing Moodle database..."
  log verbose "Running Moodle CLI installer with the following settings:"
  log verbose "  Language: en"
  log verbose "  Admin user: admin"
  log verbose "  Admin email: admin@${moodleSiteName}"
  log verbose "  Full name: ${moodleSiteName}"
  log verbose "  Short name: ${moodleSiteName}"

  # Run Moodle CLI installer
  run_command --makes-changes php "${moodleDir}/admin/cli/install_database.php" \
    --lang=en \
    --adminuser=admin \
    --adminpass="${admin_password}" \
    --adminemail="admin@${moodleSiteName}" \
    --fullname="${moodleSiteName}" \
    --shortname="${moodleSiteName}" \
    --agree-license

  # Log the admin password
  log info "Moodle installation completed successfully!"
  log info "=========================================="
  log info "IMPORTANT: Save these credentials securely"
  log info "=========================================="
  log info "Admin username: admin"
  log info "Admin password: ${admin_password}"
  log info "Admin email: admin@${moodleSiteName}"
  log info "Site URL: https://${moodleSiteName}"
  log info "=========================================="
  log verbose "Admin password has been logged to: ${LOG_FILE}"
}

function setup_moodle_cron() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"

  # Create cron job for Moodle (runs every 5 minutes)
  local cron_job="*/5 * * * * php ${moodleDir}/admin/cli/cron.php"
  local cron_comment="# Moodle cron job"

  log verbose "Setting up Moodle cron job for ${webserverUser}..."

  # Check if cron job already exists in www-data's crontab
  if run_command crontab -u "${webserverUser}" -l 2>/dev/null | grep -q "${moodleDir}/admin/cli/cron.php"; then
    log verbose "Moodle cron job already exists for ${webserverUser}. Skipping cron setup."
    return 0
  fi

  # Add cron job to www-data's crontab
  log verbose "Adding Moodle cron job to ${webserverUser}'s crontab..."

  # Get existing crontab or create empty one if it doesn't exist
  local existing_crontab
  existing_crontab=$(run_command crontab -u "${webserverUser}" -l 2>/dev/null || echo "")

  # Add new cron job
  {
    echo "${existing_crontab}"
    echo "${cron_comment}"
    echo "${cron_job}"
  } | run_command --makes-changes crontab -u "${webserverUser}" -

  log verbose "Moodle cron job added successfully for ${webserverUser}"
}

# Alphabetised version of the list from https://docs.moodle.org/310/en/PHP
## The ctype extension is required (provided by common)
# The curl extension is required (required for networking and web services).
## The dom extension is required (provided by xml)
# The gd extension is recommended (required for manipulating images).
## The iconv extension is required (provided by common)
# The intl extension is recommended.
## The json extension is required (provided by libapache2-mod-php)
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

version_compare() {
  # Compare two version numbers (format: X.Y)
  # Returns 0 if $1 >= $2, returns 1 otherwise
  local ver1="$1"
  local ver2="$2"

  # Extract major and minor versions
  local ver1_major ver1_minor ver2_major ver2_minor
  ver1_major=$(echo "$ver1" | cut -d. -f1)
  ver1_minor=$(echo "$ver1" | cut -d. -f2)
  ver2_major=$(echo "$ver2" | cut -d. -f1)
  ver2_minor=$(echo "$ver2" | cut -d. -f2)

  # Compare major version
  if [ "$ver1_major" -gt "$ver2_major" ]; then
    return 0
  elif [ "$ver1_major" -lt "$ver2_major" ]; then
    return 1
  fi

  # Major versions equal, compare minor version
  if [ "$ver1_minor" -ge "$ver2_minor" ]; then
    return 0
  else
    return 1
  fi
}

function moodle_validate_php_version() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local moodle_version="$1"
  local php_version="$2"

  # Extract major.minor from PHP version
  local php_major_minor
  php_major_minor=$(echo "$php_version" | cut -d. -f1-2)

  # Moodle/PHP compatibility matrix (October 2025)
  # Reference: https://docs.moodle.org/en/PHP
  # Version format: 500=5.0.0, 501=5.1.0, 5003=5.0.3 (patch releases use 4 digits)
  case "$moodle_version" in
    "500" | "501" | "502" | "5003")
      # Moodle 5.0+ requires PHP 8.2+ (supports 8.2, 8.3, 8.4)
      # Moodle 5.1.0 (tag: MOODLE_501) released October 2025
      if ! version_compare "$php_major_minor" "8.2"; then
        log error "Moodle 5.0+ requires PHP 8.2 or higher (supports 8.2, 8.3, 8.4). Current: $php_version"
        exit 1
      fi
      ;;
    "404" | "405")
      # Moodle 4.4-4.5 requires PHP 8.1+ (supports 8.1, 8.2, 8.3)
      if ! version_compare "$php_major_minor" "8.1"; then
        log error "Moodle 4.4-4.5 requires PHP 8.1 or higher (supports 8.1, 8.2, 8.3). Current: $php_version"
        exit 1
      fi
      ;;
    "402" | "403")
      # Moodle 4.2-4.3 requires PHP 8.0+ (supports 8.0, 8.1, 8.2)
      if ! version_compare "$php_major_minor" "8.0"; then
        log error "Moodle 4.2-4.3 requires PHP 8.0 or higher (supports 8.0, 8.1, 8.2). Current: $php_version"
        exit 1
      fi
      ;;
    "401")
      # Moodle 4.1 requires PHP 7.4+ (supports 7.4, 8.0, 8.1)
      if ! version_compare "$php_major_minor" "7.4"; then
        log error "Moodle 4.1 requires PHP 7.4 or higher (supports 7.4, 8.0, 8.1). Current: $php_version"
        exit 1
      fi
      ;;
    "400")
      # Moodle 4.0 requires PHP 7.3+ (supports 7.3, 7.4, 8.0)
      if ! version_compare "$php_major_minor" "7.3"; then
        log error "Moodle 4.0 requires PHP 7.3 or higher (supports 7.3, 7.4, 8.0). Current: $php_version"
        exit 1
      fi
      ;;
    "311" | "312")
      # Moodle 3.11 requires PHP 7.3+ (supports 7.3, 7.4, 8.0)
      if ! version_compare "$php_major_minor" "7.3"; then
        log error "Moodle 3.11 requires PHP 7.3 or higher (supports 7.3, 7.4, 8.0). Current: $php_version"
        exit 1
      fi
      ;;
    *)
      log verbose "No specific PHP version requirements known for Moodle version $moodle_version"
      log verbose "Note: Default Moodle versions are 405 (4.5) and 500 (5.0)"
      ;;
  esac

  log verbose "PHP version $php_version is compatible with Moodle $moodle_version"
}

function moodle_ensure() {
  php_verify --exit-on-failure

  # Validate PHP version compatibility with Moodle
  local php_version
  php_version=$(php -v | head -n 1 | awk '{print $2}')
  moodle_validate_php_version "${MOODLE_VERSION}" "${php_version}"

  declare -a moodle_php_extensions=(
    "php${PHP_VERSION_MAJOR_MINOR}-common"
    "php${PHP_VERSION_MAJOR_MINOR}-curl"
    "php${PHP_VERSION_MAJOR_MINOR}-gd"
    "php${PHP_VERSION_MAJOR_MINOR}-intl"
    "php${PHP_VERSION_MAJOR_MINOR}-mbstring"
    "php${PHP_VERSION_MAJOR_MINOR}-soap"
    "php${PHP_VERSION_MAJOR_MINOR}-xml"
    "php${PHP_VERSION_MAJOR_MINOR}-xmlrpc"
    "php${PHP_VERSION_MAJOR_MINOR}-zip"
    "php${PHP_VERSION_MAJOR_MINOR}-opcache"
    "php${PHP_VERSION_MAJOR_MINOR}-ldap"
  )

  if [ "${DB_TYPE}" == "pgsql" ]; then
    moodle_php_extensions+=("php${PHP_VERSION_MAJOR_MINOR}-pgsql")
  else
    moodle_php_extensions+=("php${PHP_VERSION_MAJOR_MINOR}-mysqli")
  fi

  php_extensions_ensure "${moodle_php_extensions[@]}"

  # Configure PHP for Moodle requirements
  php_configure_for_moodle

  moodle_configure_directories "${moodleUser}" "${webserverUser}" "${moodleDataDir}" "${moodleDir}"
  moodle_download_extract "${moodleDir}" "${webserverUser}" "${MOODLE_VERSION}"
  moodle_dependencies
  moodle_composer_install "${moodleDir}"
  moodle_config_files "${moodleDir}"
  moodle_install_database "${moodleDir}"
  setup_moodle_cron "${moodleDir}"

  # Get dynamic certificate paths based on ACME_CERT or SELF_SIGNED_CERT flags
  local ssl_cert_file=""
  local ssl_key_file=""

  if $ACME_CERT || $SELF_SIGNED_CERT; then
    # Validate certificates exist before creating vhost
    if ! validate_certificates --domain "${moodleSiteName}"; then
      log error "Certificate validation failed. Please ensure certificates are created before configuring vhost."
      exit 1
    fi

    # Get certificate paths
    ssl_cert_file=$(get_cert_path --domain "${moodleSiteName}" --type cert)
    ssl_key_file=$(get_cert_path --domain "${moodleSiteName}" --type key)

    log verbose "Using SSL certificates:"
    log verbose "  Certificate: ${ssl_cert_file}"
    log verbose "  Key: ${ssl_key_file}"
  else
    log info "No SSL certificate flags set (ACME_CERT or SELF_SIGNED_CERT). Virtual host will be created without SSL."
    # Use empty paths for non-SSL configurations
    ssl_cert_file=""
    ssl_key_file=""
  fi

  declare -A vhost_config=(
    ["site-name"]="${moodleSiteName}"
    ["document-root"]="/var/www/html/${moodleSiteName}"
    ["admin-email"]="admin@${moodleSiteName}"
    ["ssl-cert-file"]="${ssl_cert_file}"
    ["ssl-key-file"]="${ssl_key_file}"
  )

  if $APACHE_ENSURE; then
    apache_verify --exit-on-failure
    # Create PHP-FPM pool for Moodle when using FPM
    if $FPM_ENSURE; then
      php_fpm_create_pool "${moodleSiteName}" "${webserverUser}"
    fi
    apache_create_vhost vhost_config
  fi

  if $NGINX_ENSURE; then
    nginx_verify --exit-on-failure
    # Create PHP-FPM pool for Moodle
    if $FPM_ENSURE; then
      php_fpm_create_pool "${moodleSiteName}" "${webserverUser}"
    fi
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
  if tool_exists "nginx"; then
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

function nginx_create_optimized_config() {
  log verbose "Creating optimized Nginx configuration"

  # Backup original nginx.conf if it exists
  if [ -f "/etc/nginx/nginx.conf" ]; then
    run_command --makes-changes cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup
  fi

  # Create optimized nginx.conf
  cat > /etc/nginx/nginx.conf << 'EOF'
# Optimized Nginx Configuration
# Based on best practices for performance and security

user www-data www-data;
worker_processes auto;
worker_rlimit_nofile 8192;
pid /var/run/nginx.pid;

events {
    worker_connections 8000;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 20s;
    types_hash_max_size 2048;
    client_max_body_size 100M;
    client_body_timeout 30s;
    client_header_timeout 30s;
    send_timeout 30s;

    # Buffer sizes for better performance
    fastcgi_buffers 16 16k;
    fastcgi_buffer_size 32k;

    # Hide nginx version
    server_tokens off;

    # MIME Types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log error;

    # Gzip Compression
    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        application/atom+xml
        application/geo+json
        application/javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rdf+xml
        application/rss+xml
        application/vnd.ms-fontobject
        application/wasm
        application/x-web-app-manifest+json
        application/xhtml+xml
        application/xml
        font/eot
        font/otf
        font/ttf
        image/svg+xml
        image/x-icon
        text/cache-manifest
        text/calendar
        text/css
        text/javascript
        text/markdown
        text/plain
        text/xml
        text/vcard
        text/vtt
        text/x-component
        text/x-cross-domain-policy;

    # SSL Settings (if using HTTPS)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES;
    ssl_ecdh_curve X25519:prime256v1:secp521r1:secp384r1;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 24h;
    ssl_session_tickets off;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # Include additional configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

  # Create global configuration directory
  run_command --makes-changes mkdir -p /etc/nginx/global

  # Create security configuration for uploads
  cat > /etc/nginx/global/uploads-protection.conf << 'EOF'
# Deny access to any files with a .php extension in uploads directories
location ~* /uploads/.*\.php$ {
    deny all;
    access_log off;
}

# Deny access to hidden files
location ~ /\. {
    deny all;
    access_log off;
    log_not_found off;
}
EOF

  # Create Moodle-specific security rules
  cat > /etc/nginx/global/moodle-security.conf << 'EOF'
# Moodle Security Configuration
#
# X-Sendfile Support:
# The /dataroot/ location allows Nginx to access and serve files from the moodledata
# directory (which is stored OUTSIDE the web root for security). This only works when:
# 1. Moodle's config.php has: $CFG->xsendfile = 'X-Accel-Redirect';
# 2. And: $CFG->xsendfilealiases = array('/path/to/moodledata/' => '/dataroot/');
#
# This way, files are secure (outside web root) but can still be efficiently served by Nginx.

# Protect Moodle internal files
location ~ (/vendor/|/node_modules/|composer\.json|/readme|/README|readme\.txt|/upgrade\.txt|/UPGRADING\.md|db/install\.xml|/fixtures/|/behat/|phpunit\.xml|\.lock|environment\.xml) {
    deny all;
    return 404;
}

# Moodle file serving with X-Sendfile
# This allows Nginx to serve files from moodledata directory (which is outside web root)
# when Moodle sends an X-Accel-Redirect header
#
# IMPORTANT: The moodledata directory MUST be outside the web root for security!
# This location block makes it accessible ONLY via internal redirects from PHP
location /dataroot/ {
    internal;  # Only accessible via internal redirects, not direct URLs
    alias ${moodle_data_dir}/;  # Maps to the actual moodledata directory

    # Ensure proper content type detection
    add_header Content-Disposition 'attachment';
}

# Disable xmlrpc.php for security
location = /xmlrpc.php {
    deny all;
    access_log off;
    log_not_found off;
    return 404;
}
EOF

  # Create static files caching configuration
  cat > /etc/nginx/global/static-files.conf << 'EOF'
# Cache static files
location ~* \.(jpg|jpeg|png|gif|ico|webp|svg|css|js|pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar|gz|bz2|7z)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# Cache fonts
location ~* \.(ttf|ttc|otf|eot|woff|woff2)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
    add_header Access-Control-Allow-Origin *;
}

# Don't log robots.txt or favicon.ico
location = /robots.txt {
    access_log off;
    log_not_found off;
}

location = /favicon.ico {
    access_log off;
    log_not_found off;
}
EOF

  log verbose "Optimized Nginx configuration created"
}

function nginx_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  nginx_verify

  if [[ "$DRY_RUN_CHANGES" == "true" ]]; then
    log verbose "DRY_RUN: Skipping repository setup and Nginx installation"
  else
    log verbose "Setting up Nginx repository..."

    # Use official nginx.org repository for both Ubuntu and Debian
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
      log verbose "Adding official nginx.org repository for ${DISTRO}..."

      # Download and add nginx.org GPG key
      log verbose "Adding nginx.org GPG key..."
      run_command --makes-changes bash -c "curl -fSsL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null"

      # Verify GPG key was added successfully
      if [ ! -f "/usr/share/keyrings/nginx-archive-keyring.gpg" ]; then
        log error "Failed to add nginx.org GPG key"
        exit 1
      fi

      # Add nginx mainline repository
      # Use lowercase distro name for nginx.org repository URLs
      log verbose "Adding nginx mainline repository..."
      local codename
      local distro_lower
      codename=$(lsb_release -cs)
      distro_lower=$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/${distro_lower} ${codename} nginx" | tee /etc/apt/sources.list.d/nginx.list >/dev/null

      # Set APT pinning to prioritize nginx.org packages
      log verbose "Configuring APT pinning for nginx.org..."
      echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx >/dev/null

      # Update package list to include new repository
      run_command --makes-changes apt-get update

    else
      log error "Unsupported distro: $DISTRO"
      exit 1
    fi
  fi

  # Install Nginx if not already installed
  package_ensure nginx

  # Create optimized Nginx configuration
  nginx_create_optimized_config "${moodleDataDir}"

  # Should always be true, but just in case
  if $FPM_ENSURE; then
    log verbose "Installing PHP FPM for Nginx..."
    package_ensure "php${PHP_VERSION_MAJOR_MINOR}-fpm"
  fi

  run_command --makes-changes service_manage "php${PHP_VERSION_MAJOR_MINOR}-fpm" start

  run_command --makes-changes service_manage nginx restart

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
    listen 443 ssl http2;
    server_name {{site_name}};

    root {{document_root}};
    index index.php index.html;

    # SSL Configuration
    ssl_certificate {{ssl_cert_file}};
    ssl_certificate_key {{ssl_key_file}};

    # Security Headers for HTTPS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Logging
    error_log ${logDir}/{{site_name}}.error.log;
    access_log ${logDir}/{{site_name}}.access.log;

    # Include global security configurations
    include /etc/nginx/global/uploads-protection.conf;
    include /etc/nginx/global/moodle-security.conf;
    include /etc/nginx/global/static-files.conf;

    # Main location block
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # PHP handling
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        if (!-f \$document_root\$fastcgi_script_name) {
            return 404;
        }

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param PATH_TRANSLATED \$document_root\$fastcgi_path_info;

        fastcgi_pass unix:/run/php/php${PHP_VERSION_MAJOR_MINOR}-{{site_name}}.sock;
        fastcgi_index index.php;

        # Performance optimizations
        fastcgi_buffer_size 128k;
        fastcgi_buffers 256 16k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_read_timeout 300;
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
  run_command --makes-changes service_manage nginx reload
}

php_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  log verbose "PHP_ALONGSIDE: ${PHP_ALONGSIDE}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if PHP is installed
  if tool_exists "php"; then
    log verbose "PHP is installed."
    local php_version
    php_version=$(php -v | head -n 1 | awk '{print $2}')
    log verbose "PHP version: $php_version"

    # Extract the MAJOR.MINOR version from the installed PHP version
    local installed_version
    installed_version=$(echo "$php_version" | cut -d. -f1-2)

    if [[ "${PHP_ALONGSIDE:-false}" == "false" ]]; then
      log verbose "Using the -p flag, we are only concerned that PHP is installed, and not the specific version."
      return 0
    else
      # Compare the MAJOR.MINOR versions
      if [[ "$installed_version" == "$PHP_VERSION_MAJOR_MINOR" ]]; then
        log verbose "Installed PHP version $installed_version matches the specified version $PHP_VERSION_MAJOR_MINOR."
        return 0
      else
        log verbose "Installed PHP version $installed_version does not match the specified version $PHP_VERSION_MAJOR_MINOR."
        if [[ "$exit_on_failure" == true ]]; then
          log error "PHP version mismatch. Expected: $PHP_VERSION_MAJOR_MINOR, Installed: $installed_version"
          exit 1
        else
          log info "PHP version mismatch. Expected: $PHP_VERSION_MAJOR_MINOR, Installed: $installed_version"
          return 0
        fi
      fi
    fi
  else
    if [[ "$exit_on_failure" == true ]]; then
      log error "PHP is not installed and exit_on_failure is set."
      exit 1
    else
      log verbose "PHP is not installed."
      return 0
    fi
  fi

}

php_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  log verbose "Checking PHP installation..."
  php_verify

  log verbose "Checking if PHP is already installed and PHP_ALONGSIDE is not set..."
  if tool_exists "php" && [[ "${PHP_ALONGSIDE:-false}" == "false" ]]; then
    return 0
  fi

  if [[ "$DRY_RUN_CHANGES" == "true" ]]; then
    log verbose "DRY_RUN: Skipping repository setup and PHP installation"
  else
    log verbose "Setting up PHP repository..."
    if [ "$DISTRO" == "Ubuntu" ]; then
      log verbose "Adding Ondrej PHP repository for Ubuntu..."
      php_repository="ppa:ondrej/php"
      log verbose "Adding Ondrej Apache2 repository for Ubuntu..."
      apache_repository="ppa:ondrej/apache2"
    elif [ "$DISTRO" == "Debian" ]; then
      log verbose "Adding Sury PHP repository for Debian..."
      php_repository="deb https://packages.sury.org/php/ $CODENAME main"
      log verbose "Adding Sury Apache2 repository for Debian..."
      apache_repository="deb https://packages.sury.org/apache2/ $CODENAME main"
    else
      log error "Unsupported distro: $DISTRO"
      exit 1
    fi

    if [ "$package_manager" == "apt" ]; then
      log verbose "Ensuring repository is added $php_repository..."
      repository_ensure "$php_repository"
      log verbose "Ensuring repository is added $apache_repository..."
      repository_ensure "$apache_repository"
    fi

    log verbose "Installing PHP core..."
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
      # Install only CLI and common packages, avoid the metapackage that pulls in Apache
      # When using nginx, we'll install php-fpm separately; when using apache, we'll install mod_php separately
      php_package="php${PHP_VERSION_MAJOR_MINOR}-cli php${PHP_VERSION_MAJOR_MINOR}-common"
    else
      log error "Unsupported distro: $DISTRO"
      exit 1
    fi

    log verbose "Installing PHP packages: $php_package"
    package_ensure $php_package

    # Verify PHP installation at end of function
    php_verify --exit-on-failure
  fi
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

function php_configure_for_moodle() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Configure PHP settings for Moodle
  local php_ini_paths=(
    "/etc/php/${PHP_VERSION_MAJOR_MINOR}/cli/php.ini"
    "/etc/php/${PHP_VERSION_MAJOR_MINOR}/apache2/php.ini"
    "/etc/php/${PHP_VERSION_MAJOR_MINOR}/fpm/php.ini"
  )

  for php_ini in "${php_ini_paths[@]}"; do
    if [ -f "$php_ini" ]; then
      log verbose "Configuring $php_ini for Moodle requirements"

      # Set max_input_vars to 5000 (Moodle requirement)
      if grep -q "^max_input_vars" "$php_ini"; then
        run_command --makes-changes sed -i 's/^max_input_vars.*/max_input_vars = 5000/' "$php_ini"
      else
        run_command --makes-changes sed -i '/; max_input_vars/a max_input_vars = 5000' "$php_ini"
      fi

      # Other recommended settings for Moodle
      run_command --makes-changes sed -i 's/^max_execution_time.*/max_execution_time = 300/' "$php_ini"
      run_command --makes-changes sed -i 's/^memory_limit.*/memory_limit = 256M/' "$php_ini"
      run_command --makes-changes sed -i 's/^post_max_size.*/post_max_size = 100M/' "$php_ini"
      run_command --makes-changes sed -i 's/^upload_max_filesize.*/upload_max_filesize = 100M/' "$php_ini"

      log verbose "PHP configuration updated in $php_ini"
    fi
  done

  # Restart PHP-FPM if it's running
  if $FPM_ENSURE; then
    run_command --makes-changes service_manage "php${PHP_VERSION_MAJOR_MINOR}-fpm" restart
  fi
}

function php_fpm_create_pool() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local pool_name="${1}"
  local pool_user="${2}"
  local pool_group="${3:-www-data}"
  local listen_user="${4:-www-data}"
  local listen_group="${5:-www-data}"

  # Create the pool configuration file
  local pool_conf="/etc/php/${PHP_VERSION_MAJOR_MINOR}/fpm/pool.d/${pool_name}.conf"

  log verbose "Creating PHP-FPM pool configuration for ${pool_name}"

  cat > "${pool_conf}" << EOF
[${pool_name}]

; Pool user and group
user = ${pool_user}
group = ${pool_group}

; Unix socket configuration
listen = /run/php/php${PHP_VERSION_MAJOR_MINOR}-${pool_name}.sock
listen.owner = ${listen_user}
listen.group = ${listen_group}
listen.mode = 0660

; Process manager configuration
pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500

; PHP configuration for Moodle
php_admin_value[error_log] = /var/log/php/${pool_name}-error.log
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_vars] = 5000
php_admin_value[upload_max_filesize] = 100M
php_admin_value[post_max_size] = 100M
php_admin_value[session.save_path] = /var/lib/php/sessions/${pool_name}

; Additional security settings
php_admin_flag[log_errors] = on
php_admin_flag[display_errors] = off
php_admin_value[error_reporting] = E_ALL & ~E_DEPRECATED & ~E_STRICT
php_admin_value[open_basedir] = ${moodleDir}:${moodleDataDir}:/usr/share/php:/tmp

; Opcache settings for better performance
php_admin_value[opcache.enable] = 1
php_admin_value[opcache.memory_consumption] = 128
php_admin_value[opcache.max_accelerated_files] = 10000
php_admin_value[opcache.revalidate_freq] = 60
EOF

  # Create necessary directories
  run_command --makes-changes mkdir -p "/var/log/php"
  run_command --makes-changes mkdir -p "/var/lib/php/sessions/${pool_name}"
  run_command --makes-changes chown -R "${pool_user}:${pool_group}" "/var/lib/php/sessions/${pool_name}"
  run_command --makes-changes chmod 700 "/var/lib/php/sessions/${pool_name}"

  # Restart PHP-FPM to load the new pool
  run_command --makes-changes service_manage "php${PHP_VERSION_MAJOR_MINOR}-fpm" restart

  log verbose "PHP-FPM pool '${pool_name}' created successfully"
}

function self_signed_cert_request() {
  log verbose "Entered function ${FUNCNAME[0]}"
  local domain=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --domain)
      shift
      domain="$1"
      shift
      ;;
    *)
      log error "Invalid option: $1"
      exit 1
      ;;
    esac
  done

  if [ -z "$domain" ]; then
    log error "Missing or incomplete parameters. Usage: ${FUNCNAME[0]} --domain example.com"
    exit 1
  fi

  if ! tool_exists openssl; then
    log info "openssl is not installed."
    package_ensure openssl
  fi

  # Define certificate paths in /etc/ssl/
  local cert_file="/etc/ssl/${domain}.cert"
  local key_file="/etc/ssl/${domain}.key"

  # Check if certificate already exists
  if [[ -f "${cert_file}" ]]; then
    log info "Certificate already exists: ${cert_file}"
  else
    log info "Creating self-signed certificate for ${domain}"
    log verbose "  Certificate: ${cert_file}"
    log verbose "  Key: ${key_file}"

    # Create self-signed certificate in /etc/ssl/
    run_command --makes-changes openssl req -x509 -nodes -days 365 \
      -newkey "rsa:2048" \
      -out "${cert_file}" \
      -keyout "${key_file}" \
      -subj "/CN=${domain}" \
      -addext "subjectAltName = DNS:${domain}, DNS:www.${domain}" \
      -addext "keyUsage = digitalSignature" \
      -addext "extendedKeyUsage = serverAuth"

    log info "Self-signed certificate created successfully"
  fi
}

function prometheus_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Create prometheus user and group
  if ! id -u prometheus >/dev/null 2>&1; then
    run_command --makes-changes adduser --system --group --no-create-home prometheus
  fi

  # Create directories
  run_command --makes-changes mkdir -p /etc/prometheus
  run_command --makes-changes mkdir -p /var/lib/prometheus
  run_command --makes-changes chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

  # Download and install Prometheus
  local prometheus_version="2.47.2"
  local prometheus_arch="linux-amd64"
  local prometheus_url="https://github.com/prometheus/prometheus/releases/download/v${prometheus_version}/prometheus-${prometheus_version}.${prometheus_arch}.tar.gz"

  if [ ! -f "/usr/local/bin/prometheus" ]; then
    log verbose "Downloading Prometheus ${prometheus_version}"
    run_command --makes-changes wget -O /tmp/prometheus.tar.gz "${prometheus_url}"
    run_command --makes-changes tar -xzf /tmp/prometheus.tar.gz -C /tmp
    run_command --makes-changes cp /tmp/prometheus-${prometheus_version}.${prometheus_arch}/prometheus /usr/local/bin/
    run_command --makes-changes cp /tmp/prometheus-${prometheus_version}.${prometheus_arch}/promtool /usr/local/bin/
    run_command --makes-changes cp -r /tmp/prometheus-${prometheus_version}.${prometheus_arch}/consoles /etc/prometheus/
    run_command --makes-changes cp -r /tmp/prometheus-${prometheus_version}.${prometheus_arch}/console_libraries /etc/prometheus/
    run_command --makes-changes chown -R prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool
    run_command --makes-changes chmod +x /usr/local/bin/prometheus /usr/local/bin/promtool
    run_command --makes-changes rm -rf /tmp/prometheus*
  fi

  # Create Prometheus configuration
  cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
    - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
    - targets: ['localhost:9100']

  - job_name: 'apache'
    static_configs:
    - targets: ['localhost:9117']

  - job_name: 'nginx'
    static_configs:
    - targets: ['localhost:9113']

  - job_name: 'php-fpm'
    static_configs:
    - targets: ['localhost:9253']
EOF

  run_command --makes-changes chown prometheus:prometheus /etc/prometheus/prometheus.yml

  # Create systemd service
  cat > /etc/systemd/system/prometheus.service << 'EOF'
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --web.external-url=

SyslogIdentifier=prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  # Enable and start Prometheus
  run_command --makes-changes systemctl daemon-reload
  run_command --makes-changes service_manage prometheus enable
  run_command --makes-changes service_manage prometheus start

  log verbose "Prometheus installation completed"

  # Install exporters
  prometheus_install_node_exporter

  if $APACHE_ENSURE; then
    prometheus_install_apache_exporter
  fi

  if $NGINX_ENSURE; then
    prometheus_install_nginx_exporter
  fi

  if $FPM_ENSURE; then
    prometheus_install_phpfpm_exporter
  fi
}

function prometheus_install_node_exporter() {
  log verbose "Installing Node Exporter"

  local node_exporter_version="1.7.0"
  local node_exporter_arch="linux-amd64"
  local node_exporter_url="https://github.com/prometheus/node_exporter/releases/download/v${node_exporter_version}/node_exporter-${node_exporter_version}.${node_exporter_arch}.tar.gz"

  if [ ! -f "/usr/local/bin/node_exporter" ]; then
    run_command --makes-changes wget -O /tmp/node_exporter.tar.gz "${node_exporter_url}"
    run_command --makes-changes tar -xzf /tmp/node_exporter.tar.gz -C /tmp
    run_command --makes-changes cp /tmp/node_exporter-${node_exporter_version}.${node_exporter_arch}/node_exporter /usr/local/bin/
    run_command --makes-changes chown prometheus:prometheus /usr/local/bin/node_exporter
    run_command --makes-changes chmod +x /usr/local/bin/node_exporter
    run_command --makes-changes rm -rf /tmp/node_exporter*
  fi

  # Create systemd service
  cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF

  run_command --makes-changes systemctl daemon-reload
  run_command --makes-changes service_manage node_exporter enable
  run_command --makes-changes service_manage node_exporter start
}

function prometheus_install_apache_exporter() {
  log verbose "Installing Apache Exporter"

  # Enable Apache server-status module
  run_command --makes-changes a2enmod status

  # Configure Apache status page
  cat > /etc/apache2/conf-available/server-status.conf << 'EOF'
<Location "/server-status">
    SetHandler server-status
    Require local
    Require ip 127.0.0.1
</Location>
EOF

  run_command --makes-changes a2enconf server-status
  run_command --makes-changes service_manage apache2 reload

  # Install apache_exporter
  local apache_exporter_version="1.0.3"
  local apache_exporter_url="https://github.com/Lusitaniae/apache_exporter/releases/download/v${apache_exporter_version}/apache_exporter-${apache_exporter_version}.linux-amd64.tar.gz"

  if [ ! -f "/usr/local/bin/apache_exporter" ]; then
    run_command --makes-changes wget -O /tmp/apache_exporter.tar.gz "${apache_exporter_url}"
    run_command --makes-changes tar -xzf /tmp/apache_exporter.tar.gz -C /tmp
    run_command --makes-changes cp /tmp/apache_exporter-${apache_exporter_version}.linux-amd64/apache_exporter /usr/local/bin/
    run_command --makes-changes chown prometheus:prometheus /usr/local/bin/apache_exporter
    run_command --makes-changes chmod +x /usr/local/bin/apache_exporter
    run_command --makes-changes rm -rf /tmp/apache_exporter*
  fi

  # Create systemd service
  cat > /etc/systemd/system/apache_exporter.service << 'EOF'
[Unit]
Description=Apache Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/apache_exporter --scrape_uri=http://localhost/server-status?auto

[Install]
WantedBy=multi-user.target
EOF

  run_command --makes-changes systemctl daemon-reload
  run_command --makes-changes service_manage apache_exporter enable
  run_command --makes-changes service_manage apache_exporter start
}

function prometheus_install_nginx_exporter() {
  log verbose "Installing Nginx Exporter"

  # Configure Nginx stub_status
  cat > /etc/nginx/sites-available/stub_status << 'EOF'
server {
    listen 127.0.0.1:8080;
    server_name localhost;

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF

  run_command --makes-changes ln -sf /etc/nginx/sites-available/stub_status /etc/nginx/sites-enabled/
  run_command --makes-changes service_manage nginx reload

  # Install nginx-prometheus-exporter
  local nginx_exporter_version="0.11.0"
  local nginx_exporter_url="https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v${nginx_exporter_version}/nginx-prometheus-exporter_${nginx_exporter_version}_linux_amd64.tar.gz"

  if [ ! -f "/usr/local/bin/nginx-prometheus-exporter" ]; then
    run_command --makes-changes wget -O /tmp/nginx_exporter.tar.gz "${nginx_exporter_url}"
    run_command --makes-changes tar -xzf /tmp/nginx_exporter.tar.gz -C /tmp
    run_command --makes-changes cp /tmp/nginx-prometheus-exporter /usr/local/bin/
    run_command --makes-changes chown prometheus:prometheus /usr/local/bin/nginx-prometheus-exporter
    run_command --makes-changes chmod +x /usr/local/bin/nginx-prometheus-exporter
    run_command --makes-changes rm -rf /tmp/nginx_exporter* /tmp/nginx-prometheus-exporter
  fi

  # Create systemd service
  cat > /etc/systemd/system/nginx_exporter.service << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri=http://127.0.0.1:8080/nginx_status

[Install]
WantedBy=multi-user.target
EOF

  run_command --makes-changes systemctl daemon-reload
  run_command --makes-changes service_manage nginx_exporter enable
  run_command --makes-changes service_manage nginx_exporter start
}

function prometheus_install_phpfpm_exporter() {
  log verbose "Installing PHP-FPM Exporter"

  # Enable PHP-FPM status page
  local fpm_pool_dir="/etc/php/${PHP_VERSION_MAJOR_MINOR}/fpm/pool.d"

  # Add status configuration to www pool
  if [ -f "${fpm_pool_dir}/www.conf" ]; then
    if ! grep -q "pm.status_path" "${fpm_pool_dir}/www.conf"; then
      cat >> "${fpm_pool_dir}/www.conf" << 'EOF'

; Enable status page
pm.status_path = /status
pm.status_listen = 127.0.0.1:9001
EOF
    fi
  fi

  run_command --makes-changes service_manage "php${PHP_VERSION_MAJOR_MINOR}-fpm" restart

  # Install php-fpm_exporter
  local phpfpm_exporter_version="2.2.0"
  local phpfpm_exporter_url="https://github.com/hipages/php-fpm_exporter/releases/download/v${phpfpm_exporter_version}/php-fpm_exporter_${phpfpm_exporter_version}_linux_amd64"

  if [ ! -f "/usr/local/bin/php-fpm_exporter" ]; then
    run_command --makes-changes wget -O /usr/local/bin/php-fpm_exporter "${phpfpm_exporter_url}"
    run_command --makes-changes chown prometheus:prometheus /usr/local/bin/php-fpm_exporter
    run_command --makes-changes chmod +x /usr/local/bin/php-fpm_exporter
  fi

  # Create systemd service
  cat > /etc/systemd/system/php-fpm_exporter.service << 'EOF'
[Unit]
Description=PHP-FPM Prometheus Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
Environment="PHP_FPM_SCRAPE_URI=tcp://127.0.0.1:9001/status"
ExecStart=/usr/local/bin/php-fpm_exporter

[Install]
WantedBy=multi-user.target
EOF

  run_command --makes-changes systemctl daemon-reload
  run_command --makes-changes service_manage php-fpm_exporter enable
  run_command --makes-changes service_manage php-fpm_exporter start
}

function memcached_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  # Check if memcached is already installed
  if tool_exists "memcached"; then
    log verbose "Memcached is already installed."
    run_command memcached -V
  else
    log verbose "Installing memcached..."
    package_ensure memcached
  fi

  # Install PHP memcached extension
  log verbose "Installing PHP memcached extension..."
  package_ensure "php${PHP_VERSION_MAJOR_MINOR}-memcached"

  # Start memcached service
  run_command --makes-changes service_manage memcached start

  log verbose "Memcached installation completed."
}

function mysql_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if MySQL/MariaDB is installed
  if tool_exists "mysql"; then
    log verbose "MySQL/MariaDB is installed."
    run_command mysql --version

    # Check if MySQL service is running
    log verbose "Checking MySQL/MariaDB service status:"
    if run_command service_manage mysql is-active || run_command service_manage mariadb is-active; then
      log verbose "MySQL/MariaDB service is running."
    else
      log verbose "MySQL/MariaDB service is not running."
      if [[ "$exit_on_failure" == true ]]; then
        exit 1
      fi
    fi
  else
    log verbose "MySQL/MariaDB is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi
}

function mysql_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  mysql_verify

  if [[ "$DRY_RUN_CHANGES" == "true" ]]; then
    log verbose "DRY_RUN: Skipping MySQL/MariaDB installation"
  else
    log verbose "Installing MySQL/MariaDB..."

    # Install MariaDB server and client
    package_ensure mariadb-server mariadb-client

    # Start and enable MariaDB service
    run_command --makes-changes service_manage mariadb start
    run_command --makes-changes service_manage mariadb enable

    log verbose "MariaDB installation completed."

    # Generate secure random password
    local db_password
    db_password=$(openssl rand -base64 16 | tr -d "=+/")

    # Store password in /tmp with restricted permissions
    local password_file="/tmp/${DB_USER}-db_password"
    echo "$db_password" > "$password_file"
    run_command --makes-changes chmod 600 "$password_file"
    log verbose "Database password stored in ${password_file}"

    # Update the global DB_PASS variable
    DB_PASS="$db_password"

    # Create database with UTF-8 encoding
    log verbose "Creating database ${DB_NAME}..."
    run_command --makes-changes mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

    # Create database user and grant privileges
    log verbose "Creating database user ${DB_USER}..."
    run_command --makes-changes mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';"
    run_command --makes-changes mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';"
    run_command --makes-changes mysql -e "FLUSH PRIVILEGES;"

    # Configure MySQL/MariaDB for Moodle
    log verbose "Configuring MySQL/MariaDB for Moodle requirements..."

    # Create Moodle-specific configuration file
    cat > /etc/mysql/mariadb.conf.d/99-moodle.cnf << 'EOF'
[mysqld]
# Moodle requirements
innodb_file_format = Barracuda
innodb_file_per_table = 1
innodb_large_prefix = ON
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default-storage-engine = INNODB

# Performance tuning
max_allowed_packet = 512M
innodb_buffer_pool_size = 256M
EOF

    run_command --makes-changes service_manage mariadb restart

    log verbose "MySQL/MariaDB configuration completed."
    log info "Database: ${DB_NAME}"
    log info "User: ${DB_USER}"
    log info "Password stored in: ${password_file}"
  fi

  mysql_verify --exit-on-failure
}

function postgres_verify() {
  log verbose "Entered function ${FUNCNAME[0]}"

  local exit_on_failure=false # Default to false

  # Check if the first argument is the flag for exit on failure
  # Because we have `set -o nounset` set, we need to check if the first argument is set
  if [[ "${1:-}" == "--exit-on-failure" ]]; then
    exit_on_failure=true
  fi

  # Check if PostgreSQL is installed
  if tool_exists "psql"; then
    log verbose "PostgreSQL is installed."
    run_command psql --version

    # Check if PostgreSQL service is running
    log verbose "Checking PostgreSQL service status:"
    if run_command service_manage postgresql is-active; then
      log verbose "PostgreSQL service is running."
    else
      log verbose "PostgreSQL service is not running."
      if [[ "$exit_on_failure" == true ]]; then
        exit 1
      fi
    fi
  else
    log verbose "PostgreSQL is not installed."
    if [[ "$exit_on_failure" == true ]]; then
      exit 1
    fi
  fi
}

function postgres_ensure() {
  log verbose "Entered function ${FUNCNAME[0]}"

  postgres_verify

  if [[ "$DRY_RUN_CHANGES" == "true" ]]; then
    log verbose "DRY_RUN: Skipping PostgreSQL installation"
  else
    log verbose "Setting up PostgreSQL repository..."

    # Create APT keyrings directory if it doesn't exist
    run_command --makes-changes mkdir -p /etc/apt/keyrings

    # Download PostgreSQL signing key
    if [ ! -f "/etc/apt/keyrings/postgresql.asc" ]; then
      log verbose "Downloading PostgreSQL signing key..."
      run_command --makes-changes wget -O /etc/apt/keyrings/postgresql.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
    fi

    # Add PostgreSQL APT repository
    local postgres_version="16"
    local postgres_repository="deb [arch=amd64 signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main"

    if [ "$package_manager" == "apt" ]; then
      log verbose "Adding PostgreSQL repository..."
      repository_ensure "$postgres_repository"
    fi

    log verbose "Installing PostgreSQL..."
    package_ensure "postgresql-${postgres_version}" "postgresql-contrib-${postgres_version}" libpq-dev

    # Start and enable PostgreSQL service
    run_command --makes-changes service_manage postgresql start
    run_command --makes-changes service_manage postgresql enable

    log verbose "PostgreSQL installation completed."

    # Generate secure random password
    local db_password
    db_password=$(openssl rand -base64 16 | tr -d "=+/")

    # Store password in /tmp with restricted permissions
    local password_file="/tmp/${DB_USER}-db_password"
    echo "$db_password" > "$password_file"
    run_command --makes-changes chmod 600 "$password_file"
    log verbose "Database password stored in ${password_file}"

    # Update the global DB_PASS variable
    DB_PASS="$db_password"

    # Create database user
    log verbose "Creating database user ${DB_USER}..."
    run_command --makes-changes sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"

    # Create database with UTF-8 encoding
    log verbose "Creating database ${DB_NAME}..."
    run_command --makes-changes sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} WITH OWNER ${DB_USER} ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8' TEMPLATE=template0;"

    # Grant privileges
    run_command --makes-changes sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

    # Configure PostgreSQL for Moodle
    log verbose "Configuring PostgreSQL for Moodle requirements..."

    # Update postgresql.conf for performance
    local pg_config="/etc/postgresql/${postgres_version}/main/postgresql.conf"
    if [ -f "$pg_config" ]; then
      # Backup original config
      run_command --makes-changes cp "$pg_config" "${pg_config}.backup"

      # Update configuration values
      if ! grep -q "^max_connections" "$pg_config"; then
        echo "max_connections = 200" >> "$pg_config"
      fi
      if ! grep -q "^shared_buffers" "$pg_config"; then
        echo "shared_buffers = 256MB" >> "$pg_config"
      fi

      run_command --makes-changes service_manage postgresql restart
    fi

    log verbose "PostgreSQL configuration completed."
    log info "Database: ${DB_NAME}"
    log info "User: ${DB_USER}"
    log info "Password stored in: ${password_file}"
  fi

  postgres_verify --exit-on-failure
}

# Main function
function main() {

  log verbose "Entered function ${FUNCNAME[0]}"

  package_manager_ensure

  log verbose "checking ACME_CERT"
  if $ACME_CERT; then
    log verbose "Creating ACME certificate..."
    provider=$(acme_cert_provider "${ACME_PROVIDER}")
    acme_cert_request --domain "${moodleSiteName}" --email "admin@example.com" --challenge "http" --provider "${provider}"
  fi

  log verbose "checking SELF_SIGNED_CERT"
  if $SELF_SIGNED_CERT; then
    log verbose "Creating self-signed certificate..."
    self_signed_cert_request --domain "${moodleSiteName}"
  fi

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
  if $MEMCACHED_ENSURE; then
    log verbose "Ensuring Memcached..."
    memcached_ensure
  fi

  log verbose "checking MYSQL_ENSURE"
  if $MYSQL_ENSURE; then
    log verbose "Ensuring MySQL/MariaDB..."
    mysql_ensure
  fi

  log verbose "checking POSTGRES_ENSURE"
  if $POSTGRES_ENSURE; then
    log verbose "Ensuring PostgreSQL..."
    postgres_ensure
  fi

  log verbose "checking MOODLE_ENSURE"
  if $MOODLE_ENSURE; then
    log verbose "Ensuring Moodle..."
    moodle_ensure
  fi

  log verbose "checking PROMETHEUS_ENSURE"
  if $PROMETHEUS_ENSURE; then
    log verbose "Ensuring Prometheus..."
    prometheus_ensure
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

detect_distro_and_codename

# Check if the necessary dependencies are available before proceeding
# add-apt-repository is only needed on Ubuntu for PPA support
if [ "$DISTRO" = "Ubuntu" ] && ! tool_exists "add-apt-repository"; then
  log error "add-apt-repository command not found. Please install software-properties-common."
  exit 1
fi
if ! tool_exists "tar"; then
  log error "tar command not found. Please install tar."
  exit 1
fi
if ! tool_exists "unzip"; then
  log error "unzip command not found. Please install unzip."
  exit 1
fi
if ! tool_exists "wget"; then
  log error "wget command not found. Please install wget."
  exit 1
fi

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

  -a | --acme-cert)
    ACME_CERT=true
    shift
    ;;

  -c | --ci)
    CI_MODE=true
    shift
    ;;

  -d | --database)
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      case "$2" in
      mysql | mysqli)
        DB_TYPE="mysql"
        MYSQL_ENSURE=true
        POSTGRES_ENSURE=false
        shift # past value
        ;;
      pgsql)
        DB_TYPE="pgsql"
        MYSQL_ENSURE=false
        POSTGRES_ENSURE=true
        shift # past value
        ;;
      *)
        log error "Unsupported database type: $2. Supported types are 'mysql', 'mysqli' and 'pgsql'."
        echo_usage
        exit 1
        ;;
      esac
    else
      # Use the default value for DB_TYPE
      DB_TYPE="mysql"
      MYSQL_ENSURE=true
      POSTGRES_ENSURE=false
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
      PHP_VERSION_MAJOR_MINOR="$2"
      shift # past value
    else
      PHP_VERSION_MAJOR_MINOR="$DEFAULT_PHP_VERSION_MAJOR_MINOR"
    fi
    shift # past argument
    ;;

  -P | --php-alongside)
    PHP_ENSURE=true
    if [[ -n "${2:-}" ]] && [[ "${2:-}" != "-"* ]]; then
      PHP_VERSION_MAJOR_MINOR="$2"
      PHP_ALONGSIDE=true
      shift # past value
    else
      PHP_VERSION_MAJOR_MINOR="$DEFAULT_PHP_VERSION_MAJOR_MINOR"
      PHP_ALONGSIDE=true
    fi
    shift # past argument
    ;;

  -r | --prometheus)
    PROMETHEUS_ENSURE=true
    shift
    ;;

  -s | --sudo)
    USE_SUDO=true
    shift
    ;;

  -S | --self-signed)
    SELF_SIGNED_CERT=true
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
      # Use the default web server (Nginx)
      APACHE_ENSURE=false
      NGINX_ENSURE=true
      FPM_ENSURE=true
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
  if $PHP_ENSURE; then chosen_options+="-p: Ensure PHP version $PHP_VERSION_MAJOR_MINOR, "; fi
  if $PROMETHEUS_ENSURE; then chosen_options+="-r: Ensure Prometheus monitoring, "; fi
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
