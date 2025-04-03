#!/bin/bash
LOG=/var/log/lazy-boot.log
# set -x  # Uncomment for debugging

#######################################
# Checking for btrfs filesystem
#######################################

is_btrfs() {
    echo "Checking for btrfs"  >> $LOG
    mount | grep "on / type btrfs" > /dev/null 2>&1
    return $?
}

#######################################
# Checking for separate /home partition
#######################################

is_home_on_root_partition() {
    echo "Checking for seperate home partition"  >> $LOG
    home_mount=$(df /home | awk 'NR==2 {print $1}')
    root_mount=$(df / | awk 'NR==2 {print $1}')
    [ "$home_mount" == "$root_mount" ]
}

#######################################
# Function to create snapshot
#######################################

create_snapshot() {
    echo "creating new snapshot"  >> $LOG
    snapshot_dir="/@snapshots"
    timestamp=$(date +%Y%m%d_%H%M%S)
    snapshot_name="snapshot_$timestamp"
    btrfs subvolume snapshot / "$snapshot_dir/$snapshot_name"
    echo "$snapshot_name"  >> $LOG
}

#######################################
# Function to update grub entries
#######################################
update_grub() {
    echo "creating new grub entry"  >> $LOG
    timeout 60 grub-mkconfig -o /boot/grub/grub.cfg > /var/log/grub-mkconfig.log 2>&1
    if [ $? -ne 0 ]; then
        echo "Grub had an error, please see /var/log/grub-mkconfig.log for details."  >> $LOG
        exit 1
    fi
}

#######################################
# Function to remove oldest snapshot
#######################################

cleanup_snapshots() {
    echo "removing oldest snapshot"  >> $LOG
    snapshot_dir="/@snapshots"
    snapshot_list=$(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d | sort)
    oldest_snapshot=$(echo "$snapshot_list" | head -n 1)
    
    if [ -n "$oldest_snapshot" ]; then  # Check if the list is not empty
        btrfs subvolume delete "$oldest_snapshot" || {
            echo "Failed to delete subvolume $oldest_snapshot"  >> $LOG
            exit 1
        }
        rm -rf "$oldest_snapshot" || {
            echo "Failed to remove directory $oldest_snapshot"  >> $LOG
            exit 1
        }
        echo "Oldest snapshot $oldest_snapshot removed."  >> $LOG
    else
        echo "No snapshots found to delete."  >> $LOG
    fi

    echo "updating grub"  >> $LOG
    update_grub
}

#######################################
# Function to check if GNOME started successfully
#######################################

is_gnome_running() {
    echo "checking for a running Desktop"  >> $LOG
    pgrep -x "gnome-shell" > /dev/null 2>&1
    return $?
}

#######################################
# Main script
#######################################

main() {
    # Wait for GNOME with timeout
    echo "Waiting for GNOME session..." >> $LOG
    timeout=300  # 5 minutes
    elapsed=0
    while ! is_gnome_running; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $timeout ]; then
            echo "GNOME did not start, exiting script." >> $LOG
            exit 1
        fi
    done

    if is_btrfs && ! is_home_on_root_partition; then
        snapshot_dir="/@snapshots"
        mkdir -p "$snapshot_dir"
        new_snapshot=$(create_snapshot)
        echo "Snapshot $new_snapshot created."
    else
        echo "Skipping snapshots due to missing btrfs or /home on root partition." >> $LOG
    fi

    # Delete oldest snapshot if there are 4 or more snapshots
    snapshot_count=$(find "$snapshot_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)
    if [ "$snapshot_count" -ge 4 ]; then
        cleanup_snapshots
    fi

    # Update GRUB
    echo "Updating Grub"
    update_grub
    
    # Update software
    echo "Updating System packages..." >> $LOG
    if ! sudo xbps-install -yu xbps >> $LOG 2>&1; then
        echo "Failed to update xbps!" >> $LOG
    fi
    if ! sudo xbps-install -Syu >> $LOG 2>&1; then
        echo "Failed to update system!" >> $LOG
    fi
    echo "Updating flatpaks..." >> $LOG
    sudo flatpak update -y >> $LOG 2>&1
    echo "Removing unused flatpak files" >> $LOG
    sudo flatpak uninstall -y --unused
    
    	#######################################
	# Update Lazyvoid scripts
	#######################################

	echo "Updating Lazyvoid scripts" >> "$LOG"
	REPO_URL="https://github.com/Barba-Q/lazyvoid.git"
	TMP_DIR="/tmp/repo_temp"

	# Remove last temp files
	rm -rf "$TMP_DIR"
	mkdir -p "$TMP_DIR"

	# Clone repository
	echo "Cloning repository..." >> "$LOG"
	git clone --depth=1 "$REPO_URL" "$TMP_DIR" >> "$LOG" 2>&1

	if [ $? -ne 0 ]; then
	    echo "Error cloning repository." >> "$LOG"
	    exit 1
	fi

	echo "Comparing and updating files..." >> "$LOG"

	FILES_TO_UPDATE="
	/etc/default/grub
	/etc/runit/core-services/20-lazy-boot.sh
	/etc/xbps.d/blacklist.conf
	/usr/local/bin/btrfs-snapshot.sh
	"

	echo "$FILES_TO_UPDATE" | while read DEST_FILE; do
	    [ -z "$DEST_FILE" ] && continue  # Überspringe leere Zeilen
	    REL_PATH="$(echo "$DEST_FILE" | sed 's|^/||')"
	    SRC_FILE=$(find "$TMP_DIR" -type f -path "*/$REL_PATH" 2>/dev/null | head -n 1)
	    
	    if [ -n "$SRC_FILE" ] && [ -f "$SRC_FILE" ]; then
		if [ -f "$DEST_FILE" ]; then
		    if ! cmp -s "$SRC_FILE" "$DEST_FILE"; then
		        echo "Creating backup: ${DEST_FILE}.bak" >> "$LOG"
		        cp "$DEST_FILE" "${DEST_FILE}.bak"
		        echo "Updating: $DEST_FILE" >> "$LOG"
		        cp "$SRC_FILE" "$DEST_FILE"
		    fi
		else
		    echo "Adding new file: $DEST_FILE" >> "$LOG"
		    mkdir -p "$(dirname "$DEST_FILE")"
		    cp "$SRC_FILE" "$DEST_FILE"
		fi
	    else
		echo "Warning: $DEST_FILE not found in repository" >> "$LOG"
	    fi

	done

	# Cleanup
	echo "Cleanup temporary files" >> "$LOG"
	rm -rf "$TMP_DIR"

	echo "Lazyvoid scripts are up to date" >> "$LOG"
    
    
    

    echo "Script was successful."  >> $LOG
    date -I >> $LOG
    echo "########## END ##########" >> $LOG
}

main

#######################################
# End
#######################################

