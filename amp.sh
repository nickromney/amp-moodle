#!/bin/bash

# Helper functions

checkIsCommandAvailable() {
    local commandToCheck="$1"
    if command -v "${commandToCheck}" &> /dev/null
    then
        echo "${commandToCheck} command available"
    else
        # propagate error to caller
        return $?
    fi
}

checkPrivileges() {
    if [ "$(id -u)" != 0 ]
    then
        echo "script needs to be run as root user" >&2
    fi
}

updatePackageRepositories() {
	echo "Updating package repositories"
	sudo apt -qq update
}

# Main functions

phpGetVersion() {
	# Extract installed PHP version
	PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
    echo "PHP version is ${PHP_VERSION}"
}

phpInstall() {
    if ! checkIsCommandAvailable php
    then
        echo "PHP is not yet available. Starting installation of PHP"
	    apt -qy install php
    fi
}

phpListModules() {
    if ! checkIsCommandAvailable php
    then
        echo "PHP is not yet available. Exiting."
	    exit
    else
        echo "List all compiled PHP modules"
        php -m
        echo "List all PHP modules installed by package manager"
        dpkg --get-selections | grep -i php
    fi


}

checkPrivileges
updatePackageRepositories
phpInstall
phpGetVersion
phpListModules
