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
VERBOSE=true
DRY_RUN=false
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

# Used internally by the script
USE_SUDO=false
CI_MODE=false

# helper functions

die() {
    echo "$1" >&2
    exit 1
}





apply_template() {
    local template="$1"
    shift
    local substitutions=("$@")

    for substitution in "${substitutions[@]}"; do
        IFS="=" read -r key value <<< "$substitution"
        template="${template//\{\{$key\}\}/$value}"
    done

    echo "$template"
}

check_command() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    local should_exit_on_failure=false  # Default to false

    # Check if the first argument is the flag for exit on failure
    if [[ "$1" == "--exit-on-failure" ]]; then
        should_exit_on_failure=true
        shift  # Remove the flag from the arguments list
    fi

    for command in "$@"
    do
        if type -P "${command}" &>/dev/null ; then
            echo_stdout_verbose "Dependency is present: ${command}"
        else
            echo_stderr "Dependency not found: ${command}, please install it and run this script again."
            if [[ "$should_exit_on_failure" == true ]]; then
                exit 1
            fi
        fi
    done
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
  local prefix=""

  # If DRY RUN mode is active, prefix the message

  if [[ "${DRY_RUN}" == "true" ]]; then
      prefix="DRY RUN: "
  fi

  if [[ "${VERBOSE}" == "true" ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: VERBOSE: ${prefix}${message}" >&1
  fi
}

package_manager_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

        if check_command apt; then
            package_manager="apt"
        else
            echo_stderr "Error: Package manager not found."
            exit 1
        fi
}



package_ensure() {
    local no_install_recommends_flag=""
    if [ "$1" == "--no-install-recommends" ]; then
        shift
        if [ "$package_manager" == "apt" ]; then
            no_install_recommends_flag="--no-install-recommends"
        else
            echo_stderr "Warning: --no-install-recommends flag is not supported for this package manager."
        fi
    fi

    local packages=("$@")
    local missing_packages=()

    for package in "${packages[@]}"
    do
        case "$package_manager" in
            apt)
                if ! dpkg -s "$package" >/dev/null 2>&1; then
                    missing_packages+=("$package")
                fi
                ;;
            *)
                echo_stderr "Error: Unsupported package manager."
                exit 1
                ;;
        esac
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo_stdout_verbose "Installing missing packages: ${missing_packages[*]}"

        case "$package_manager" in
            apt)
                run_command apt update
                run_command apt install --yes $no_install_recommends_flag "${missing_packages[@]}"
                ;;
            *)
                echo_stderr "Error: Unsupported package manager."
                exit 1
                ;;
        esac
    else
        echo_stdout_verbose "All packages are already installed."
    fi
}

repository_ensure() {
    local repositories=("$@")
    local missing_repositories=()

    case "$package_manager" in
        apt)
            for repository in "${repositories[@]}"
            do
                if ! run_command grep -q "^deb .*$repository" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
                    missing_repositories+=("$repository")
                fi
            done
            ;;
        *)
            echo_stderr "Error: Repositories management for this package manager is not supported."
            exit 1
            ;;
    esac

    if [ ${#missing_repositories[@]} -gt 0 ]; then
        echo_stdout_verbose "Adding missing repositories: ${missing_repositories[*]}"

        case "$package_manager" in
            apt)
                for repository in "${missing_repositories[@]}"; do
                    run_command add-apt-repository "$repository"
                done
                run_command apt update
                ;;
            *)
                echo_stderr "Error: Unsupported package manager."
                exit 1
                ;;
        esac
    else
        echo_stdout_verbose "All repositories are already added."
    fi
}



replace_file_value() {

  local current_value="$1"
  local new_value="$2"
  local file_path="$3"

  # Acquire lock on file
  exec 200>"$file_path"
  flock -x 200 || exit 1

  if [ -f "$file_path" ]; then

    # Check if current value already exists
    if run_command grep -q "$current_value" "$file_path"; then

      echo_stdout_verbose "Value $current_value already set in $file_path"

    else

      # Value not present, go ahead and replace
      run_command sed -i "s|$current_value|$new_value|" "$file_path"
      echo_stdout_verbose "Replaced $current_value with $new_value in $file_path"

    fi

  fi

  # Release lock
  flock -u 200

}


