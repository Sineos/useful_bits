#!/bin/bash

# Helper to get step/step_done/try error checking
# Based on: https://stackoverflow.com/a/5196220

# Use step(), try(), and step_done() to perform a series of commands and print
# [  OK  ] or [FAILED] at the end. The step as a whole fails if any individual
# command fails.
#
# Example:
#     step "Remounting / and /boot as read-write:"
#     try mount -o remount,rw /
#     try mount -o remount,rw /boot
#     step_done

# Echo formatting
resCol=30
moveToCol="echo -en \\033[${resCol}G"
fError=$(
    tput bold
    tput setaf 1
)

fSuccess=$(
    tput bold
    tput setaf 2
)

fInfo=$(
    tput bold
    tput setaf 4
)

fWarning=$(
    tput bold
    tput setaf 3
)

fReset=$(tput sgr0)

# Function to annaounce the step_done processing step
step() {
    echo -e "${fInfo}$@${fReset}"

    STEP_OK=0
    [[ -w /tmp ]] && echo $STEP_OK >/tmp/step.$$
}

# Function to check the return code and potentially
# return an error message
try() {
    # Check for `-b' argument to run command in the background.
    local BG=

    [[ $1 == -b ]] && {
        BG=1
        shift
    }
    [[ $1 == -- ]] && { shift; }

    # Run the command.
    if [[ -z $BG ]]; then
        "$@"
    else
        "$@" &
    fi

    # Check if command failed and update $STEP_OK if so.
    local EXIT_CODE=$?

    if [[ $EXIT_CODE -ne 0 ]]; then
        STEP_OK=$EXIT_CODE
        [[ -w /tmp ]] && echo $STEP_OK >/tmp/step.$$

        if [[ -n $LOG_STEPS ]]; then
            local FILE=$(readlink -m "${BASH_SOURCE[1]}")
            local LINE=${BASH_LINENO[0]}

            echo "$FILE: line $LINE: Command \`$*' failed with exit code $EXIT_CODE." >>"$LOG_STEPS"
        fi
    fi

    return $EXIT_CODE
}

# Function to move to the next processing step and
# return a success / failure message from the just
# processed step
#
# This function uses following named arguments that can be passed:
# "doExit=success / failure / both" --> End processing with respective return code / message
# "mSuccess=..." --> Use the specified string for success, otherwise just "OK" is returned
# "mFailure=..." --> Use the specified string for an error, otherwise just "FAILED" is returned
# "mWarningS=..." --> mWarningS can be used instead of mSuccess to get a different formatting
# "mWarningF=..." --> mWarningF can be used instead of mFailure to get a different formatting
step_done() {
    # Parse function arguments in the form key=value
    # Arguments are exported and considered global to the script
    # Based on: https://unix.stackexchange.com/a/353639
    for ARGUMENT in "$@"; do
        KEY=$(echo $ARGUMENT | cut -f1 -d=)

        KEY_LENGTH=${#KEY}
        VALUE="${ARGUMENT:$KEY_LENGTH+1}"

        export "$KEY"="$VALUE"
    done

    [[ -f /tmp/step.$$ ]] && {
        STEP_OK=$(</tmp/step.$$)
        rm -f /tmp/step.$$
    }
    if [[ $STEP_OK -eq 0 ]]; then
        if [ "$mSuccess" ]; then
            echo_success "$mSuccess"
        elif [ "$mWarningS" ]; then
            echo_warning "$mWarningS"
        else
            echo_success "OK"
        fi
    else
        if [ "$mFailure" ]; then
            echo_failure "$mFailure"
        elif [ "$mWarningF" ]; then
            echo_warning "$mWarningF"
        else
            echo_failure "FAILED"
        fi
    fi
    echo

    if { [ "$doExit" = "success" ] || [ "$doExit" = "both" ]; } && [[ $STEP_OK -eq 0 ]]; then
        echo
        exit 0
    elif { [ "$doExit" = "failure" ] || [ "$doExit" = "both" ]; } && [[ $STEP_OK -ne 0 ]]; then
        echo
        exit 1
    else
        # Clear the arguments to avoid polluting
        # subsequent calls
        unset doExit
        unset mSuccess
        unset mFailure
        unset mWarningS
        unset mWarningF
        return "$STEP_OK"
    fi
}

echo_success() {
    message="$1"
    $moveToCol
    echo -n "["
    echo -n "${fSuccess}"
    echo -n "$message"
    echo -n "${fReset}"
    echo -n "]"
    echo -ne "\r"
    return 0
}

echo_failure() {
    message="$1"
    $moveToCol
    echo -n "["
    echo -n "${fError}"
    echo -n "$message"
    echo -n "${fReset}"
    echo -n "]"
    echo -ne "\r"
    return 1
}

echo_warning() {
    message="$1"
    $moveToCol
    echo -n "["
    echo -n "${fWarning}"
    echo -n "$message"
    echo -n "${fReset}"
    echo -n "]"
    echo -ne "\r"
    return 0
}

#################################################################
################ Start of the actual script #####################
#################################################################

# Function to check if the script has root rights
is_root_user() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
    return 0
}

