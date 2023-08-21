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
check_is_command_available() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local commandToCheck="${1:-}"
  if [[ -z "${commandToCheck}" ]]; then
    echo_stderr "Error: Null input received"
    return 1
  fi
  if command -v "${commandToCheck}" &> /dev/null; then
    echo_stdout_verbose "${commandToCheck} command available"
  else
    # propagate error to caller
    return $?
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
  local prefix=""

  # If DRY RUN mode is active, prefix the message

  if [[ "${DRY_RUN}" == "true" ]]; then
      prefix="DRY RUN: "
  fi

  if [[ "${VERBOSE}" == "true" ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: VERBOSE: ${prefix}${message}" >&1
  fi
}

package_ensure() {
    local no_install_recommends_flag=""
    if [ "$1" == "--no-install-recommends" ]; then
        no_install_recommends_flag="--no-install-recommends"
        shift
    fi

    local packages=("$@")
    local missing_packages=()

    for package in "${packages[@]}"
    do
        if [ "$package_manager" == "brew list" ]; then
            # Using brew, the package is missing if the command fails
            if ! brew list "$package" >/dev/null 2>&1; then
                missing_packages+=("$package")
            fi
        else
            # For other package managers, use the generic approach
            if ! $package_manager "$package" >/dev/null 2>&1; then
                missing_packages+=("$package")
            fi
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo_stdout_verbose "Installing missing packages: ${missing_packages[*]}"
        if [ "$package_manager" == "dpkg -s" ]; then
            run_command apt update
            run_command apt install --yes $no_install_recommends_flag "${missing_packages[@]}"
        elif [ "$package_manager" == "rpm -q" ]; then
            run_command yum update -y
            run_command yum install -y $no_install_recommends_flag "${missing_packages[@]}"
        elif [ "$package_manager" == "brew list" ]; then
            for package in "${missing_packages[@]}"; do
                run_command brew install "$package"
            done
        fi
    else
        echo_stdout_verbose "All packages are already installed."
    fi
}

package_manager_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
    if command -v dpkg >/dev/null 2>&1; then
        package_manager="dpkg -s"
    elif command -v rpm >/dev/null 2>&1; then
        package_manager="rpm -q"
    elif command -v brew >/dev/null 2>&1; then
        package_manager="brew list"
    else
        echo_stderr "Error: Package manager not found."
        exit 1
    fi
}

