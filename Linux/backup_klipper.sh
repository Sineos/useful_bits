#!/bin/bash

########## SETTINGS ##############

# Directories to monitor for changes // mind the (..)
MONITOR_DIRS=("/home/klipper/printer_data/config" "/home/klipper/printer_data/database")

# Backup directory for local backups
BACKUP_DIR="/home/klipper/backup"

# Number of backups to keep for cleanup (only valid for 'local' backups)
NUM_BACKUPS_TO_KEEP=5  # Adjust this number based on your requirement

# Remote setup for rclone // only tested with Google Drive
# Other targets may need adaption of the script
REMOTE_NAME="myGoogleremote" # Replace with your rclone remote name
REMOTE_DIR="remoteFolder"    # Replace with your remote directory in rclone's remote

# Git repository setup
GIT_REPO_PATH="/path/to/git/repo" # Replace with your Git repository path
GIT_DEF_BRANCH="main"             # For GitHub the default branch is "main"
GIT_REMOTE_NAME="origin"          # Replace with your Git remote name

# Name of the systemd service
SERVICE_NAME="backup_klipper.service"

########## MAIN SCRIPT ##############

# Function to display help information
show_help() {
    echo "Usage: $SCRIPT_NAME [COMMAND] [METHOD]"
    echo ""
    echo "Commands:"
    echo "  install [METHOD]   Install the backup script as a systemd service."
    echo "                     METHOD can be 'local', 'remote', or 'git'."
    echo "  help               Display this help message."
    echo ""
    echo "Methods:"
    echo "  local              Perform local backups."
    echo "  remote             Perform backups to a remote server using rclone."
    echo "  git                Perform backups to a Git repository."
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME install local"
    echo "  $SCRIPT_NAME install remote"
    echo "  $SCRIPT_NAME install git"
}

# Dynamically get the full path of the script
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

install_dependencies() {
    echo "Installing inotify-tools..."
    sudo apt-get install -y inotify-tools

    if [ "$1" == "remote" ]; then
        echo "Installing rclone..."
        sudo apt-get install -y rclone
    fi
}

create_systemd_service() {
    echo "Creating systemd service..."

    # Create systemd service file safely
    SERVICE_FILE_CONTENT="[Unit]
Description=Backup Script Service

[Service]
ExecStart=$SCRIPT_PATH $1
Restart=always

[Install]
WantedBy=multi-user.target"

    echo "$SERVICE_FILE_CONTENT" | sudo tee /etc/systemd/system/$SERVICE_NAME > /dev/null

    # Reload systemd daemon and enable service
    if systemctl is-active --quiet $SERVICE_NAME; then
        sudo systemctl stop $SERVICE_NAME
    fi
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    sudo systemctl start $SERVICE_NAME

    echo "Service installed and started."
}

# Check for command line arguments for installation and help
if [ "$1" == "install" ]; then
    if [ "$2" == "local" ] || [ "$2" == "remote" ] || [ "$2" == "git" ]; then
        install_dependencies "$2"
        create_systemd_service "$2"
    else
        echo "Invalid installation option. Use 'install local', 'install remote', or 'install git'."
        exit 1
    fi

    exit 0
elif [ "$1" == "help" ]; then
    show_help
    exit 0
fi


# Check if the backup method is provided as a command-line argument
if [ "$#" -ne 1 ]; then
    logger -t "${SERVICE_NAME}" "Error: You must provide one argument: 'local', 'remote' or 'git'."
    exit 1
fi

METHOD="$1"

# Validate the provided method
if [ "$METHOD" != "local" ] && [ "$METHOD" != "remote" ] && [ "$METHOD" != "git" ]; then
    logger -t "${SERVICE_NAME}" "Invalid method. You must enter either 'local', 'remote' or 'git'."
    exit 1
fi

# Function to perform local backup
local_backup() {
    CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
    BACKUP_FILE="backup_${CURRENT_DATETIME}.tar.gz"
    tar -czf "${BACKUP_FILE}" "${MONITOR_DIRS[@]}"
    cp "${BACKUP_FILE}" "${BACKUP_DIR}/"
    logger -t "${SERVICE_NAME}" "Local backup created: ${BACKUP_DIR}/${BACKUP_FILE}"
    rm "${BACKUP_FILE}"
}

# Function to perform remote backup
remote_backup() {
    CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
    BACKUP_FILE="backup_${CURRENT_DATETIME}.tar.gz"
    tar -czf "${BACKUP_FILE}" "${MONITOR_DIRS[@]}"
    rclone copy "${BACKUP_FILE}" "${REMOTE_NAME}:${REMOTE_DIR}"
    logger -t "${SERVICE_NAME}" "Backup uploaded to rclone remote: ${REMOTE_DIR}/${BACKUP_FILE}"
    rm "${BACKUP_FILE}"
}

# Function to perform git backup
git_backup() {
    rsync -av --delete "${MONITOR_DIRS[@]}" "${GIT_REPO_PATH}/"
    cd "${GIT_REPO_PATH}" || exit
    git add .
    git commit -m "Backup on $(date)"
    git push "${GIT_REMOTE_NAME}" "${GIT_DEF_BRANCH}"
    logger -t "${SERVICE_NAME}" "Backup pushed to Git repository: ${GIT_REMOTE_NAME}"
}

# Function to keep only the specified number of newest backup files
cleanup() {
    if [ "$METHOD" == "local" ]; then
        # Go to the backup directory
        cd "${BACKUP_DIR}" || exit

        # Delete all but the specified number of most recent files
        find "${BACKUP_DIR}" -type f -print0 | xargs -0 ls -t | tail -n +$((NUM_BACKUPS_TO_KEEP + 1)) | xargs -d '\n' rm -f --
    fi
}

# Monitoring loop
while true; do
    inotifywait -e modify,create,delete -r "${MONITOR_DIRS[@]}"

    case "$METHOD" in
        local)
            local_backup
            ;;
        remote)
            remote_backup
            ;;
        git)
            git_backup
            ;;
        *)
            logger -t "${SERVICE_NAME}" "Invalid backup method specified."
            exit 1
            ;;
    esac

    cleanup
done