# Function to check if we are on Debian 11
# or Debian based OS
is_debian_11() {
    if [ -f /etc/os-release ]; then
        echo -e "Debian os-release:\n" >> /tmp/debug_fix_udev.log
        os_release_content="$(cat /etc/os-release | tee -a /tmp/debug_fix_udev.log)"
        if [[ "$os_release_content" == *'VERSION_ID="11"'* ]] && { [[ "$os_release_content" == *'ID=debian'* ]] || [[ "$os_release_content" == *'ID_LIKE=debian'* ]]; }; then
            return 0
        fi
    fi
    return 1
}


delete_log() {
    if [ -f /tmp/debug_fix_udev.log ]; then
        rm -f /tmp/debug_fix_udev.log
        return 0
    fi
    return 1
}

# Get the installed udev version
get_udev_version() {
    udev_version="-1"
    echo -e "\n\nudev version:\n" >> /tmp/debug_fix_udev.log
    udev_version="$(dpkg-query --show --showformat='${Version}' udev |& tee -a /tmp/debug_fix_udev.log)"
    echo "$udev_version"
}

# Check if the udev version contains the
# buggy version string deb11u2
is_udev_version_deb11u2() {
    udev_version=$(get_udev_version)
    if [[ "$udev_version" == *deb11u2* ]]; then
        return 1
    fi
    return 0
}

get_repositories() {
    echo -e "\n\nActive repositories:\n" >> /tmp/debug_fix_udev.log
    local apt_cache_output="$(apt-cache policy 2>/dev/null |& tee -a /tmp/debug_fix_udev.log)"
    echo "$apt_cache_output"
}

# Function to check if Bullseye backports are already
# available. E.g. Armbian already has them by default
is_bullseye_backports_available() {
    local apt_cache_output=$(get_repositories)
    if echo "$apt_cache_output" | grep -q "bullseye-backports/main"; then
        return 0
    fi
    return 1
}

# Function to Download and install the Debian Bullseye key
# to sign the repository. Avoid apt-key since it is deprecated
# and considered insecure
download_bullseye_backports_key() {
    try gpg --quiet --yes -k
    try gpg --quiet --yes --no-default-keyring --keyring /tmp/keyring.gpg --keyserver keyserver.ubuntu.com --recv-key 0x73a4f27b8dd47936
    try gpg --quiet --yes --no-default-keyring --keyring /tmp/keyring.gpg --output /usr/share/keyrings/debian11-backports-archive-keyring.gpg --export
    rm /tmp/keyring.gpg*
    step_done
}

# Add the Bullseye backport repository and sign it
# with the downloaded GPG key
add_bullseye_backports_to_sources() {
    local repo_string="deb [signed-by=/usr/share/keyrings/debian11-backports-archive-keyring.gpg] http://ftp.debian.org/debian bullseye-backports main non-free contrib"
    try echo "$repo_string" >>/etc/apt/sources.list.d/bullseye-backports.list
    step_done
}

#################################################################
###################### Main #####################################
#################################################################

# Check if we are running on Debian 11
step "Checking for Debian 11 (Bullseye)"
try is_debian_11
step_done doExit="failure" mFailure="This script only works for Debian 11 and Debian 11 based Linux OS. Exiting"

# Check for root rights
step "Checking for root rights"
try is_root_user
step_done doExit="failure" mFailure="This script must be run as root. Please use sudo or run as the root user. Exiting"

# Delete old log
delete_log

# Update the system first to have
# a stable starting point. E.g. PiOS Lite (32bit)
# seems to be shipped with deb11u1 Udev
step "Update the apt repository index"
try apt -qq update
step_done doExit="failure"
step "Upgrade system (can take a while)"
try apt -qq upgrade -y
step_done doExit="failure"

# Check for buggy udev version
step "Checking for buggy udev version"
try is_udev_version_deb11u2
step_done doExit="success" mSuccess="No buggy udev found (Version: $(get_udev_version). Exiting" mWarningF="Buggy udev found (Version: $(get_udev_version))! Proceeding"

# Remedy buggy udev
step "Checking if the backports repository is already available"
if is_bullseye_backports_available; then
    echo_success "Backports already available"
    echo
    step "Installing udev from backports"
    try apt install udev -t bullseye-backports -y
    step_done doExit="failure" mSuccess="All done, udev has been updated to the backports version $(get_udev_version)"
    echo_warning "You should REBOOT now"
    echo
    exit 0
else
    echo_warning "Bullseye-backports repository not available. Setting it up"
    echo
    step "Download repository signing key"
    download_bullseye_backports_key
    step "Adding backports to sources.d"
    add_bullseye_backports_to_sources
    step "Updating repositories' index and installing new udev"
    try apt -qq update
    get_repositories >/dev/null
    try apt -qq install udev -t bullseye-backports -y
    step_done doExit="failure" mSuccess="All done, udev has been updated to the backports version $(get_udev_version)"
    echo_warning "You should REBOOT now"
    echo
    exit 0
fi
