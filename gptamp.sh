#!/usr/bin/env bash
# This shebang line uses the env command to locate the bash interpreter in the user's PATH
#  environment variable. This means that the script will be executed with the bash interpreter
#  that is found first in the user's PATH. This approach is more flexible and portable because
#  it relies on the system's PATH to find the appropriate interpreter.
#  It can be particularly useful in situations where the exact path to the interpreter
#  might vary across different systems.

# Set up error handling
set -euo pipefail

# Set locale to avoid issues with apt-get
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

# Define default options
# I tend to leave these as false, and set with command line options
VERBOSE=true
DRY_RUN=false
INSTALL_APACHE=false
INSTALL_MOODLE=false
INSTALL_PHP=false
INSTALL_FPM=false
MOODLE_VERSION="311"
PHP_VERSION="7.2"

# Moodle database
DB_TYPE="mysqli"
DB_HOST="localhost"
DB_NAME="moodle"
DB_USER="moodle"
DB_PASS="moodle"
DB_PREFIX="mdl_"

# Users
apacheUser="www-data"
moodleUser="moodle"

# Site name
moodleSiteName="moodle.romn.co"

# Directories
apacheDocumentRoot="/var/www/html"
moodleDir="${apacheDocumentRoot}/${moodleSiteName}"
moodleDataDir="/home/${moodleUser}/moodledata"

# Used internally by the script
USER_REQUIRES_PASSWORD_TO_SUDO='true'
NON_ROOT_USER='true'

# helper functions
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


# Function to install Apache web server
install_apache() {
    # Install Apache and enable required modules
    echo_stdout_verbose "Installing Apache..."
    run_command apt-get install --yes apache2

    if $INSTALL_FPM; then
        echo_stdout_verbose "Configuring Apache for FPM..."
        run_command a2enmod proxy_fcgi setenvif
        run_command a2enconf "php${PHP_VERSION}-fpm"
        run_command apt-get install --yes "libapache2-mod-fcgid"
        run_command service "php${PHP_VERSION}-fpm" start
    else
        echo_stdout_verbose "Configuring Apache without FPM..."
        run_command apt-get install --yes "libapache2-mod-php${PHP_VERSION}"
    fi

    # Restart Apache
    run_command service apache2 restart
    echo_stdout_verbose "Apache installation and configuration completed."
}


# Function to install PHP and required extensions
install_php() {
    echo_stdout_verbose "Installing PHP and required extensions..."

    # Alphabetised version of the list from https://docs.moodle.org/310/en/PHP
    # The ctype extension is required.
    # The curl extension is required (required for networking and web services).
    # The dom extension is required.
    # The gd extension is recommended (required for manipulating images).
    # The iconv extension is required.
    # The intl extension is recommended.
    # The json extension is required.
    # The mbstring extension is required.
    # The openssl extension is recommended (required for networking and web services).
    # The pcre extension is required.
    # The simplexml extension is required.
    # The soap extension is recommended (required for web services).
    # The spl extension is required.
    # The tokenizer extension is recommended.
    # The xml extension is required.
    # The xmlrpc extension is recommended (required for networking and web services).
    # The zip extension is required.

    run_command apt-get install -y "php${PHP_VERSION}" "libapache2-mod-php${PHP_VERSION}" \
        php-ctype \
        php-curl \
        php-dom \
        php-gd \
        php-iconv \
        php-intl \
        php-json \
        php-mbstring \
        php-openssl \
        php-pcre \
        php-simplexml \
        php-soap \
        php-spl \
        php-tokenizer \
        php-xml \
        php-xmlrpc \
        php-zip

            if [ "${DB_TYPE}" == "pgsql" ]; then
                # Install php-pgsql extension for PostgreSQL
                run_command apt-get install -y php-pgsql
            else
                # Install php-mysqli extension for MySQL and MariaDB
                # Note php-mysql is deprecated in PHP 7.0 and removed in PHP 7.2
                # Note we are not supporting all the different database types that Moodle supports
                run_command apt-get install -y php-mysqli
            fi
}

moodle_config_files() {
    local configDist="config-dist.php"
    local configFile="config.php"

    if [ -f "${configDist}" ]; then
        if [ -f "${configFile}" ]; then
            echo_stdout_verbose "${configFile} already exists. Skipping configuration setup."
        else
            # Copy config-dist.php to config.php
            run_command cp "${configDist}" "${configFile}"
            echo_stdout_verbose "${configFile} copied from ${configDist}."
        fi
        echo_stdout_verbose "Setting up database configuration in ${configFile}..."
        # Modify values in config.php using sed (if config.php was copied)
        if [ -f "${configFile}" ]; then
            sed -i "s/\$CFG->dbtype\s*=\s*'pgsql';/\$CFG->dbtype = '${DB_TYPE}';/" "${configFile}"
            sed -i "s/\$CFG->dbhost\s*=\s*'localhost';/\$CFG->dbhost = '${DB_HOST}';/" "${configFile}"
            sed -i "s/\$CFG->dbname\s*=\s*'moodle';/\$CFG->dbname = '${DB_NAME}';/" "${configFile}"
            sed -i "s/\$CFG->dbuser\s*=\s*'username';/\$CFG->dbuser = '${DB_USER}';/" "${configFile}"
            sed -i "s/\$CFG->dbpass\s*=\s*'password';/\$CFG->dbpass = '${DB_PASS}';/" "${configFile}"
            sed -i "s/\$CFG->prefix\s*=\s*'mdl_';/\$CFG->prefix = '${DB_PREFIX}';/" "${configFile}"
            sed -i "s|\$CFG->wwwroot.*|\$CFG->wwwroot   = 'https://${moodleSiteName}';|" "${configFile}"
            sed -i "s|\$CFG->dataroot.*|\$CFG->dataroot  = '${moodleDataDir}';|" "${configFile}"

            echo_stdout_verbose "Configuration file changes completed."
        fi
    else
        echo_stderr "Error: ${configDist} does not exist."
        exit 1
    fi
}