run_command() {
    if [[ ! -t 0 ]]; then
        cat
    fi

    printf -v cmd_str '%q ' "$@"

    # Decide whether to use sudo based on the command and global USE_SUDO setting
    local cmd=("$@")

    if $USE_SUDO && [[ "${cmd[0]}" != "brew" ]]; then
        cmd=("sudo" "${cmd[@]}")
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo_stdout_verbose "Not executing: ${cmd_str}"
        return
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
        echo_stdout_verbose "Preparing to execute: ${cmd_str}"
    fi

    "${cmd[@]}"
}




acme_cert_provider() {
    local provider=""
    case "$1" in
        staging) provider="https://acme-staging-v02.api.letsencrypt.org/directory" ;;
        production) provider="https://acme-v02.api.letsencrypt.org/directory" ;;
        *) echo_stderr "Invalid provider option: $1"; exit 1 ;;
    esac
    echo "$provider"
}

acme_cert_request() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
    local domain=""
    local email=""
    local san_entries=""
    local challenge_type="dns"
    local provider="https://acme-staging-v02.api.letsencrypt.org/directory"  # Default to Let's Encrypt sandbox

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain) shift; domain="$1"; shift ;;
            --email) shift; email="$1"; shift ;;
            --san) shift; san_entries="$1"; shift ;;
            --challenge) shift; challenge_type="$1"; shift ;;
            --provider) shift; provider="$1"; shift ;;
            *) echo_stderr "Invalid option: $1"; exit 1 ;;
        esac
    done

    if [ -z "$domain" ] || [ -z "$email" ]; then
        echo_stderr "Missing or incomplete parameters. Usage: ${FUNCNAME[0]} --domain example.com --email admin@example.com [--san \"www.example.com,sub.example.com\"] [--challenge http] [--provider \"https://acme-v02.api.letsencrypt.org/directory\"]"
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



# Function to ensure Apache web server is installed and configured
apache_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    # Check if PHP is installed
    # and exit if not
    php_verify true

        service_command="systemctl"

        # Install Apache and necessary modules for non-macOS systems
        package_ensure apache2
        package_ensure "libapache2-mod-ssl"
        package_ensure "libapache2-mod-headers"
        package_ensure "libapache2-mod-rewrite"
        package_ensure "libapache2-mod-deflate"
        package_ensure "libapache2-mod-expires"

        # Enable essential Apache modules
        run_command a2enmod ssl
        run_command a2enmod headers
        run_command a2enmod rewrite
        run_command a2enmod deflate
        run_command a2enmod expires

        if $FPM_ENSURE; then
            echo_stdout_verbose "Installing PHP FPM for non-macOS systems..."
            package_ensure "php${PHP_VERSION}-fpm"
            package_ensure "libapache2-mod-fcgid"

            echo_stdout_verbose "Configuring Apache for FPM..."
            run_command a2enmod proxy_fcgi setenvif
            run_command a2enconf "php${PHP_VERSION}-fpm"

            # Enable and start PHP FPM service
            run_command $service_command enable "php${PHP_VERSION}-fpm"
            run_command $service_command start "php${PHP_VERSION}-fpm"
        else
            echo_stdout_verbose "Configuring Apache without FPM..."
            package_ensure "libapache2-mod-php${PHP_VERSION}"
        fi

        run_command $service_command enable apache2
        run_command $service_command restart apache2

    echo_stdout_verbose "Apache installation and configuration completed."
}




