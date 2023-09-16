#!/bin/bash

# Helper to get step/next/try error checking
# Based on: https://stackoverflow.com/a/5196220

# Use step(), try(), and next() to perform a series of commands and print
# [  OK  ] or [FAILED] at the end. The step as a whole fails if any individual
# command fails.
#
# Example:
#     step "Remounting / and /boot as read-write:"
#     try mount -o remount,rw /
#     try mount -o remount,rw /boot
#     next

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

# Function to annaounce the next processing step
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
# return a general success / failure message
next() {
  doExit="$1"
  [[ -f /tmp/step.$$ ]] && {
    STEP_OK=$(</tmp/step.$$)
    rm -f /tmp/step.$$
  }
  if [[ $STEP_OK -eq 0 ]]; then
    echo_success "OK"
  else
    if [ "$doExit" ]; then
      echo_failure "FAILED"
      echo
      exit 1
    fi
    echo_failure "FAILED"
  fi
  echo

  return $STEP_OK
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
  echo -e "\r"
  return 1
}

##############################
# Start of the actual script #
##############################

# Function to check if the script has root rights
is_root_user() {
  if [ "$(id -u)" -ne 0 ]; then
    echo_failure "This script must be run as root. Please use sudo or run as the root user."
    echo
    return 1
  fi
  return 0
}

# Function to check if a service unit is enabled
check_service_enabled() {
  service_unit="$1"
  systemctl is-enabled --quiet "$service_unit"
}

# Function to stop a service unit
stop_service() {
  service_unit="$1"
  step "Stopping $service_unit"
  try systemctl --quiet stop "$service_unit"
  next
}

# Function to disable a service unit
disable_service() {
  service_unit="$1"
  step "Disabling $service_unit"
  try systemctl disable --quiet --now "$service_unit"
  next
}

# Function to mask a service unit
mask_service() {
  service_unit="$1"
  step "Masking $service_unit"
  try systemctl --quiet mask "$service_unit"
  next
}

# Function to list and disable services based on a name pattern
list_and_disable_services() {
  service_pattern="$1"
  step "Checking if $service_pattern is installed"
  service_units=($(systemctl list-units --full --all -t service | grep -i "$service_pattern" | awk '{print $1}'))

  if [ ${#service_units[@]} -eq 0 ]; then
    echo_success "No $service_pattern service(s) found."
    echo
  else
    for service_unit in "${service_units[@]}"; do
      echo_warning "$service_unit found"
      if check_service_enabled "$service_unit"; then
        stop_service "$service_unit"
        disable_service "$service_unit"
        mask_service "$service_unit"
      else
        mask_service "$service_unit"
      fi
    done
  fi
}

# Main script

# Check for root rights
step "Checking for root rights"
try is_root_user
next "doExit"

# List and disable brltty services
list_and_disable_services "brltty"

# List and disable modemmanager service
list_and_disable_services "modemmanager"

exit 0