moodle_configure_directories() {
  local moodleUser="${1}"
  local apacheUser="${2}"
  local moodleDataDir="${3}"
  local moodleDir="${4}"

  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  # Add moodle user for moodledata / Change ownerships and permissions
  run_command adduser --system "${moodleUser}"
  run_command mkdir -p "${moodleDataDir}"
  run_command chown -R "${apacheUser}:${apacheUser}" "${moodleDataDir}"
  run_command chmod 0777 "${moodleDataDir}"
  run_command mkdir -p "${moodleDir}"
  run_command chown -R root:"${apacheUser}" "${moodleDir}"
  run_command chmod -R 0755 "${moodleDir}"
}

moodle_download_extract() {
  local moodleDir="${1}"
  local apacheUser="${2}"
  local moodleVersion="${3}"
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz"

  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  # Download and extract Moodle
  echo_stdout_verbose "Downloading and extracting ${moodleArchive}"
  run_command mkdir -p "${moodleDir}"
  run_command wget -qO - "${moodleArchive}" | tar zx -C "${moodleDir}" --strip-components 1
  run_command chown -R root:"${apacheUser}" "${moodleDir}"
  run_command chmod -R 0755 "${moodleDir}"
}

while getopts ":afmn:p:v:" opt; do
    case "${opt}" in
        a) INSTALL_APACHE=true ;;
        f) INSTALL_FPM=true ;;
        m) INSTALL_MOODLE=true ;;
        n) DRY_RUN=true ;;
        p) INSTALL_PHP=true; PHP_VERSION=${OPTARG} ;;
        v) MOODLE_VERSION=${OPTARG} ;;
        \?) echo "Invalid option: -$OPTARG" >&2
            usage ;;
    esac
done

if check_is_true "${VERBOSE}"; then
    chosen_options=""
    if $INSTALL_APACHE; then chosen_options+="Install Apache, "; fi
    if $INSTALL_FPM; then chosen_options+="Install Apache with FPM, "; fi
    if $INSTALL_MOODLE; then chosen_options+="Install Moodle, "; fi
    if $DRY_RUN; then chosen_options+="Dry run, "; fi
    if $INSTALL_PHP; then chosen_options+="Install PHP version $PHP_VERSION, "; fi
    if [ -n "$MOODLE_VERSION" ]; then chosen_options+="Use Moodle version: $MOODLE_VERSION, "; fi
    chosen_options="${chosen_options%, }"

    echo_stdout_verbose "Options chosen: $chosen_options"
fi




usage() {
    echo_stdout "Usage: $0 [options]"
    echo_stdout "Options:"
    echo_stdout "  -a    Install Apache web server"
    echo_stdout "  -f    Install Apache with FPM"
    echo_stdout "  -m    Install Moodle"
    echo_stdout "  -n    Dry run (show commands without executing)"
    echo_stdout "  -p    Install PHP version (default: ${PHP_VERSION})"
    echo_stdout "  -v    Specify Moodle branch (default: ${MOODLE_VERSION})"
    echo_stdout "  Note: Options -p and -v require an argument."
    exit 1
}

# Main function
main() {

    check_user_is_root
    if check_is_true "${NON_ROOT_USER}"; then
      check_user_can_sudo_without_password_entry
      if check_is_true "${USER_REQUIRES_PASSWORD_TO_SUDO}"; then
        echo_stderr "User requires a password to issue sudo commands. Exiting"
        echo_stderr "Please re-run the script as root, or having sudo'd with a password"
        usage
      else
        SUDO='sudo '
        echo_stdout_verbose "User can issue sudo commands without entering a password. Continuing"
      fi
    fi

    run_command apt-get update

    if $INSTALL_PHP; then
        install_php
    fi

    if $INSTALL_APACHE; then
        install_apache
    fi

    if $INSTALL_MOODLE; then
        moodle_configure_directories "${moodleUser}" "${apacheUser}" "${moodleDataDir}" "${moodleDir}"
        moodle_download_extract "${moodleDir}" "${apacheUser}" "${MOODLE_VERSION}"
        moodle_config_files
    fi
}

# Run the main function
main

## Still to do
# Add option for memcached support
# Add option to install mysql locally
# Add option to install moodle with git rather than download



