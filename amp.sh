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

checkSudoWithoutPasswordEntry() {
    if sudo -v &> /dev/null
    then
        echo "This user is able to sudo without requiring a password"
    else
        # propagate error to caller
        return $?
    fi
}

serviceEnable() {
    local service="$1"
	sudo systemctl enable "${service}"
}

serviceReload() {
    local service="$1"
	sudo systemctl reload "${service}"
}

serviceRestart() {
    local service="$1"
	sudo systemctl restart "${service}"
}

serviceStart() {
    local service="$1"
	sudo systemctl start "${service}"
}

serviceStatus() {
    local service="$1"
	sudo systemctl status "${service}"
}

serviceStop() {
    local service="$1"
	sudo systemctl stop "${service}"
}

systemPackagesAdd() {
    local packagesToCheck="$1"
    systemPackagesUpdateRepositories
    echo "Checking presence of packages ${packagesToCheck}"
    echo "use apt list --installed"
    sudo apt -qq list "${packagesToCheck}" --installed
    # Install if not present, but don't upgrade if present
    sudo apt-get -qy install --no-upgrade "${packagesToCheck}"
}

systemPackageAddRepositories() {
    local repositoriesToAdd="$1"
    systemPackagesAdd software-properties-common
    sudo add-apt-repository "${repositoriesToAdd}"
}

systemPackagesUpdateRepositories() {
	echo "Updating package repositories"
	sudo apt-get -qq update
}

# Main functions

apacheEnsurePresent() {
    systemPackagesAdd apache2
    serviceEnable apache2
    serviceStart apache2
}

apacheStatus() {
    echo "Apache - get service status"
    serviceStatus apache2
	echo "Apache - get version"
	apache2 -V
    echo "Apache - list loaded/enabled modules"
    apache2ctl -M
    echo "Apache - list enabled sites"
    apachectl -S
    echo "Apache - check configuration files for errors"
    apache2ctl -t
}

phpGetVersion() {
	# Extract installed PHP version
	PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2 | cut -c 1-3)
    echo "PHP version is ${PHP_VERSION}"
}

phpEnsurePresent() {
    packagesToInstall=()
    if ! checkIsCommandAvailable php
    then
        echo "PHP is not yet available. Adding."
        packagesToInstall=("${packagesToInstall[@]}" "php")
    else
        echo "PHP is already available"
        phpGetVersion
    fi
    systemPackageAddRepositories ppa:ondrej/php
    packagesToInstall=("${packagesToInstall[@]}" "libapache2-mod-php${PHP_VERSION}" "${PHP_VERSION}-common")
    systemPackagesAdd "${packagesToInstall[@]}"
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

checkSudoWithoutPasswordEntry
systemPackagesUpdateRepositories
apacheEnsurePresent
apacheStatus
phpEnsurePresent
phpGetVersion
#phpListModules
