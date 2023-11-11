#!/bin/bash

########## SETTINGS ##############

# Directories to monitor
MONITOR_DIRS="/home/klipper/printer_data/config /home/klipper/printer_data/database"

# Backup directory
BACKUP_DIR="/home/klipper/backup"

# Remote setup for rclone
REMOTE_NAME="my_rclone_drive" # Replace with your rclone remote name
REMOTE_DIR="remoteFolder"   # Replace with your remote directory in Google remote

# Number of backups to keep (only applicable to local backups)
NUM_BACKUPS_TO_KEEP=5

########## MAIN SCRIPT ##############

# Check if the backup method is provided as a command-line argument
if [ "$#" -ne 1 ]; then
    logger -t Klipper_BackupScript "Error: You must provide one argument: 'local' or 'remote'."
    exit 1
fi

METHOD="$1"

# Validate the provided method
if [ "$METHOD" != "local" ] && [ "$METHOD" != "remote" ]; then
    logger -t Klipper_BackupScript "Invalid method. You must enter either 'local' or 'remote'."
    exit 1
fi

# Function to perform backup
backup() {
    # Get current date and time for filename
    CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")

    # Filename for the backup
    BACKUP_FILE="backup_${CURRENT_DATETIME}.tar.gz"

    # Tar and gzip the directories
    tar -czf "${BACKUP_FILE}" ${MONITOR_DIRS}

    # Perform backup based on the chosen method
    if [ "$METHOD" == "local" ]; then
        # Copy to local backup directory
        cp "${BACKUP_FILE}" "${BACKUP_DIR}/"
        logger -t Klipper_BackupScript "Backup created and copied to local directory: ${BACKUP_DIR}/${BACKUP_FILE}"
    elif [ "$METHOD" == "remote" ]; then
        # Upload to Google remote using rclone
        rclone copy "${BACKUP_FILE}" "${REMOTE_NAME}:${REMOTE_DIR}"
        logger -t Klipper_BackupScript "Backup created and uploaded to remote drive: ${REMOTE_DIR}/${BACKUP_FILE}"
    fi

    # Remove the local backup file after copying/uploading
    rm "${BACKUP_FILE}"

    # Call the cleanup function
    cleanup
}

# Function to keep only the specified number of newest backup files
cleanup() {
    if [ "$METHOD" == "local" ]; then
        # Go to the backup directory
        cd "${BACKUP_DIR}"

        # Delete all but the specified number of most recent files
        ls -t | tail -n +$((NUM_BACKUPS_TO_KEEP + 1)) | xargs -d '\n' rm -f --
    fi
}

# Ensure backup directory exists for local backup
mkdir -p "${BACKUP_DIR}"

# Monitoring loop
while true; do
    # Wait for changes in the specified directories
    inotifywait -e modify,create,delete -r ${MONITOR_DIRS}

    # Call backup function with the selected method
    backup "$METHOD"
done

