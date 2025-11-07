#!/bin/bash

LOG_FILE="$HOME/logs/frame_sync.log"
#RCLONE_CONFIG="/home/pi/.config/rclone/rclone.conf"
#RCLONE_REMOTE="kfphotos:album/frame"
#LDIR="./Pictures/frame"
Rclone_remote="kfgdrive:dframe"
LDIR="./Pictures/gdt_frame"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') frame_sync.sh - $message" | tee -a "$LOG_FILE"
}

# Ensure the log file exists
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE"
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to create log file at $LOG_FILE. Check permissions."
        exit 1
    fi
    sudo chmod 664 "$LOG_FILE"  # Set write permissions for owner and group
    log_message "Log file created."
fi

# Function to get directory counts
get_directory_counts() {
    local dir_type="$1"
    local count=0
    if [ "$dir_type" = "google" ]; then
        #count=$(sudo rclone ls "$RCLONE_REMOTE" | wc -l)
	 count=$(sudo rclone ls kfgdrive:dframe |wc -l)
    elif [ "$dir_type" = "local" ]; then
        count=$(ls "$LDIR" | wc -l)
    else
        log_message "ERROR: Invalid directory type specified: $dir_type"
        exit 1
    fi

    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to get file count for $dir_type."
        exit 1
    fi
    echo "$count"
}

# Function to sync directories
sync_directories() {
    log_message "Syncing directories."
    sudo rclone sync kfgdrive:dframe ./Pictures/gdt_frame |wc -l
    if [ $? -ne 0 ]; then
        log_message "ERROR: Sync failed."
        exit 1
    fi
    log_message "Sync complete."
}
# Function to restart picframe.service and log the process
restart_picframe_service() {
    local service="picframe.service"

    log_message "Attempting to restart $service."

    # Stop the service
    systemctl --user stop "$service"
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to stop $service."
        return 1
    fi
    log_message "$service successfully stopped."

    # Start the service
    systemctl --user start "$service"
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to start $service."
        return 1
    fi

    # Verify the service status
    systemctl --user is-active --quiet "$service"
    if [ $? -eq 0 ]; then
        log_message "$service restarted successfully."
    else
        log_message "ERROR: $service failed to restart."
        return 1
    fi
}


# Main process
log_message "Starting directory check and sync process."

# Get initial counts
gdir_count=$(get_directory_counts "google")
ldir_count=$(get_directory_counts "local")

log_message "Google Album file count: $gdir_count"
log_message "Local directory file count: $ldir_count"

# Compare counts
if [ "$gdir_count" -eq "$ldir_count" ]; then
    log_message "Counts match. No sync needed. Exiting."
    exit 0
else
    log_message "Counts do not match. Syncing directories."
    sync_directories
    sync_performed=true
    log_message "Sync completed. Restarting picframe.service."
#    restart_picframe_service
#    ./T1_picframe_svc_restart.sh
    restart_picframe_service
   if [ $? -ne 0 ]; then
       log_message "ERROR: Service restart failed after sync."
       exit 1
    else
       log_message "Service restart succeeded."
    fi
fi

# Final verification only if a sync was performed
if [ "${sync_performed:-false}" = true ]; then
    log_message "Final Verification: Checking directories after sync."
    gdir_count=$(get_directory_counts "google")
    ldir_count=$(get_directory_counts "local")

    log_message "Final Verification: Google Album file count: $gdir_count"
    log_message "Final Verification: Local directory file count: $ldir_count"

    if [ "$gdir_count" -eq "$ldir_count" ]; then
        log_message "Final Verification: Directories are in sync."
    else
        log_message "ERROR: Final Verification failed. Directories still do not match."
        exit 1
    fi
fi



