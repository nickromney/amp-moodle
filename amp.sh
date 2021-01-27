#!/usr/bin/env bash
# This file:
#
#  - Install Apache MySQL PHP on Ubuntu
#
# Usage:
#
#  LOG_LEVEL=7 ./main.sh -f /tmp/x -x (change this for your script)
#
# Based on a template by BASH3 Boilerplate v2.4.1
# http://bash3boilerplate.sh/#authors
#
# The MIT License (MIT)
# Copyright (c) 2013 Kevin van Zonneveld and contributors
# You are not obligated to bundle the LICENSE file with your b3bp projects as long
# as you leave these references intact in the header comments of your source files.

# Exit on error. Append "|| true" if you expect an error.
set -o errexit
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

# Set locale to avoid issues with apt-get
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8

ENSURE_BINARIES='false'

DRY_RUN='false'
ENSURE_BINARIES='false'
ENSURE_FPM='false'
ENSURE_LOCAL_DATABASE_SERVER='false'
ENSURE_MOODLE='false'
ENSURE_PHP='false'
ENSURE_REPOSITORIES='false'
ENSURE_ROLES='false'
ENSURE_SSL='false'
ENSURE_VIRTUALHOST='false'
ENSURE_WEBSERVER='false'
SHOW_USAGE='false'
VERBOSE='false'
DATABASE_ENGINE='mariadb'
SSL_ENGINE='openssl'
WEBSERVER_ENGINE='apache'

# Used internally by the script
DATABASE_ENGINE_OPTIONS='mariadb mysql'
SSL_ENGINE_OPTIONS='openssl ubuntusnakeoil'
WEBSERVER_ENGINE_OPTIONS='apache nginx nginxproxyingapache'
USER_REQUIRES_PASSWORD_TO_SUDO='true'
NON_ROOT_USER='true'


if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  __i_am_main_script="0" # false

  if [[ "${__usage+x}" ]]; then
    if [[ "${BASH_SOURCE[1]}" = "${0}" ]]; then
      __i_am_main_script="1" # true
    fi

    __b3bp_external_usage="true"
    __b3bp_tmp_source_idx=1
  fi
else
  __i_am_main_script="1" # true
  [[ "${__usage+x}" ]] && unset -v __usage
  [[ "${__helptext+x}" ]] && unset -v __helptext
fi

# Set magic variables for current file, directory, os, etc.
__dir="$(cd "$(dirname "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")" && pwd)"
__file="${__dir}/$(basename "${BASH_SOURCE[${__b3bp_tmp_source_idx:-0}]}")"
__base="$(basename "${__file}" .sh)"
# shellcheck disable=SC2034,SC2015
__invocation="$(printf %q "${__file}")$( (($#)) && printf ' %q' "$@" || true)"

# Define the environment variables (and their defaults) that this script depends on
LOG_LEVEL="${LOG_LEVEL:-6}" # 7 = debug -> 0 = emergency
NO_COLOR="${NO_COLOR:-}"    # true = disable color. otherwise autodetected


### Functions
##############################################################################

function __b3bp_log () {
  local log_level="${1}"
  shift

  # shellcheck disable=SC2034
  local color_debug="\\x1b[35m"
  # shellcheck disable=SC2034
  local color_info="\\x1b[32m"
  # shellcheck disable=SC2034
  local color_notice="\\x1b[34m"
  # shellcheck disable=SC2034
  local color_warning="\\x1b[33m"
  # shellcheck disable=SC2034
  local color_error="\\x1b[31m"
  # shellcheck disable=SC2034
  local color_critical="\\x1b[1;31m"
  # shellcheck disable=SC2034
  local color_alert="\\x1b[1;37;41m"
  # shellcheck disable=SC2034
  local color_emergency="\\x1b[1;4;5;37;41m"

  local colorvar="color_${log_level}"

  local color="${!colorvar:-${color_error}}"
  local color_reset="\\x1b[0m"

  if [[ "${NO_COLOR:-}" = "true" ]] || { [[ "${TERM:-}" != "xterm"* ]] && [[ "${TERM:-}" != "screen"* ]]; } || [[ ! -t 2 ]]; then
    if [[ "${NO_COLOR:-}" != "false" ]]; then
      # Don't use colors on pipes or non-recognized terminals
      color=""; color_reset=""
    fi
  fi

  # all remaining arguments are to be printed
  local log_line=""

  while IFS=$'\n' read -r log_line; do
    echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${color_reset} ${log_line}" 1>&2
  done <<< "${@:-}"
}