apache_create_vhost() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    declare -n config=$1
    local logDir="${APACHE_LOG_DIR:-/var/log/apache2}"

    # Check if required configuration options are provided
    local required_options=("site-name" "document-root" "admin-email" "ssl-cert-file" "ssl-key-file")
    for option in "${required_options[@]}"; do
        if [[ -z "${config[$option]}" ]]; then
            echo_stderr "Missing required configuration option: $option"
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
    vhost_config=$(apply_template "$vhost_template" \
        "site_name=${config["site-name"]}" \
        "document_root=${config["document-root"]}" \
        "admin_email=${config["admin-email"]}" \
        "ssl_cert_file=${config["ssl-cert-file"]}" \
        "ssl_key_file=${config["ssl-key-file"]}" \
        "include_file=${config["include-file"]:+Include ${config["include-file"]}}"
    )

    echo "$vhost_config" > "/etc/apache2/sites-available/${config["site-name"]}.conf"
    run_command a2ensite "${config["site-name"]}"
}






moodle_dependencies() {
  # From https://github.com/moodlehq/moodle-php-apache/blob/master/root/tmp/setup/php-extensions.sh
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  declare -a runtime=("ghostscript" \
   "libaio1" \
   "libcurl4" \
   "libgss3" \
   "libicu72" \
   "libmcrypt-dev" \
   "libxml2" \
   "libxslt1.1" \
    "libzip-dev" \
    "sassc" \
    "unzip" \
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

moodle_config_files() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
    local configDir="${1}"
    local configDist="${configDir}/config-dist.php"
    configFile="${configDir}/config.php"

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

            replace_file_value "\$CFG->dbtype\s*=\s*'pgsql';" "\$CFG->dbtype = '${DB_TYPE}';" "$configFile"
            replace_file_value "\$CFG->dbhost\s*=\s*'localhost';" "\$CFG->dbhost = '${DB_HOST}';" "$configFile"
            replace_file_value "\$CFG->dbname\s*=\s*'moodle';" "\$CFG->dbname = '${DB_NAME}';" "$configFile"
            replace_file_value "\$CFG->dbuser\s*=\s*'username';" "\$CFG->dbuser = '${DB_USER}';" "$configFile"
            replace_file_value "\$CFG->dbpass\s*=\s*'password';" "\$CFG->dbpass = '${DB_PASS}';" "$configFile"
            replace_file_value "\$CFG->prefix\s*=\s*'mdl_';" "\$CFG->prefix = '${DB_PREFIX}';" "$configFile"
            replace_file_value "\$CFG->wwwroot.*" "\$CFG->wwwroot   = 'https://${moodleSiteName}';" "$configFile"
            replace_file_value "\$CFG->dataroot.*" "\$CFG->dataroot  = '${moodleDataDir}';" "$configFile"

            echo_stdout_verbose "Configuration file changes completed."
        fi
    else
        echo_stderr "Error: ${configDist} does not exist."
        if [ "${DRY_RUN}" != "true" ]; then
            exit 1
        fi
    fi
}

moodle_configure_directories() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local moodleUser="${1}"
  local webserverUser="${2}"
  local moodleDataDir="${3}"
  local moodleDir="${4}"

  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  # Add moodle user for moodledata / Change ownerships and permissions
  run_command adduser --system "${moodleUser}"
  run_command mkdir -p "${moodleDataDir}"
  run_command chown -R "${webserverUser}:${webserverUser}" "${moodleDataDir}"
  run_command chmod 0777 "${moodleDataDir}"
  run_command mkdir -p "${moodleDir}"
  run_command chown -R root:"${webserverUser}" "${moodleDir}"
  run_command chmod -R 0755 "${moodleDir}"
}

