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

phpInstall() {
    if ! checkIsCommandAvailable php
    then
        echo "PHP is not yet available. Starting installation of PHP"
	    apt -qy install php
    fi
}

phpInstall