function emergency () {                                __b3bp_log emergency "${@}"; exit 1; }
function alert ()     { [[ "${LOG_LEVEL:-0}" -ge 1 ]] && __b3bp_log alert "${@}"; true; }
function critical ()  { [[ "${LOG_LEVEL:-0}" -ge 2 ]] && __b3bp_log critical "${@}"; true; }
function error ()     { [[ "${LOG_LEVEL:-0}" -ge 3 ]] && __b3bp_log error "${@}"; true; }
function warning ()   { [[ "${LOG_LEVEL:-0}" -ge 4 ]] && __b3bp_log warning "${@}"; true; }
function notice ()    { [[ "${LOG_LEVEL:-0}" -ge 5 ]] && __b3bp_log notice "${@}"; true; }
function info ()      { [[ "${LOG_LEVEL:-0}" -ge 6 ]] && __b3bp_log info "${@}"; true; }
function debug ()     { [[ "${LOG_LEVEL:-0}" -ge 7 ]] && __b3bp_log debug "${@}"; true; }

function help () {
  echo "" 1>&2
  echo " ${*}" 1>&2
  echo "" 1>&2
  echo "  ${__usage:-No usage available}" 1>&2
  echo "" 1>&2

  if [[ "${__helptext:-}" ]]; then
    echo " ${__helptext}" 1>&2
    echo "" 1>&2
  fi

  exit 1
}

apache_ensure_present() {
  system_packages_ensure apache2
  service_enable apache2
  service_start apache2
}

apache_get_status() {
  info "Apache - get service status"
  service_action status apache2
  info "Apache - get version"
  run_command apache2 -V
  info "Apache - list loaded/enabled modules"
  run_command apache2ctl -M
  info "Apache - list enabled sites"
  run_command apachectl -S
  info "Apache - check configuration files for errors"
  run_command apache2ctl -t
}

apache_php_integration() {
  php_get_version
  if ${ENSURE_FPM}; then
    info "Enabling Apache modules and config for ENSURE_FPM."
    run_command a2enmod proxy_fcgi setenvif
    run_command a2enconf "php${DISCOVERED_PHP_VERSION}-fpm"
    system_packages_ensure "libapache2-mod-fcgid"
  else
    info "ENSURE_FPM is not required."
    system_packages_ensure "libapache2-mod-php${DISCOVERED_PHP_VERSION}"
  fi
}

check_is_command_available() {
  local commandToCheck="$1"
  if command -v "${commandToCheck}" &> /dev/null; then
    info "${commandToCheck} command available"
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
  info "Test if UID is 0 (root)"
  if [[ "${UID}" -eq 0 ]]; then
    info "Setting NON_ROOT_USER to true"
    NON_ROOT_USER='true'
  fi
  info "UID value: ${UID}"
  info "NON_ROOT_USER value: ${NON_ROOT_USER}"
}

check_user_can_sudo_without_password_entry() {

  info "Test if user can sudo without entering a password"
  if sudo -v &> /dev/null; then
    USER_REQUIRES_PASSWORD_TO_SUDO='false'
    info "USER_REQUIRES_PASSWORD_TO_SUDO value: ${USER_REQUIRES_PASSWORD_TO_SUDO}"
    return 0
  else
    info "USER_REQUIRES_PASSWORD_TO_SUDO value: ${USER_REQUIRES_PASSWORD_TO_SUDO}"
    return 1
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
  local moodleArchive="https://download.moodle.org/download.php/direct/stable${MOODLE_VERSION}/moodle-latest-${MOODLE_VERSION}.tgz"
  info "Downloading and extracting ${moodleArchive}"
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
  DISCOVERED_PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
  info "PHP version is ${DISCOVERED_PHP_VERSION}"
}