repository_ensure() {
    if [ "$package_manager" == "brew list" ]; then
        echo_stdout_verbose "Homebrew does not require repository addition. Skipping."
        return
    fi

    local repositories=("$@")
    local missing_repositories=()

    if [ "$package_manager" == "dpkg -s" ]; then
        for repository in "${repositories[@]}"
        do
            if ! grep -q "^deb .*$repository" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
                missing_repositories+=("$repository")
            fi
        done
    elif [ "$package_manager" == "rpm -q" ]; then
        for repository in "${repositories[@]}"
        do
            if ! yum repolist all | grep -q "$repository"; then
                missing_repositories+=("$repository")
            fi
        done
    fi

    if [ ${#missing_repositories[@]} -gt 0 ]; then
        echo_stdout_verbose "Adding missing repositories: ${missing_repositories[*]}"
        if [ "$package_manager" == "dpkg -s" ]; then
            for repository in "${missing_repositories[@]}"
            do
                run_command add-apt-repository "$repository"
            done
            run_command apt update
        elif [ "$package_manager" == "rpm -q" ]; then
            for repository in "${missing_repositories[@]}"
            do
                run_command yum-config-manager --add-repo "$repository"
            done
            run_command yum update -y
        fi
    else
        echo_stdout_verbose "All repositories are already added."
    fi
}


replace_file_value() {
    local current_value="$1"
    local new_value="$2"
    local file_path="$3"

    if [ -f "$file_path" ]; then
        run_command sed -i "s|$current_value|$new_value|" "$file_path"
        echo_stdout_verbose "Replaced $current_value with $new_value in $file_path"
    fi
}

run_command() {
    if [[ ! -t 0 ]]; then
        cat
    fi

    printf -v cmd_str '%q ' "$@"

    # Decide whether to use sudo based on the command and global USE_SUDO setting
    local cmd_prefix=""
    if $USE_SUDO && [[ "$1" != "brew" ]]; then
        cmd_prefix="sudo "
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        echo_stdout_verbose "Not executing: ${cmd_prefix}${cmd_str}"
        return
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
        echo_stdout_verbose "Preparing to execute: ${cmd_prefix}${cmd_str}"
    fi

    "${cmd_prefix}$@"
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

# Function to ensure Apache web server is installed and configured
apache_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    # Install Apache if not already installed
    package_ensure apache2

    # Ensure essential modules
    package_ensure "libapache2-mod-ssl"  # For SSL/TLS support
    package_ensure "libapache2-mod-headers"  # For HTTP header manipulation
    package_ensure "libapache2-mod-rewrite"  # For URL rewriting, useful for many web apps
    package_ensure "libapache2-mod-deflate"  # For response compression
    package_ensure "libapache2-mod-expires"  # For setting expiration HTTP headers

    # Enable essential Apache modules
    run_command a2enmod ssl
    run_command a2enmod headers
    run_command a2enmod rewrite
    run_command a2enmod deflate
    run_command a2enmod expires

    if $FPM_ENSURE; then
        echo_stdout_verbose "Installing PHP FPM..."
        package_ensure "php${PHP_VERSION}-fpm"
        package_ensure "libapache2-mod-fcgid"

        echo_stdout_verbose "Configuring Apache for FPM..."
        run_command a2enmod proxy_fcgi setenvif
        run_command a2enconf "php${PHP_VERSION}-fpm"

        run_command systemctl enable "php${PHP_VERSION}-fpm"
        run_command systemctl start "php${PHP_VERSION}-fpm"
    else
        echo_stdout_verbose "Configuring Apache without FPM..."
        package_ensure "libapache2-mod-php${PHP_VERSION}"
    fi

    # Enable and Restart Apache
    run_command systemctl enable apache2
    run_command systemctl restart apache2

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




php_ensure() {
    echo_stdout_verbose "Entered function ${FUNCNAME[0]}"

    echo_stdout_verbose "Ensuring PHP repository..."
    repository_ensure ppa:ondrej/php

    echo_stdout_verbose "Installing PHP and required extensions..."

    package_ensure --no-install-recommends "php${PHP_VERSION}"

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

    declare -a extensions=("libapache2-mod-php${PHP_VERSION}" \
        "php${PHP_VERSION}-common" \
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
        extensions+=("php${PHP_VERSION}-pgsql")
    else
        # Add php-mysqli extension for MySQL and MariaDB
        extensions+=("php${PHP_VERSION}-mysqli")
    fi

    package_ensure "${extensions[@]}"

    echo_stdout_verbose "Checking PHP configuration..."

    # Check PHP configuration
    run_command php -v

    # Get installed extensions and store in a file
    run_command php -m > installed_extensions.txt

    # List of required extensions
    declare -a required_extensions=("ctype" "curl" "dom" "gd" "iconv" "intl" "json" "mbstring" "openssl" "pcre" "SimpleXML" "soap" "SPL" "tokenizer" "xml" "xmlrpc" "zip")

    if [ "${DB_TYPE}" == "pgsql" ]; then
        # Add "pgsql" extension for PostgreSQL
        required_extensions+=("pgsql")
    else
        # Add "mysqli" extension for MySQL and MariaDB
        required_extensions+=("mysqli")
    fi

    # Check if required extensions are installed
    for extension in "${required_extensions[@]}"
    do
        if ! grep -q -w "$extension" installed_extensions.txt; then
            echo_stderr "PHP extension $extension is not installed."
            echo_stderr "Please install the required PHP extensions and try again."
            exit 1
        fi
    done

    echo_stdout_verbose "Required PHP extensions are already installed."
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
        exit 1
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
    run_command wget -q "${moodleArchive}"
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

# Interesting function. May not use much.
moodle_plugins() {
  echo_stdout_verbose "Entered function ${FUNCNAME[0]}"
  local moodleDir="${1}"
  local webserverUser="${2}"
  local moodleVersionSemVer="${3}"

  echo_stdout_verbose "Configuring Moodle plugins..."

  # Download and install plugins
  local plugins=(
    "mod_certificate https://github.com/moodlehq/moodle-mod_certificate/archive/refs/tags/v3.10.0.zip"
    "mod_forum https://github.com/moodle/moodle-mod_forum/archive/refs/tags/v3.10.0.zip"
    "theme_boost https://github.com/moodle/moodle-theme_boost/archive/refs/tags/v3.10.0.zip"
  )

  for plugin in "${plugins[@]}"; do
    plugin_name="${plugin%% *}"
    plugin_url="${plugin#* }"
    plugin_dir="${moodleDir}/mod/${plugin_name}"

    echo_stdout_verbose "Checking for plugin ${plugin_name}..."
    if [ ! -d "${plugin_dir}" ]; then
      echo_stdout_verbose "Plugin ${plugin_name} not found. Downloading and installing..."
      run_command mkdir -p "${plugin_dir}"
      run_command wget -qO "${plugin_name}.zip" "${plugin_url}"
      run_command unzip -q "${plugin_name}.zip" -d "${plugin_dir}"
      run_command rm "${plugin_name}.zip"
      run_command chown -R root:"${webserverUser}" "${plugin_dir}"
      run_command chmod -R 0755 "${plugin_dir}"
      echo_stdout_verbose "Plugin ${plugin_name} installed."
    else
      echo_stdout_verbose "Plugin ${plugin_name} already installed. Skipping installation."
    fi
  done

  echo_stdout_verbose "Configuration completed."
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
        return 301 https://$host$request_uri;
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
        try_files $uri $uri/ =404;
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


usage() {
    echo_stdout "Usage: $0 [options]"
    echo_stdout "Options:"
    echo_stdout "  -a    Ensure Apache web server is installed"
    echo_stdout "  -d    Database type (default: MySQL, supported: [mysql, pgsql])"
    echo_stdout "  -e    Ensure Nginx web server is installed"
    echo_stdout "  -f    Enable FPM for the web server (requires -a or -e)"
    echo_stdout "  -h    Display this help message"
    echo_stdout "  -m    Ensure Moodle of specified version is installed (default: ${MOODLE_VERSION})"
    echo_stdout "  -M    Ensure Memcached is installed"
    echo_stdout "  -n    Dry run (show commands without executing)"
    echo_stdout "  -p    Ensure PHP of specified version is installed (default: ${PHP_VERSION})"
    echo_stdout "  -v    Enable verbose output"
    echo_stdout "  Note: Options -d, -m, and -p require an argument but have defaults."
    exit 0
}

# Main function
main() {

    package_manager_ensure

    if $PHP_ENSURE; then
        php_ensure
    fi

    if $APACHE_ENSURE; then
        apache_ensure
    fi

    if $NGINX_ENSURE; then
        nginx_ensure
        nginx_configure_for_php
    fi

    if $MOODLE_ENSURE; then
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


      fi
}

# Pre-check for --ci long option
if [[ "$1" == "--ci" ]]; then
    CI_MODE=true
    shift 1  # remove the CI flag from arguments
fi

while getopts ":ad:cefhm:M::np:sv" opt; do
    case "${opt}" in
        a) APACHE_ENSURE=true ;;
        c) CI_MODE=true ;;
        d)
            case "${OPTARG}" in
                mysql|pgsql) DB_TYPE=${OPTARG} ;;
                *)
                    echo_stderr "Unsupported database type: $OPTARG. Supported types are 'mysql' and 'pgsql'."
                    usage
                    ;;
            esac
            ;;
        e) NGINX_ENSURE=true; FPM_ENSURE=true ;;
        f) FPM_ENSURE=true ;;
        h) usage ;;
        M)
            MEMCACHED_ENSURE=true
            if [[ ${OPTARG:0:1} == "-" || -z ${OPTARG} ]]; then
                MEMCACHED_MODE="network"
                if [[ ${OPTARG:0:1} == "-" ]]; then
                    OPTIND=$((OPTIND - 1))
                fi
            elif [[ ${OPTARG} == "local" ]]; then
                MEMCACHED_MODE="local"
            elif [[ ${OPTARG} == "network" ]]; then
                MEMCACHED_MODE="network"
            else
                echo_stderr "Invalid mode for Memcached: $OPTARG. Supported modes are 'local' and 'network'."
                usage
            fi
            ;;
        m)
            MOODLE_ENSURE=true
            if [[ ${OPTARG:0:1} == "-" || -z ${OPTARG} ]]; then
                MOODLE_VERSION="${DEFAULT_MOODLE_VERSION}"
                if [[ ${OPTARG:0:1} == "-" ]]; then
                    OPTIND=$((OPTIND - 1))
                fi
            else
                MOODLE_VERSION=${OPTARG}
            fi
            ;;
        n) DRY_RUN=true ;;
        p)
            PHP_ENSURE=true
            if [[ ${OPTARG:0:1} == "-" || -z ${OPTARG} ]]; then
                PHP_VERSION="${DEFAULT_PHP_VERSION}"
                if [[ ${OPTARG:0:1} == "-" ]]; then
                    OPTIND=$((OPTIND - 1))
                fi
            else
                PHP_VERSION=${OPTARG}
            fi
            ;;
        s) USE_SUDO=true ;;
        v) VERBOSE=true ;;
        \?) echo_stderr "Invalid option: -$OPTARG" >&2
            usage ;;
        :)
            # Do nothing. We're handling this in the cases for -m and -p above.
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
            echo "sudo command not found. Please run as root or install sudo."
            exit 1
        elif $USE_SUDO && ! sudo -n true 2>/dev/null; then
            echo "This script requires sudo privileges. Please run as root or with a user that has sudo privileges."
            exit 1
        fi
    fi
fi

    # Check mutual exclusivity of web servers
    if [[ "${APACHE_ENSURE}" == "true" && "${NGINX_ENSURE}" == "true" ]]; then
        echo_stderr "Options -a and -e are mutually exclusive. Please select only one web server."
        usage
    fi

    # Checking if -f is selected on its own without -a or -e
    if [[ "${FPM_ENSURE}" == "true" && "${APACHE_ENSURE}" != "true" && "${NGINX_ENSURE}" != "true" ]]; then
        echo_stderr "Option -f requires either -a or -e to be selected."
        usage
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
        chosen_options=""

        if $APACHE_ENSURE; then chosen_options+="-a: Ensure Apache web server, "; fi
        if [[ -n "${DB_TYPE}" ]]; then chosen_options+="-d: Database type set to ${DB_TYPE}, "; fi
        if $NGINX_ENSURE; then chosen_options+="-e: Ensure Nginx web server, "; fi
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

        chosen_options="${chosen_options%, }"
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