moodle_download_extract() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"
  local webserverUser="${2}"
  local moodleVersion="${3}"
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${moodleVersion}/moodle-latest-${moodleVersion}.tgz"

  # Check if Moodle directory already exists
  if [ -d "${moodleDir}" ]; then
    echo_stdout_verbose "Moodle directory ${moodleDir} already exists. Skipping download and extraction."
    return
  fi

  # Check if local download already exists
  if [ -f "moodle-latest-${moodleVersion}.tgz" ]; then
    echo_stdout_verbose "Local Moodle archive moodle-latest-${moodleVersion}.tgz already exists. Skipping download."
  else
    # Download Moodle
    echo_stdout_verbose "Downloading ${moodleArchive}"
    # Use -O to not overwrite existing file
    run_command wget -O "moodle-latest-${moodleVersion}.tgz" "${moodleArchive}"

  fi

  # Check if Moodle archive has been extracted
  if [ -d "${moodleDir}/lib" ]; then
    echo_stdout_verbose "Moodle archive has already been extracted. Skipping extraction."
  else
    # Extract Moodle
    echo_stdout_verbose "Extracting ${moodleArchive}"
    run_command mkdir -p "${moodleDir}"
    run_command tar zx -C "${moodleDir}" --strip-components 1 -f "moodle-latest-${moodleVersion}.tgz"
    run_command chown -R root:"${webserverUser}" "${moodleDir}"
    run_command chmod -R 0755 "${moodleDir}"
  fi
}

moodle_ensure() {
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

    declare -a moodle_php_extensions=("php${PHP_VERSION}-common" \
          "php${PHP_VERSION}-curl" \
          "php${PHP_VERSION}-gd" \
          "php${PHP_VERSION}-intl" \
          "php${PHP_VERSION}-json" \
          "php${PHP_VERSION}-mbstring" \
          "php${PHP_VERSION}-soap" \
          "php${PHP_VERSION}-xml" \
          "php${PHP_VERSION}-xmlrpc" \
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
          apache_create_vhost vhost_config
      fi

      if $NGINX_ENSURE; then
          nginx_create_vhost vhost_config
      fi
}


nginx_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    # Install Nginx if not already installed
    package_ensure nginx

    # Should always be true, but just in case
    if $FPM_ENSURE; then
        echo_stdout_verbose "Installing PHP FPM for Nginx..."
        package_ensure "php${PHP_VERSION}-fpm"
    fi

    # Enable and start PHP FPM
    run_command systemctl enable "php${PHP_VERSION}-fpm"
    run_command systemctl start "php${PHP_VERSION}-fpm"

    # Enable and restart Nginx
    run_command systemctl enable nginx
    run_command systemctl restart nginx

    echo_stdout_verbose "Nginx installation and configuration completed."
}

nginx_create_vhost() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    declare -n config=$1
    local logDir="${NGINX_LOG_DIR:-/var/log/nginx}"

    # Check if required configuration options are provided
    local required_options=("site-name" "document-root" "admin-email" "ssl-cert-file" "ssl-key-file")
    for option in "${required_options[@]}"; do
        if [[ -z "${config[$option]}" ]]; then
            echo_stderr "Missing required configuration option: $option"
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
    vhost_config=$(apply_template "$vhost_template" \
        "site_name=${config["site-name"]}" \
        "document_root=${config["document-root"]}" \
        "admin_email=${config["admin-email"]}" \
        "ssl_cert_file=${config["ssl-cert-file"]}" \
        "ssl_key_file=${config["ssl-key-file"]}" \
        "include_file=${config["include-file"]}"
    )

    echo "$vhost_config" > "/etc/nginx/sites-available/${config["site-name"]}.conf"
    run_command ln -s "/etc/nginx/sites-available/${config["site-name"]}.conf" "/etc/nginx/sites-enabled/"
    run_command systemctl reload nginx
}

php_verify() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    local should_exit_on_failure=${1:-false}  # Default to false

    # Check if PHP is installed
    if check_command "php"; then
        echo_stdout_verbose "PHP is installed."
        run_command php -v
    else
        echo_stdout_verbose "PHP is not installed."
        if [[ "$should_exit_on_failure" == "true" ]]; then
            exit 1
        fi
    fi
}


