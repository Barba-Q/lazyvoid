#!/bin/sh
LOG=/var/log/lazy-boot.log

# Version 20260330

################################################
# This script will be executed on every boot
################################################

# set -x  # Uncomment for debugging

#######################################
# unimmute /var/log
# This only exists due to a rare bug in recent kernel versions where /var/log was set immutable and causes hard freezes
#######################################
chattr -i /var/log

################################################
# System Update
################################################

if [ -n "$(xbps-install -un)" ]; then
    echo "=========================================================="
    echo " Installing prepared updates..."
    echo " Please do not turn off this machine."
    echo "=========================================================="
    xbps-install -uy
    echo " All done, proceeding..."
    sleep 1
fi

#######################################
# Removing old kernels
#######################################

echo "Removing old kernels" >> "$LOG"
vkpurge_output=$(vkpurge list 2>/dev/null || echo "")
num_entries=$(echo "$vkpurge_output" | wc -l)

if [ "$num_entries" -gt 2 ]; then
    while [ "$num_entries" -gt 2 ]; do
        first_entry=$(echo "$vkpurge_output" | head -n 1 | awk '{print $1}')
        vkpurge rm "$first_entry"
        echo "Oldest Kernel '$first_entry' removed with vkpurge rm." >> "$LOG"
        vkpurge_output=$(vkpurge list 2>/dev/null || echo "")
        num_entries=$(echo "$vkpurge_output" | wc -l)
    done
else
    echo "There are $num_entries kernel entries. No action needed." >> "$LOG"
fi

#######################################
# Removing orphaned packages
#######################################

echo "Removing package cache and orphaned packages" >> "$LOG"
xbps-remove -oy >> "$LOG" 2>&1
xbps-remove -Oy >> "$LOG" 2>&1
if [ $? -ne 0 ]; then
    echo "Removing orphaned packages failed" >> "$LOG"
else 
    echo "Orphaned packages removed" >> "$LOG"
fi

#######################################
# Initial settings
#######################################

echo "Setting IP range" >> "$LOG"
sysctl -w net.ipv4.ping_group_range="0 2147483647" >> "$LOG" 2>&1
echo "Applying performance tweaks" >> "$LOG"
echo 10 > /proc/sys/vm/swappiness 
sysctl -w vm.max_map_count=16777216
cpupower frequency-set -g performance
echo "Proceeding" >> "$LOG"

#######################################
# Link to update- and snapshot script
#######################################

echo "Initial boot complete, creating snapshot & update" >> "$LOG"
sh /usr/local/bin/lazyvoid_main.sh >> "$LOG" 2>&1 &
date -I >> "$LOG"

echo "Lazy-boot process completed" >> "$LOG"