php_ensure_present() {

  if ! check_is_command_available php; then
    echo "PHP is not yet available. Adding."
    phpModulesToEnsure=("${phpModulesToEnsure[@]}" "php")
  else
    info "PHP is already available"
  fi
  if check_is_true "${ENSURE_FPM}"; then
    phpModulesToEnsure=("${phpModulesToEnsure[@]}" "libapache2-mod-fcgid")
  else
    phpModulesToEnsure=("${phpModulesToEnsure[@]}" "libapache2-mod-php${DISCOVERED_PHP_VERSION}")
  fi
  system_repositories_ensure ppa:ondrej/php
  phpModulesToEnsure=("${phpModulesToEnsure[@]}" "${DISCOVERED_PHP_VERSION}-common")
  system_packages_ensure "${phpModulesToEnsure[@]}"
  if check_is_true "${ENSURE_FPM}"; then
    localServiceName="php${DISCOVERED_PHP_VERSION}-fpm"
  info "Starting ${localServiceName}"
    service_start "${localServiceName}"
  fi
}

php_get_status() {

  if ! check_is_command_available php; then
    error "PHP is not yet available. Exiting."
    exit
  else
    info "List all compiled PHP modules"
    php -m
  info "List all PHP modules installed by package manager"
    dpkg --get-selections | grep -i php
  fi
}

run_command() {
  if [[ ! -t 0 ]]; then
    cat
  fi
  printf -v cmd_str '%q ' "$@"
  if check_is_true "${DRY_RUN}"; then
    info "DRY RUN: Not executing: ${SUDO}${cmd_str}"
  else
    if check_is_true "${VERBOSE}"; then
      info "Preparing to execute: ${SUDO}${cmd_str}"
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
  local packagesToEnsure=("$@")
  for package in "${packagesToEnsure[@]}"; do
    info "Ensuring presence of package ${package}"
    apt -qq list "${package}" --installed
    # Install if not present, but don't upgrade if present
    run_command apt-get -qy install --no-upgrade "${package}"
  done
}

system_repositories_ensure() {
  local repositoriesToEnsure=("$@")
  for repository in "${repositoriesToEnsure[@]}"; do
    info "Ensuring repository ${repository}"
    run_command add-apt-repository "${repository}"
  done
}

system_packages_repositories_update() {
  info "Updating package repositories"
  run_command apt-get -qq update
}



### Parse commandline options
##############################################################################

# Commandline options. This defines the usage page, and is used to parse cli
# opts & defaults from. The parsing is unforgiving so be precise in your syntax
# - A short option must be preset for every long option; but every short option
#   need not have a long option
# - `--` is respected as the separator between options and arguments
# - We do not bash-expand defaults, so setting '~/app' as a default will not resolve to ${HOME}.
#   you can use bash variables to work around this (so use ${HOME} instead)

# shellcheck disable=SC2015
[[ "${__usage+x}" ]] || read -r -d '' __usage <<-'EOF' || true # exits non-zero when EOF encountered
  -B --binary     [arg] Ensure binary is present. Specify binary name. Can be repeated.
  -d --database         Ensure database server is installed locally. Uses --dbengine argumentoption
  -D --dbengine   [arg] Specify database engine for connections. Default="mysql"
  -h --help             This page
  -n --dryrun           Enable dry run mode (do not make changes)
  -N --no-color         Disable color output
  -m --moodle     [arg] Ensure Moodle is present. Specify version.
  -M --moodleopt  [arg] Add Moodle option. [installdb|moosh|memcached|localmemcached]. Can be repeated.
  -p --php        [arg] Ensure PHP is present. Specify version [7.4|8.0]
  -P --phpmod     [arg] Ensure PHP module is present. Can be repeated.
  -R --repository [arg] Ensure Package repository is present. Can be repeated.
  -s --ssl        [arg] Ensure SSL is used. Specify provider [openssl|ubuntusnakeoil].
  -v --verbose          Enable verbose mode, print script as it is executed
  -w --webserver  [arg] Ensure webserver is present. Specify engine.
  -W --webroot    [arg] Specify webroot
  -x --debug            Enables debug mode