php_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    # Verify if PHP is already installed
    php_verify

    # If PHP is already installed, simply return
    if check_command "php"; then
        return 0
    fi

    echo_stdout_verbose "Ensuring PHP repository..."

    if [ "$DISTRO" == "Ubuntu" ]; then
      php_repository="ppa:ondrej/php"
    elif [ "$DISTRO" == "Debian" ]; then
      php_repository="deb https://packages.sury.org/php/ $CODENAME main"
    else
      echo_stderr "Unsupported distro: $DISTRO"
      exit 1
    fi

    if [ "$package_manager" == "apt" ]; then
      repository_ensure "$php_repository"
    fi

    echo_stdout_verbose "Installing PHP core..."

    if [ "$DISTRO" == "Ubuntu" ]; then
      php_package="php${PHP_VERSION}-${CODENAME}"
    elif [ "$DISTRO" == "Debian" ]; then
      php_package="php${PHP_VERSION}-${CODENAME}"
    else
      echo_stderr "Unsupported distro: $DISTRO"
      exit 1
    fi

    package_install "$php_package"

    # Verify PHP installation at end of function
    php_verify true
}



php_extensions_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
    local extensions=("$@")

    if [ ${#extensions[@]} -eq 0 ]; then
        echo_stderr "No PHP extensions provided. Aborting."
        exit 1
    fi

    package_ensure "${extensions[@]}"
}



# Main function
main() {

    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    package_manager_ensure

    if $PHP_ENSURE; then
        php_ensure
    fi

    if $APACHE_ENSURE; then
        apache_ensure
    fi

    if $NGINX_ENSURE; then
        nginx_ensure
    fi

    if $MOODLE_ENSURE; then
        moodle_ensure
    fi

}

usage() {
    echo_stdout "Usage: $0 [options]"
    echo_stdout "Options:"
    echo_stdout "  -c    Run in CI mode (no prompts)"
    echo_stdout "  -d    Database type (default: MySQL, supported: [mysql, pgsql])"
    echo_stdout "  -f    Enable FPM for the web server (requires -w apache (-w nginx sets fpm by default))"
    echo_stdout "  -h    Display this help message"
    echo_stdout "  -m    Ensure Moodle of specified version is installed (default: ${MOODLE_VERSION})"
    echo_stdout "  -M    Ensure Memcached is installed"
    echo_stdout "  -n    Dry run (show commands without executing)"
    echo_stdout "  -p    Ensure PHP of specified version is installed (default: ${PHP_VERSION})"
    echo_stdout "  -v    Enable verbose output"
    echo_stdout "  -w    Web server type (default: apache, supported: [apache, nginx])"
    echo_stdout "  Note: Options -d, -m, and -p require an argument but have defaults."
    exit 0
}

# Define a function to detect the distribution and codename
detect_distro_and_codename() {
    if command -v lsb_release &> /dev/null; then
        DISTRO="$(lsb_release -is)"
        CODENAME="$(lsb_release -sc)"
    elif [[ -f /etc/os-release ]]; then
        # Load values from /etc/os-release
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO="$ID"
        CODENAME="$VERSION_CODENAME"
    else
        echo_stderr "Unable to determine distribution."
        echo_stderr "Please run this script on a supported distribution."
        echo_stderr "Supported distributions are: Ubuntu, Debian."
        exit 1
    fi
}

# Script evaluation starts here

# Run the function to detect the distribution and codename
detect_distro_and_codename

# Make them readonly
readonly DISTRO
readonly CODENAME

# Supported distributions
SUPPORTED_DISTROS=("Ubuntu" "Debian")

is_distro_supported() {
    local distro="$1"
    for supported_distro in "${SUPPORTED_DISTROS[@]}"; do
        if [[ "$supported_distro" == "$distro" ]]; then
            return 0  # Found
        fi
    done
    return 1  # Not found
}

# ...

if ! is_distro_supported "$DISTRO"; then
    echo_stderr "Unsupported distro: $DISTRO"
    exit 1
fi



# Check if the necessary dependencies are available before proceeding
check_command --exit-on-failure tar unzip wget

# Parse command line options
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        -c|--ci)
            CI_MODE=true
            shift
            ;;

        -d|--database)
            if [[ -z "${2:-}" ]] || [[ "${2:-}" == "-"* ]]; then
                die "-d|--database option requires an argument"
            fi
            case "$2" in
                mysql|pgsql)
                    DB_TYPE="$2"
                    ;;
                *)
                    die "Unsupported database type: $2. Supported types are 'mysql' and 'pgsql'."
                    ;;
            esac
            shift 2
            ;;

        -f|--fpm)
            FPM_ENSURE=true
            shift
            ;;

        -h|--help)
            usage
            ;;

        -M|--memcached)
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
                        die "Invalid mode for Memcached: $2. Supported modes are 'local' and 'network'."
                        ;;
                esac
                shift
            fi
            shift
            ;;

        -m|--moodle)
            MOODLE_ENSURE=true
            MOODLE_VERSION="${2:-$DEFAULT_MOODLE_VERSION}"
            shift 2
            ;;

        -n|--nop)
            DRY_RUN=true
            shift
            ;;

        -p|--php)
            PHP_ENSURE=true
            PHP_VERSION="${2:-$DEFAULT_PHP_VERSION}"
            shift 2
            ;;

        -s|--sudo)
            USE_SUDO=true
            shift
            ;;

        -v|--verbose)
            VERBOSE=true
            shift
            ;;

        -w|--web)
            if [[ -z "${2:-}" ]] || [[ "${2:-}" == "-"* ]]; then
                die "-w|--web option requires an argument"
            fi
            case "$2" in
                apache)
                    APACHE_ENSURE=true
                    ;;
                nginx)
                    APACHE_ENSURE=false
                    NGINX_ENSURE=true
                    FPM_ENSURE=true
                    ;;
                *)
                    die "Unsupported web server type: $2. Supported types are 'apache' and 'nginx'."
                    ;;
            esac
            shift 2
            ;;

        *)
            # unknown option
            die "Unknown option: $1"
            ;;
    esac
