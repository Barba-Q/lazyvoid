#!/bin/sh
LOG=/var/log/lazy-boot.log

# Version 20260330 - Clean Stage 1 Boot Script

################################################
# This script will be executed on every boot (Stage 1)
################################################

# set -x  # Uncomment for debugging

#######################################
# unimmute /var/log
# Fixes a rare bug where /var/log becomes immutable
#######################################
chattr -i /var/log 2>/dev/null

################################################
# System Update (Offline Flag Check)
################################################
# Das Main-Skript setzt dieses Flag, wenn Updates geladen wurden
UPDATE_FLAG="/var/tmp/lazy_update_pending"

if [ -f "$UPDATE_FLAG" ]; then
    echo "=========================================================="
    echo " Installing prepared updates..."
    echo " Please do not turn off this machine."
    echo "=========================================================="
    # -u installiert nur xbps, -y bestätigt alles, -f erzwingt ggf.
    xbps-install -uy
    rm -f "$UPDATE_FLAG"
    echo " All done, proceeding..."
    sleep 1
fi

#######################################
# Removing old kernels
#######################################
echo "Removing old kernels" >> "$LOG"
vkpurge_output=$(vkpurge list 2>/dev/null || echo "")
num_entries=$(echo "$vkpurge_output" | wc -l)

# Wir behalten immer 2 Kerne zur Sicherheit
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
# Removing orphaned packages & Cache cleanup
#######################################
echo "Removing package cache and orphaned packages" >> "$LOG"
# -o entfernt Waisen, -O leert den Cache
xbps-remove -oy >> "$LOG" 2>&1
xbps-remove -Oy >> "$LOG" 2>&1

#######################################
# System Settings & Performance
#######################################
echo "Applying system tweaks" >> "$LOG"
# Erlaubt Pings für alle User (wichtig für Steam/Games)
sysctl -w net.ipv4.ping_group_range="0 2147483647" >> "$LOG" 2>&1

# Swappiness auf 10 (besser für Desktop-Responsiveness)
echo 10 > /proc/sys/vm/swappiness 

# Max Map Count for Steam/Proton/Star Citizen
sysctl -w vm.max_map_count=16777216 >> "$LOG" 2>&1

# Set CPU Governor to Performance
if command -v cpupower >/dev/null 2>&1; then
    cpupower frequency-set -g performance >> "$LOG" 2>&1
fi

echo "Stage-1 Lazy-boot process completed" >> "$LOG"
date -I >> "$LOG"#!/bin/sh
