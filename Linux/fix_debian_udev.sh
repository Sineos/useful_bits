#!/bin/bash

# Echo formatting
fError=`tput bold; tput setaf 1`
fInfo=`tput bold; tput setaf 4`
fReset=`tput sgr0`

# Function to check if we are on Debian 11
# or Debian based OS
is_debian_11() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if ([ "$ID" = "debian" ] || [ "$ID_LIKE" = "debian" ]) && [ "$VERSION_ID" = "11" ]; then
            return 0
        fi
    fi
    echo "${fError}This script only works for Debian 11 and Debian 11 based Linux OS. Exiting${fReset}"
    exit 1
}

# Check if the udev version contains the
# buggy version string deb11u2
is_udev_version_deb11u2() {
    udev_version=$(dpkg-query --show --showformat='${Version}' udev)
    if [[ "$udev_version" == *deb11u2* ]]; then
      return 0
    fi
    return 1
}

# Function to check if Bullseye backports are already
# available. E.g. Armbian already has them by default
is_bullseye_backports_available() {
    apt_cache_output=$(apt-cache policy 2>/dev/null)

    if echo "$apt_cache_output" | grep -q "bullseye-backports/main"; then
        return 0
    fi
    return 1
}

# Function to Download and install the Debian Bullseye key
# to sign the repository. Avoid apt-key since it is deprecated
# and considered insecure
download_bullseye_backports_key() {
    gpg -k
    gpg --no-default-keyring --keyring /tmp/keyring.gpg --keyserver keyserver.ubuntu.com --recv-key 0x73a4f27b8dd47936
    gpg --no-default-keyring --keyring /tmp/keyring.gpg --output /usr/share/keyrings/debian11-backports-archive-keyring.gpg --export
}

# Add the Bullseye backport repository and sign it
# with the downloaded GPG key
add_bullseye_backports_to_sources() {
    local repo_string="deb [signed-by=/usr/share/keyrings/debian11-backports-archive-keyring.gpg] http://ftp.debian.org/debian bullseye-backports main non-free contrib"
    echo "$repo_string" >> /etc/apt/sources.list.d/bullseye-backports.list
}

# Function to check if the script has root rights
is_root_user() {
   if [ "$(id -u)" -ne 0 ]; then
        echo "${fError}This script must be run as root. Please use sudo or run as the root user.${fReset}"
        exit 1
    fi
    return 0
}

#################################################################
###################### Main #####################################
#################################################################

# Check if we are running on Debian 11
is_debian_11

# Check for root rights
is_root_user

# Update the system first to have
# a stable starting point. E.g. PiOS Lite (32bit)
# seems to be shipped with deb11u1 Udev
apt update
apt upgrade -y

# Check for buggy udev version and remedy it
if is_udev_version_deb11u2; then
    if is_bullseye_backports_available; then
        echo "${fInfo}Backports already available. Installing udev from backports.${fReset}"
        apt install udev -t bullseye-backports -y
        echo "${fInfo}All done, udev has been updated to the backports version${fReset}"
        echo "${fInfo}You should REBOOT now${fReset}"
    else
        echo "${fInfo}Setting up bullseye-backports repository...${fReset}"
        download_bullseye_backports_key
        add_bullseye_backports_to_sources
        apt update
        echo "${fInfo}Backports installed. Installing udev from backports.${fReset}"
        apt install udev -t bullseye-backports -y
        echo "${fInfo}All done, udev has been updated to the backports version${fReset}"
        echo "${fInfo}You should REBOOT now${fReset}"
    fi
else
    echo "${fInfo}System seems OK. No need to install new udev. Exiting${fReset}"
fi