done



# If not in CI mode, do the sudo checks
if ! $CI_MODE; then
    # Check if user is root
    if [[ $EUID -eq 0 ]]; then
        USE_SUDO=false
    else
        # Check if sudo is available and the user has sudo privileges
        if $USE_SUDO && ! command -v sudo &>/dev/null; then
            echo_stderr "sudo command not found. Please run as root or install sudo."
            exit 1
        elif $USE_SUDO && ! sudo -n true 2>/dev/null; then
            echo_stderr "This script requires sudo privileges. Please run as root or with a user that has sudo privileges."
            exit 1
        fi
    fi
else
    # In CI mode, use sudo if not root
    if [[ $EUID -ne 0 ]]; then
        USE_SUDO=true
    else
        USE_SUDO=false
    fi
fi


  # Checking if -f is selected on its own without -w apache
  if [[ "${FPM_ENSURE}" == "true" && "${APACHE_ENSURE}" != "true" && "${NGINX_ENSURE}" != "true" ]]; then
      echo_stderr "Option -f requires either -w apache or -w nginx to be selected."
      usage
  fi

  if $VERBOSE; then
      chosen_options=""

      if [[ -n "${DB_TYPE}" ]]; then chosen_options+="-d: Database type set to ${DB_TYPE}, "; fi
      if $FPM_ENSURE; then chosen_options+="-f: Ensure FPM for web servers, "; fi
      if $MOODLE_ENSURE; then chosen_options+="-m: Ensure Moodle version $MOODLE_VERSION, "; fi
      if $MEMCACHED_ENSURE; then
          chosen_options+="-M: Ensure Memcached support, "
          if [[ "$MEMCACHED_MODE" == "local" ]]; then
              chosen_options+="Ensure local Memcached instance, "
          fi
      fi
      if $DRY_RUN; then chosen_options+="-n: DRY RUN, "; fi
      if $PHP_ENSURE; then chosen_options+="-p: Ensure PHP version $PHP_VERSION, "; fi
      if $APACHE_ENSURE; then chosen_options+="-w: Webserver type set to Apache, "; fi
      if $NGINX_ENSURE; then chosen_options+="-w: Webserver type set to Nginx, "; fi
      chosen_options="${chosen_options%, }"

      echo_stdout_verbose "Chosen options: ${chosen_options}"
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

