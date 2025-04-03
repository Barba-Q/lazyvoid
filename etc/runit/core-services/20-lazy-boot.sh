#!/bin/sh
LOG=/var/log/lazy-boot.log
# set -x  # Uncomment for debugging

#######################################
# Removing old kernels
#######################################

echo "Removing old kernels" >> "$LOG"
vkpurge_output=$(vkpurge list)
num_entries=$(echo "$vkpurge_output" | wc -l)

if [ "$num_entries" -gt 2 ]; then
    while [ "$num_entries" -gt 2 ]; do
        first_entry=$(echo "$vkpurge_output" | head -n 1 | awk '{print $1}')
        sudo vkpurge rm "$first_entry"
        echo "Oldest Kernel '$first_entry' removed with vkpurge rm." >> "$LOG"
        vkpurge_output=$(vkpurge list)
        num_entries=$(echo "$vkpurge_output" | wc -l)
    done
else
    echo "There are $num_entries kernel entries. No action needed." >> "$LOG"
fi

#######################################
# Removing orphanes
#######################################

echo "Removing package cache and orphaned packages" >> "$LOG"
sudo xbps-remove -oy >> "$LOG" 2>&1
sudo xbps-remove -Oy >> "$LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "Removing orphaned packages failed" >> "$LOG"
else 
    echo "Orphaned packages removed" >> "$LOG"
fi

#######################################
# Initial stuff
#######################################

echo "Setting IP range" >> "$LOG"
sudo sysctl -w net.ipv4.ping_group_range="0 2147483647" >> "$LOG" 2>&1
echo "Cleanup complete, proceeding" >> "$LOG"

#######################################
# Link to update and snapshot script
#######################################

echo "Initial boot complete, creating snapshot & update" >> "$LOG"
nohup sudo sh /usr/local/bin/btrfs_snapshot.sh >> "$LOG" 2>&1 &
date -I >> "$LOG"