EOF

# shellcheck disable=SC2015
[[ "${__helptext+x}" ]] || read -r -d '' __helptext <<-'EOF' || true # exits non-zero when EOF encountered
 Install a LAMP stack on Ubuntu to be used for Moodle
 Examples
 amp.sh -w apache -f
    Install Apache, plus FPM
 amp.sh -w apache -f php 7.4 -D mysql -m 3.9
    Install Apache, PHP. Use Mysql in Moodle 3.9 connection
EOF

# Translate usage string -> getopts arguments, and set $arg_<flag> defaults
while read -r __b3bp_tmp_line; do
  if [[ "${__b3bp_tmp_line}" =~ ^- ]]; then
    # fetch single character version of option string
    __b3bp_tmp_opt="${__b3bp_tmp_line%% *}"
    __b3bp_tmp_opt="${__b3bp_tmp_opt:1}"

    # fetch long version if present
    __b3bp_tmp_long_opt=""

    if [[ "${__b3bp_tmp_line}" = *"--"* ]]; then
      __b3bp_tmp_long_opt="${__b3bp_tmp_line#*--}"
      __b3bp_tmp_long_opt="${__b3bp_tmp_long_opt%% *}"
    fi

    # map opt long name to+from opt short name
    printf -v "__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}" '%s' "${__b3bp_tmp_opt}"
    printf -v "__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt}" '%s' "${__b3bp_tmp_long_opt//-/_}"

    # check if option takes an argument
    if [[ "${__b3bp_tmp_line}" =~ \[.*\] ]]; then
      __b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
      __b3bp_tmp_init=""  # it has an arg. init with ""
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "1"
    elif [[ "${__b3bp_tmp_line}" =~ \{.*\} ]]; then
      __b3bp_tmp_opt="${__b3bp_tmp_opt}:" # add : if opt has arg
      __b3bp_tmp_init=""  # it has an arg. init with ""
      # remember that this option requires an argument
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
    else
      __b3bp_tmp_init="0" # it's a flag. init with 0
      printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "0"
    fi
    __b3bp_tmp_opts="${__b3bp_tmp_opts:-}${__b3bp_tmp_opt}"

    if [[ "${__b3bp_tmp_line}" =~ ^Can\ be\ repeated\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Can\ be\ repeated\. ]]; then
      # remember that this option can be repeated
      printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "1"
    else
      printf -v "__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}" '%s' "0"
    fi
  fi

  [[ "${__b3bp_tmp_opt:-}" ]] || continue

  if [[ "${__b3bp_tmp_line}" =~ ^Default= ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Default= ]]; then
    # ignore default value if option does not have an argument
    __b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}"
    if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
      # take default
      __b3bp_tmp_init="${__b3bp_tmp_line##*Default=}"
      # strip double quotes from default argument
      __b3bp_tmp_re='^"(.*)"$'
      if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
        __b3bp_tmp_init="${BASH_REMATCH[1]}"
      else
        # strip single quotes from default argument
        __b3bp_tmp_re="^'(.*)'$"
        if [[ "${__b3bp_tmp_init}" =~ ${__b3bp_tmp_re} ]]; then
          __b3bp_tmp_init="${BASH_REMATCH[1]}"
        fi
      fi
    fi
  fi

  if [[ "${__b3bp_tmp_line}" =~ ^Required\. ]] || [[ "${__b3bp_tmp_line}" =~ \.\ *Required\. ]]; then
    # remember that this option requires an argument
    printf -v "__b3bp_tmp_has_arg_${__b3bp_tmp_opt:0:1}" '%s' "2"
  fi

  # Init var with value unless it is an array / a repeatable
  __b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
  [[ "${!__b3bp_tmp_varname}" = "0" ]] && printf -v "arg_${__b3bp_tmp_opt:0:1}" '%s' "${__b3bp_tmp_init}"
done <<< "${__usage:-}"

