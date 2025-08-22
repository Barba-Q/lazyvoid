#Version 20250822

##############################################################################
# This script will create snapshots, update system packages and flatpaks
##############################################################################

#!/bin/sh
LOG=/var/log/lazy-boot.log

mkdir -p /var/log
touch "$LOG"
chmod 644 "$LOG"

#######################################
# Checking for btrfs filesystem
#######################################

is_btrfs() {
    echo "Checking for btrfs"  >> "$LOG"
    mount | grep "on / type btrfs" >/dev/null 2>&1
    return $?
}

#######################################
# Checking for separate /home partition
#######################################

is_home_on_root_partition() {
    echo "Checking for separate home partition"  >> "$LOG"
    home_mount=`df /home | awk 'NR==2 {print $1}'`
    root_mount=`df / | awk 'NR==2 {print $1}'`
    [ "$home_mount" = "$root_mount" ]
}

#######################################
# Function to create snapshot
#######################################

create_snapshot() {
    echo "Creating new snapshot"  >> "$LOG"
    snapshot_dir="/@snapshots"
    timestamp=`date +%Y%m%d_%H%M%S`
    snapshot_name="snapshot_$timestamp"
    btrfs subvolume snapshot / "$snapshot_dir/$snapshot_name"
    echo "$snapshot_name"  >> "$LOG"
    echo "$snapshot_name"
    cleanup_snapshots
}

#######################################
# Function to clean up old snapshots
#######################################

cleanup_snapshots() {
    echo "Checking and cleaning old snapshots..." >> "$LOG"
    snapshot_dir="/@snapshots"
    snapshots=$(ls -1t "$snapshot_dir" | grep '^snapshot_' | tail -n +4)

    for snapshot in $snapshots; do
        echo "Deleting old snapshot: $snapshot" >> "$LOG"
        if sudo btrfs subvolume delete "$snapshot_dir/$snapshot" >> "$LOG" 2>&1; then
            rm -rf "$snapshot_dir/$snapshot"
        else
            echo "Failed to delete snapshot: $snapshot" >> "$LOG"
        fi
    done
}

#######################################
# Function to update grub entries
#######################################

update_grub() {
    echo "Creating new grub entry"  >> "$LOG"
    grub-mkconfig -o /boot/grub/grub.cfg >/var/log/grub-mkconfig.log 2>&1 &
    pid=$!
    SECONDS=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 5
        if [ "$SECONDS" -ge 60 ]; then
            echo "Grub update timed out!" >> "$LOG"
            kill "$pid"
            exit 1
        fi
    done
}

#######################################
# Function to check if GNOME started successfully
#######################################

is_gnome_running() {
    echo "Checking for a running Desktop"  >> "$LOG"
    pgrep -x gnome-session >/dev/null 2>&1 || pgrep -x gnome-shell >/dev/null 2>&1
    return $?
}

#######################################
# Main script
#######################################

