#!/bin/bash
LOG=/var/log/lazy-boot.log

#######################################
# Removing old kernels
#######################################

echo "Removing old kernels" >> $LOG
vkpurge_output=$(vkpurge list)
num_entries=$(echo "$vkpurge_output" | wc -l)

if [ $num_entries -gt 2 ]; then
    while [ $num_entries -gt 2 ]; do
        first_entry=$(echo "$vkpurge_output" | head -n 1 | awk '{print $1}')
        sudo vkpurge rm $first_entry
        echo "Oldest Kernel '$first_entry' removed with vkpurge rm." >> $LOG
        vkpurge_output=$(vkpurge list)
        num_entries=$(echo "$vkpurge_output" | wc -l)
    done
else
    echo "There are $num_entries kernel entries. No action needed." >> $LOG
fi

#######################################
# Removing orphanes
#######################################

echo "Removing package cache and orphaned packages" >> $LOG
sudo xbps-remove -oy >> $LOG 2>&1
sudo xbps-remove -Oy >> $LOG 2>&1
if [ $? -ne 0 ]; then
    echo "Removing orphaned packages failed" >> $LOG
else 
    echo "Orphaned packages removed" >> $LOG
fi

#######################################
# Initial stuff
#######################################

echo "Setting IP range" >> $LOG
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647" >> $LOG 2>&1
echo "Cleanup complete, proceeding" >> $LOG

#######################################
# Update Lazyvoid scripts
# Remove this section if you wanna make your own changes to any of the lazy void scripts.
#######################################

echo "Updating Lazyvoid scripts" >> $LOG
REPO_URL="https://github.com/Barba-Q/lazyvoid/archive/refs/heads/main.tar.gz"
TMP_DIR="/tmp/repo_temp"
ARCHIVE="/tmp/repo.tar.gz"

# Update targets
FILES_TO_UPDATE=(
    "/etc/default/grub"
    "/etc/runit/core-services/20-lazy-boot.sh"
    "/etc/xbps.d/blacklist.conf"
    "/usr/local/bin/btrfs-snapshot.sh"
)

# Remove last temp files
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Download and unpack repository
echo "Downloading repository..." >> $LOG
wget -O "$ARCHIVE" "$REPO_URL" >> $LOG 2>&1
echo "Extracting repository..." >> $LOG
tar -xzf "$ARCHIVE" -C "$TMP_DIR" --strip-components=1 >> $LOG 2>&1

echo "Comparing and updating files..." >> $LOG
for DEST_FILE in "${FILES_TO_UPDATE[@]}"; do
    REL_PATH="${DEST_FILE#/}"
    SRC_FILE="$TMP_DIR/$REL_PATH"
    
    if [[ -f "$SRC_FILE" ]]; then
        if [[ -f "$DEST_FILE" ]]; then
            if ! cmp -s "$SRC_FILE" "$DEST_FILE"; then
                echo "Creating backup: ${DEST_FILE}.bak" >> $LOG
                cp "$DEST_FILE" "${DEST_FILE}.bak"
                echo "Updating: $DEST_FILE" >> $LOG
                cp "$SRC_FILE" "$DEST_FILE"
            fi
        else
            echo "Adding new file: $DEST_FILE" >> $LOG
            mkdir -p "$(dirname "$DEST_FILE")"
            cp "$SRC_FILE" "$DEST_FILE"
        fi
    else
        echo "Warning: $SRC_FILE not found in repository" >> $LOG
    fi
done

echo "Cleanup temporary files" >> $LOG
rm -rf "$TMP_DIR" "$ARCHIVE"

echo "Lazyvoid scripts are up to date" >> $LOG

#######################################
# Link to update and snapshot script
#######################################

echo "Initial boot complete, creating snapshot & update" >> $LOG
sudo sh /usr/local/bin/btrfs_snapshot.sh >> $LOG 2>&1
date -I >> $LOG

#######################################
# End
#######################################

echo "Lazy-boot process completed" >> $LOG
