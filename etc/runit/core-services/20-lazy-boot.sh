#!/bin/bash
LOG=/var/log/lazy-boot.log

#######################################
# Removing old kernels
#######################################

echo "Removing old kernels" >> $LOG
vkpurge_output=$(vkpurge list)
num_entries=$(echo "$vkpurge_output" | wc -l)

if [ $num_entries -gt 2 ]; then
    first_entry=$(echo "$vkpurge_output" | head -n 1 | awk '{print $1}')
    sudo vkpurge rm $first_entry
    echo "Oldest Kernel '$first_entry' removed with vkpurge rm." >> $LOG
else
    echo "There are $num_entries kernel entries. No action needed." >> $LOG
fi

#######################################
# Removing orphanes
#######################################

echo "Removing package cache and orphaned packages" >> $LOG
sudo xbps-remove -oy >> $LOG
sudo xbps-remove -Oy >> $LOG
if [ $? -ne 0 ]; then
    echo "Removing orphaned packages failed" >> $LOG
else 
    echo "Orphaned packages removed" >> $LOG
fi

#######################################
# Initial stuff
#######################################

echo "Setting IP range" >> $LOG
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647"
echo "Cleanup complete, proceeding" >> $LOG

#######################################
# Update Lazyvoid scripts
# Remove this section if you wanna make your own changes to any of the lazy void scripts.
#######################################


# Config
REPO_URL="https://github.com/user/repo/archive/refs/heads/main.tar.gz"
DEST_DIR="/pfad/zu/zielverzeichnis"
TMP_DIR="/tmp/repo_temp"
ARCHIVE="/tmp/repo.tar.gz"

# Remove old tmp files
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# download lazy void repo
wget -O "$ARCHIVE" "$REPO_URL"
tar -xzf "$ARCHIVE" -C "$TMP_DIR" --strip-components=1

# Compare and update
find "$TMP_DIR" -type f | while read -r FILE; do
    REL_PATH="${FILE#$TMP_DIR/}"
    DEST_FILE="$DEST_DIR/$REL_PATH"
    
    if [[ -f "$DEST_FILE" ]]; then
        # Compare
        if [[ $(stat -c%s "$FILE") -ne $(stat -c%s "$DEST_FILE") ]]; then
            echo "Replacing: $DEST_FILE"
            cp "$FILE" "$DEST_FILE"
        fi
    else
        # File is missing or new
        echo "Copy new file: $DEST_FILE"
        mkdir -p "$(dirname "$DEST_FILE")"
        cp "$FILE" "$DEST_FILE"
    fi

done

# remove temp files
rm -rf "$TMP_DIR" "$ARCHIVE"

echo "Lazyvoid scripts are up to date"

#######################################
# Link to update and snapshot script
#######################################

echo "Initial boot complete, creating snapshot & update" & sudo sh /usr/local/bin/btrfs_snapshot.sh &
date -I >> $LOG

#######################################
# End
#######################################