# run getopts only if options were specified in __usage
if [[ "${__b3bp_tmp_opts:-}" ]]; then
  # Allow long options like --this
  __b3bp_tmp_opts="${__b3bp_tmp_opts}-:"

  # Reset in case getopts has been used previously in the shell.
  OPTIND=1

  # start parsing command line
  set +o nounset # unexpected arguments will cause unbound variables
                 # to be dereferenced
  # Overwrite $arg_<flag> defaults with the actual CLI options
  while getopts "${__b3bp_tmp_opts}" __b3bp_tmp_opt; do
    [[ "${__b3bp_tmp_opt}" = "?" ]] && help "Invalid use of script: ${*} "

    if [[ "${__b3bp_tmp_opt}" = "-" ]]; then
      # OPTARG is long-option-name or long-option=value
      if [[ "${OPTARG}" =~ .*=.* ]]; then
        # --key=value format
        __b3bp_tmp_long_opt=${OPTARG/=*/}
        # Set opt to the short option corresponding to the long option
        __b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${__b3bp_tmp_long_opt//-/_}"
        printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
        OPTARG=${OPTARG#*=}
      else
        # --key value format
        # Map long name to short version of option
        __b3bp_tmp_varname="__b3bp_tmp_opt_long2short_${OPTARG//-/_}"
        printf -v "__b3bp_tmp_opt" '%s' "${!__b3bp_tmp_varname}"
        # Only assign OPTARG if option takes an argument
        __b3bp_tmp_varname="__b3bp_tmp_has_arg_${__b3bp_tmp_opt}"
        __b3bp_tmp_varvalue="${!__b3bp_tmp_varname}"
        [[ "${__b3bp_tmp_varvalue}" != "0" ]] && __b3bp_tmp_varvalue="1"
        printf -v "OPTARG" '%s' "${@:OPTIND:${__b3bp_tmp_varvalue}}"
        # shift over the argument if argument is expected
        ((OPTIND+=__b3bp_tmp_varvalue))
      fi
      # we have set opt/OPTARG to the short value and the argument as OPTARG if it exists
    fi

    __b3bp_tmp_value="${OPTARG}"

    __b3bp_tmp_varname="__b3bp_tmp_is_array_${__b3bp_tmp_opt:0:1}"
    if [[ "${!__b3bp_tmp_varname}" != "0" ]]; then
      # repeatables
      # shellcheck disable=SC2016
      if [[ -z "${OPTARG}" ]]; then
        # repeatable flags, they increcemnt
        __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
        debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
          # shellcheck disable=SC2004
        __b3bp_tmp_value=$((${!__b3bp_tmp_varname} + 1))
        printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"
      else
        # repeatable args, they get appended to an array
        __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}[@]"
        debug "cli arg ${__b3bp_tmp_varname} append ${__b3bp_tmp_value}"
        declare -a "${__b3bp_tmp_varname}"='("${!__b3bp_tmp_varname}" "${__b3bp_tmp_value}")'
      fi
    else
      # non-repeatables
      __b3bp_tmp_varname="arg_${__b3bp_tmp_opt:0:1}"
      __b3bp_tmp_default="${!__b3bp_tmp_varname}"

      if [[ -z "${OPTARG}" ]]; then
        __b3bp_tmp_value=$((__b3bp_tmp_default + 1))
      fi

      printf -v "${__b3bp_tmp_varname}" '%s' "${__b3bp_tmp_value}"

      debug "cli arg ${__b3bp_tmp_varname} = (${__b3bp_tmp_default}) -> ${!__b3bp_tmp_varname}"
    fi
  done
  set -o nounset # no more unbound variable references expected

  shift $((OPTIND-1))

  if [[ "${1:-}" = "--" ]] ; then
    shift
  fi
fi


### Automatic validation of required option arguments
##############################################################################

for __b3bp_tmp_varname in ${!__b3bp_tmp_has_arg_*}; do
  # validate only options which required an argument
  [[ "${!__b3bp_tmp_varname}" = "2" ]] || continue

  __b3bp_tmp_opt_short="${__b3bp_tmp_varname##*_}"
  __b3bp_tmp_varname="arg_${__b3bp_tmp_opt_short}"
  [[ "${!__b3bp_tmp_varname}" ]] && continue

  __b3bp_tmp_varname="__b3bp_tmp_opt_short2long_${__b3bp_tmp_opt_short}"
  printf -v "__b3bp_tmp_opt_long" '%s' "${!__b3bp_tmp_varname}"
  [[ "${__b3bp_tmp_opt_long:-}" ]] && __b3bp_tmp_opt_long=" (--${__b3bp_tmp_opt_long//_/-})"

  help "Option -${__b3bp_tmp_opt_short}${__b3bp_tmp_opt_long:-} requires an argument"
done


### Cleanup Environment variables
##############################################################################

for __tmp_varname in ${!__b3bp_tmp_*}; do
  unset -v "${__tmp_varname}"
done

unset -v __tmp_varname


### Externally supplied __usage. Nothing else to do here
##############################################################################

if [[ "${__b3bp_external_usage:-}" = "true" ]]; then
  unset -v __b3bp_external_usage
  return
fi


### Signal trapping and backtracing
##############################################################################

function __b3bp_cleanup_before_exit () {
  info "Cleaning up. Done"
}
trap __b3bp_cleanup_before_exit EXIT

# requires `set -o errtrace`
__b3bp_err_report() {
    local error_code=${?}
    error "Error in ${__file} in function ${1} on line ${2}"
    exit ${error_code}
}
# Uncomment the following line for always providing an error backtrace
# trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR


### Command-line argument switches (like -x for debugmode, -h for showing helppage)
##############################################################################

if [[ -n "${arg_B:-}" ]]; then
  ENSURE_BINARIES="true"
fi

if [[ -n "${arg_R:-}" ]]; then
  ENSURE_REPOSITORIES="true"
fi

# help mode
if [[ "${arg_h:?}" = "1" ]]; then
  # Help exists with code 1
  help "Help using ${0}"
fi

# no color mode
if [[ "${arg_N:?}" = "1" ]]; then
  NO_COLOR="true"
fi

# verbose mode
if [[ "${arg_v:?}" = "1" ]]; then
  set -o verbose
fi

# debug mode
if [[ "${arg_x:?}" = "1" ]]; then
  set -o xtrace
  PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
  LOG_LEVEL="7"
  # Enable error backtracing
  trap '__b3bp_err_report "${FUNCNAME:-.}" ${LINENO}' ERR
fi

### Validation. Error out if the things required for your script are not present
##############################################################################

[[ "${LOG_LEVEL:-}" ]] || emergency "Cannot continue without LOG_LEVEL. "


### Runtime
##############################################################################

info "__i_am_main_script: ${__i_am_main_script}"
info "__file: ${__file}"
info "__dir: ${__dir}"
info "__base: ${__base}"
info "OSTYPE: ${OSTYPE}"

if [[ -n "${arg_B:-}" ]]; then
  info "arg_B: ${#arg_B[@]}"
  for binary in "${arg_B[@]}"; do
    info " - ${binary}"
  done
else
  info "arg_B: 0"
fi
info "arg_d: ${arg_d}"
info "arg_D: ${arg_D}"
info "arg_h: ${arg_h}"
info "arg_n: ${arg_n}"
info "arg_N: ${arg_N}"
info "arg_m: ${arg_m}"
if [[ -n "${arg_M:-}" ]]; then
  info "arg_M: ${#arg_M[@]}"
  for moodle_option in "${arg_M[@]}"; do
    info " - ${moodle_option}"
  done
else
  info "arg_M: 0"
fi
info "arg_p: ${arg_p}"
if [[ -n "${arg_P:-}" ]]; then
  info "arg_P: ${#arg_P[@]}"
  for php_module in "${arg_P[@]}"; do
    info " - ${php_module}"
  done
else
  info "arg_P: 0"
fi
if [[ -n "${arg_R:-}" ]]; then
  info "arg_R: ${#arg_R[@]}"
  for repository in "${arg_R[@]}"; do
    info " - ${repository}"
  done
else
  info "arg_R: 0"
fi
info "arg_s: ${arg_s}"
info "arg_v: ${arg_v}"
info "arg_w: ${arg_w}"
info "arg_W: ${arg_W}"
info "arg_x: ${arg_x}"

#info "$(echo -e "multiple lines example - line #1\\nmultiple lines example - line #2\\nimagine logging the output of 'ls -al /path/'")"
# All of these go to STDERR, so you can use STDOUT for piping machine readable information to other software
# debug "Info useful to developers for debugging the application, not useful during operations."
# info "Normal operational messages - may be harvested for reporting, measuring throughput, etc. - no action required."
# notice "Events that are unusual but not error conditions - might be summarized in an email to developers or admins to spot potential problems - no immediate action required."
# warning "Warning messages, not an error, but indication that an error will occur if action is not taken, e.g. file system 85% full - each item must be resolved within a given time. This is a debug message"
# error "Non-urgent failures, these should be relayed to developers or admins; each item must be resolved within a given time."
# critical "Should be corrected immediately, but indicates failure in a primary system, an example is a loss of a backup ISP connection."
# alert "Should be corrected immediately, therefore notify staff who can fix the problem. An example would be the loss of a primary ISP connection."
# emergency "A \"panic\" condition usually affecting multiple apps/servers/sites. At this level it would usually notify all tech staff on call."

### Main logic

  check_user_is_root
  if check_is_true "${NON_ROOT_USER}"; then
    check_user_can_sudo_without_password_entry
    if check_is_true "${USER_REQUIRES_PASSWORD_TO_SUDO}"; then
      error "User requires a password to issue sudo commands. Exiting"
      error "Please re-run the script as root, or having sudo'd with a password"
      usage
      exit 1
    else
      SUDO='sudo '
      info "User can issue sudo commands without entering a password. Continuing"
    fi
  fi

  if check_is_true "${ENSURE_BINARIES}"; then
    for binary in "${arg_B[@]}"; do
      system_packages_ensure "${binary}"
    done
  fi
  if check_is_true "${ENSURE_REPOSITORIES}"; then
    for repository in "${arg_R[@]}"; do
      system_repositories_ensure "${repository}"
    done
  fi
  if check_is_true "${ENSURE_WEBSERVER}"; then
    system_packages_ensure apache2
    service_action enable apache2
    service_action start apache2
  fi
  if check_is_true "${ENSURE_PHP}"; then
    if ! check_is_command_available php; then
      echo "PHP is not yet available. Adding."
      phpPackagesToEnsure=("${phpPackagesToEnsure[@]}" "php")
    else
      echo_stdout_verbose "PHP is already available"
    fi
    if check_is_true "${ENSURE_FPM}"; then
      phpPackagesToEnsure=("${phpPackagesToEnsure[@]}" "libapache2-mod-fcgid")
    else
      phpPackagesToEnsure=("${phpPackagesToEnsure[@]}" "libapache2-mod-php${DISCOVERED_PHP_VERSION}")
    fi
    system_repositories_ensure ppa:ondrej/php
    phpPackagesToEnsure=("${phpPackagesToEnsure[@]}" "${DISCOVERED_PHP_VERSION}-common")
    for phpPackage in "${phpPackagesToEnsure[@]}"; do
      system_packages_ensure "${phpPackage}"
    done
    if check_is_true "${ENSURE_FPM}"; then
      localServiceName="php${DISCOVERED_PHP_VERSION}-fpm"
    echo_stdout_verbose "Starting ${localServiceName}"
      service_action start "${localServiceName}"
    fi
  fi
  if check_is_true "${ENSURE_LOCAL_DATABASE_SERVER}"; then
    info "Install local database server"
  fi
  if check_is_true "${ENSURE_SSL}"; then
    info "Ensure SSL"
  fi
  if check_is_true "${ENSURE_VIRTUALHOST}"; then
    info "Ensure Virtualhost"
  fi
  if check_is_true "${ENSURE_MOODLE}"; then
    info "Ensure Moodle"
  fi