main() {
    echo "Waiting for GNOME session..." >> "$LOG"
    timeout=300
    elapsed=0
    while ! is_gnome_running; do
        sleep 5
        elapsed=`expr $elapsed + 5`
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "GNOME did not start, exiting script." >> "$LOG"
            exit 1
        fi
    done

    if is_btrfs && ! is_home_on_root_partition; then
        snapshot_dir="/@snapshots"
        mkdir -p "$snapshot_dir"
        new_snapshot=`create_snapshot`
        echo "Snapshot $new_snapshot created."
    else
        echo "Skipping snapshots due to missing btrfs or /home on root partition." >> "$LOG"
    fi

    TIMEOUT=120
    INTERVAL=5
    ELAPSED=0

    while ! nc -zw1 google.com 443; do
        echo "Waiting for an internet connection..." >> "$LOG"
        sleep "$INTERVAL"
        ELAPSED=`expr $ELAPSED + $INTERVAL`
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo "Timeout: No internet connection after 2 minutes. Software updates skipped..." >> "$LOG"
            exit 1
        fi
    done
    #######################################
    # Update Void packages
    #######################################
    
    echo "System is online, proceeding" >> "$LOG"
    echo "Updating System packages..." >> "$LOG"
    
    # Check current Nvidia and Kernel version
    OLD_KERNEL=$(xbps-query -R -p pkgver linux)
    OLD_NVIDIA=$(xbps-query -R -p pkgver nvidia)

    # System updates
    if ! sudo xbps-install -yu xbps >> "$LOG" 2>&1; then
        echo "Failed to update xbps!" >> "$LOG"
    fi
    if ! sudo xbps-install -Syu >> "$LOG" 2>&1; then
        echo "Failed to update system!" >> "$LOG"
    fi
    # Check for newer Nvidia or Kernel versions
    NEW_KERNEL=$(xbps-query -R -p pkgver linux)
    NEW_NVIDIA=$(xbps-query -R -p pkgver nvidia)

    # Force reconfigure (thanks nidia)
    if [ "$OLD_KERNEL" != "$NEW_KERNEL" ]; then
        echo "Newer Kernelversion installed: $OLD_KERNEL → $NEW_KERNEL"
        sudo xbps-reconfigure -f nvidia
    fi

    # Force reconfigure (thanks nvidia)
    if [ "$OLD_NVIDIA" != "$NEW_NVIDIA" ]; then
        echo "Newer Nvidia driver installed: $OLD_NVIDIA → $NEW_NVIDIA"
        sudo xbps-reconfigure -f nvidia
    fi

    #######################################
    # Update and cleanup Flatpaks
    #######################################

    echo "Updating flatpaks..." >> "$LOG"
    sudo flatpak update -y >> "$LOG" 2>&1
    echo "Removing unused flatpak files" >> "$LOG"
    sudo flatpak uninstall -y --unused &
    wait

    #######################################
    # Update Lazyvoid scripts from github repo
    #######################################

    echo "Updating Lazyvoid scripts" >> "$LOG"
    REPO_URL="https://github.com/Barba-Q/lazyvoid.git"
    TMP_DIR="/tmp/repo_temp"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    echo "Cloning repository..." >> "$LOG"
    git clone --depth=1 "$REPO_URL" "$TMP_DIR" >> "$LOG" 2>&1

    if [ $? -ne 0 ]; then
        echo "Error cloning repository." >> "$LOG"
        exit 1
    fi

    echo "Comparing and updating files..." >> "$LOG"

    FILES_TO_UPDATE="/etc/default/grub /etc/runit/core-services/20-lazy-boot.sh /etc/xbps.d/blacklist.conf /usr/local/bin/btrfs_snapshot.sh"

    for DEST_FILE in $FILES_TO_UPDATE; do
        BASENAME=`basename "$DEST_FILE"`
        SRC_FILE=`find "$TMP_DIR" -type f -name "$BASENAME" 2>/dev/null | head -n 1`

        if [ -n "$SRC_FILE" ] && [ -f "$SRC_FILE" ]; then
            if [ -f "$DEST_FILE" ]; then
                cmp -s "$SRC_FILE" "$DEST_FILE"
                if [ $? -ne 0 ]; then
                    echo "Creating backup: ${DEST_FILE}.bak" >> "$LOG"
                    cp "$DEST_FILE" "${DEST_FILE}.bak"
                    echo "Updating: $DEST_FILE" >> "$LOG"
                    cp "$SRC_FILE" "$DEST_FILE"
                fi
            else
                echo "Adding new file: $DEST_FILE" >> "$LOG"
                mkdir -p "`dirname "$DEST_FILE"`"
                cp "$SRC_FILE" "$DEST_FILE"
            fi
        else
            echo "Warning: $DEST_FILE not found in repository" >> "$LOG"
        fi
    done

    echo "Cleanup temporary files" >> "$LOG"
    rm -rf "$TMP_DIR"

    echo "Lazyvoid scripts are up to date" >> "$LOG"
    echo "Script was successful." >> "$LOG"
    date -I >> "$LOG"
    echo "########## END ##########" >> "$LOG"
}

main
