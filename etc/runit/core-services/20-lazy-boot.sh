#!/bin/sh
# Version 20260330 - Lazyvoid Universal installer & hybrid firstboot

log="/var/log/lazy_installer.log"
LOCK_FILE="/tmp/lazy_installer.lock"

trap 'rm -f "$LOCK_FILE"' EXIT INT TERM QUIT

# ==============================================================================
# 1. INTERNAL FUNCTIONS
# ==============================================================================

install_nvidia_open_latest() {
    printf "\n--- STARTING ADVANCED NVIDIA OPEN MODULE INSTALLATION ---\n"

    # Install dependencies for building
    sudo xbps-install -y base-devel linux-lts-headers dkms libglvnd curl

    # Find the newly installed LTS kernel version for DKMS targeting
    LTS_VER=$(ls /lib/modules | grep -i "lts" | sort -V | tail -n 1)
    if [ -z "$LTS_VER" ]; then
        printf "ERROR: Could not detect LTS kernel version in /lib/modules. Falling back to current kernel.\n"
        LTS_VER=$(uname -r)
    fi
    printf "Targeting DKMS build for LTS Kernel: %s\n" "$LTS_VER"

    # Scrape latest version number from Nvidia servers
    printf "Scraping Nvidia servers for latest driver version...\n"
    LATEST_VERSION=$(curl -s https://download.nvidia.com/XFree86/Linux-x86_64/ | grep -oP 'href="\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=/")' | sort -V | tail -n 1)

    if [ -z "$LATEST_VERSION" ]; then
        printf "ERROR: Failed to fetch latest version from Nvidia!"
        return 1
    fi

    printf "Latest version found: %s\n" "$LATEST_VERSION"
    RUN_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${LATEST_VERSION}/NVIDIA-Linux-x86_64-${LATEST_VERSION}.run"
    INSTALLER_PATH="/var/tmp/NVIDIA-Linux-x86_64-${LATEST_VERSION}.run"

    printf "Downloading %s...\n" "$RUN_URL"
    curl -# "$RUN_URL" -o "$INSTALLER_PATH"
    chmod +x "$INSTALLER_PATH"

    # --- Applying the Tegra Dummy-Header Hack for LTS Headers ---
    HEADERS_DIR=$(find /usr/src -maxdepth 1 -type d -name "kernel-headers-${LTS_VER}*" | sort -V | head -n 1)

    if [ -n "$HEADERS_DIR" ] && [ -d "$HEADERS_DIR" ]; then
        printf "Applying Tegra hack in: %s\n" "$HEADERS_DIR"
        sudo mkdir -p "$HEADERS_DIR/include/soc/tegra"
        sudo touch "$HEADERS_DIR/include/soc/tegra/bpmp-abi.h" "$HEADERS_DIR/include/soc/tegra/bpmp.h" "$HEADERS_DIR/include/soc/tegra/mc.h" "$HEADERS_DIR/include/soc/tegra/tegra-icc.h"
        sudo mkdir -p "$HEADERS_DIR/include/linux/platform_data"
        sudo touch "$HEADERS_DIR/include/linux/platform_data/tegra_mc.h"
    else
        printf "Warning: Could not find headers dir for Tegra hack.\n"
    fi

    # --- System configurations (modprobe & dracut) ---
    printf "Writing modprobe and dracut configs (fbdev=1)...\n"
    echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null
    echo 'options nvidia_drm modeset=1 fbdev=1' | sudo tee /etc/modprobe.d/nvidia.conf > /dev/null
    sudo mkdir -p /etc/dracut.conf.d
    echo 'add_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf > /dev/null
    echo 'install_items+=" /lib/firmware/nvidia/* "' | sudo tee /etc/dracut.conf.d/nvidia-fw.conf > /dev/null

    # --- Setup DKMS ---
    DKMS_MODULE_NAME="nvidia-open"
    DKMS_SRC_DIR="/usr/src/${DKMS_MODULE_NAME}-${LATEST_VERSION}"
    TEMP_EXTRACT_DIR="/var/tmp/nvidia-installer-extraction"

    sudo rm -rf "$TEMP_EXTRACT_DIR" "$DKMS_SRC_DIR"
    mkdir -p "$TEMP_EXTRACT_DIR"

    printf "Extracting installer...\n"
    sh "$INSTALLER_PATH" -x --target "$TEMP_EXTRACT_DIR/extract" > /dev/null
    EXTRACTED_DIR=$(find "$TEMP_EXTRACT_DIR/extract" -maxdepth 1 -type d -name "NVIDIA-Linux-x86_64-*" | head -n 1)

    sudo mkdir -p "$DKMS_SRC_DIR"
    sudo cp -r "$EXTRACTED_DIR/kernel/"* "$DKMS_SRC_DIR/"

    sudo tee "${DKMS_SRC_DIR}/dkms.conf" > /dev/null << EOF
PACKAGE_NAME="${DKMS_MODULE_NAME}"
PACKAGE_VERSION="${LATEST_VERSION}"
BUILT_MODULE_NAME[0]="nvidia"
BUILT_MODULE_NAME[1]="nvidia-drm"
BUILT_MODULE_NAME[2]="nvidia-modeset"
BUILT_MODULE_NAME[3]="nvidia-uvm"
BUILT_MODULE_NAME[4]="nvidia-peermem"
DEST_MODULE_LOCATION[0]="/kernel/drivers/video"
DEST_MODULE_LOCATION[1]="/kernel/drivers/video"
DEST_MODULE_LOCATION[2]="/kernel/drivers/video"
DEST_MODULE_LOCATION[3]="/kernel/drivers/video"
DEST_MODULE_LOCATION[4]="/kernel/drivers/video"
MAKE[0]="'make' -j\$(nproc) KERNEL_UNAME=\${kernelver} SYSSRC=/lib/modules/\${kernelver}/build IGNORE_CC_MISMATCH=1 module-type=open"
AUTOINSTALL="yes"
EOF

    printf "Building OPEN modules via DKMS for LTS kernel...\n"
    sudo dkms add -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}"
    sudo dkms build -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}" -k "$LTS_VER"
    sudo dkms install -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}" -k "$LTS_VER"

    printf "Installing userspace libraries...\n"
    sudo sh "$INSTALLER_PATH" -s --no-kernel-module --install-libglvnd --run-nvidia-xconfig

    printf "Rebuilding initramfs...\n"
    sudo dracut --kver "$LTS_VER" --force

    # Cleanup
    sudo rm -rf "$TEMP_EXTRACT_DIR" "$INSTALLER_PATH"
    printf "--- ADVANCED NVIDIA INSTALLATION COMPLETE ---\n"
}

do_setup() {
    printf "Performing Lazyvoid setup.\n"
    printf "This will swap your kernel to LTS and inject the automation scripts.\n\n"

    # Keep sudo alive
    sudo -v
    (
        while true; do
            sleep 30
            sudo -n true 2>/dev/null
            kill -0 "$$" || exit
        done
    ) &

    # Swapping to LTS Kernel and basic updates
    printf "\nUpdating base system and swapping to LTS Kernel...\n"
    sudo xbps-install -Sy
    sudo xbps-install -yu xbps
    sudo xbps-install -Syu
    sudo xbps-install -y linux-lts linux-lts-headers

    # Install additional Lazyvoid packages
    printf "\n\nInstalling Lazyvoid dependencies...\n"
    sudo xbps-install -y unrar grub-btrfs cpupower libgamemode-32bit git curl flatpak wget netcat-openbsd pciutils diffutils btrfs-progs

    # Fetch Lazyvoid Scripts from GitHub
    printf "\n\nFetching Lazyvoid Automation Scripts from GitHub...\n"
    TMP_DIR="/tmp/lazyvoid_repo"
    rm -rf "$TMP_DIR"
    if git clone --depth=1 "https://github.com/Barba-Q/lazyvoid.git" "$TMP_DIR"; then
        sudo cp "$TMP_DIR/etc/runit/core-services/20-lazy-boot.sh" "/etc/runit/core-services/20-lazy-boot.sh"
        sudo cp "$TMP_DIR/usr/local/bin/lazyvoid_main.sh" "/usr/local/bin/lazyvoid_main.sh"
        
        # create a service for main script
        sudo mkdir -p /etc/sv/lazyvoid
        sudo cp "$TMP_DIR/etc/sv/lazyvoid/run" "/etc/sv/lazyvoid/run"
        
        sudo chmod +x /etc/runit/core-services/20-lazy-boot.sh
        sudo chmod +x /usr/local/bin/lazyvoid_main.sh
        sudo chmod +x /etc/sv/lazyvoid/run
        
        # activate service
        sudo ln -sf /etc/sv/lazyvoid /var/service/
        
        echo "Lazyvoid scripts and background service successfully injected."
    else
        echo "ERROR: Could not download Lazyvoid scripts. Check your internet connection."
        exit 1
    fi
    rm -rf "$TMP_DIR"

    # CPU Governor (Live-Set only)
    if sudo cpupower frequency-info -g | grep -q "performance"; then
        printf "Setting CPU governor to performance...\n"
        sudo cpupower frequency-set -g performance
    else
        echo "Info: Performance-Governor not available, you're probably on a virtual system."
    fi

    # Adding noatime to fstab
    sudo cp /etc/fstab /etc/fstab.bak.$(date +%F_%T)
    awk '$3 ~ /^(ext4|xfs|btrfs)$/ && $4 !~ /noatime/ { $4 = $4",noatime" } 1' /etc/fstab > /tmp/fstab.new

    if [ -s /tmp/fstab.new ]; then
        sudo mv -f /tmp/fstab.new /etc/fstab
        sudo chmod 644 /etc/fstab
        echo "noatime injected successfully."
    else
        echo "error injecting noatime, keeping backup."
        exit 1
    fi

    # Detect Nvidia hardware and Generation
    printf "\n\nChecking for Nvidia hardware...\n"
    GPU_INFO=$(lspci -nn | grep -i -E "VGA|3D" | grep -i NVIDIA || true)

    if [ -n "$GPU_INFO" ]; then
        printf "Nvidia hardware detected: %s\n" "$GPU_INFO"
        if echo "$GPU_INFO" | grep -qiE "GTX (10|9|8|7|6|5|4)[0-9]{2}|GT [0-9]{3}|Quadro (K|M|P)"; then
            printf "Older Nvidia architecture detected. Safe bet: Standard proprietary driver.\n"
            sudo xbps-install -y nvidia
            if [ ! -L /var/service/nvidia-powerd ]; then
                sudo ln -s /etc/sv/nvidia-powerd /var/service/
            fi
            printf "Standard Nvidia driver installed.\n"
        else
            printf "Modern Nvidia architecture detected (Turing+).\n"
            printf "Do you want to fetch and compile the LATEST open modules from Nvidia? (y/n): "
            read REPLY
            printf "\n"
            if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
                install_nvidia_open_latest
            else
                printf "\nSkipping automatic compilation. Falling back to Void repos.\n"
                sudo xbps-install -y nvidia
            fi
        fi
    else
        printf "No Nvidia hardware detected, moving on.\n\n"
        sleep 2
    fi

    # Intel microcode installation
    if lscpu | grep -iq 'Intel'; then
        printf "Intel CPU detected, installing intel-ucode...\n"
        sudo xbps-install -y intel-ucode
    else
        printf "No Intel CPU detected, skipping intel-ucode.\n"
    fi

    # Configure Flathub
    printf "\n\nConfiguring Flathub repository...\n"
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sleep 2

    # ==========================================
    # KERNEL CLEANUP & GRUB UPDATE
    # ==========================================
    printf "\n\nCleaning up old mainline kernel to enforce LTS boot...\n"
    sudo xbps-remove -Ry linux linux-headers >/dev/null 2>&1 || true
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    # ==========================================
    # HYBRID CLEANUP (Für ISO-Firstboot)
    # ==========================================
    printf "\n\nCleaning up first-boot files (if present)...\n"
    sudo rm -f /etc/runit/core-services/10-live-bootscript.sh

    if [ -f /etc/lazy/30-lazy_firstboot.sh ]; then
        sudo mv /etc/lazy/30-lazy_firstboot.sh /etc/lazy/30-lazy_firstboot_done.sh
        echo "Disabled firstboot script."
    fi
    if [ -f /etc/xdg/autostart/30-lazy_firstboot.desktop ]; then
        sudo mv /etc/xdg/autostart/30-lazy_firstboot.desktop /etc/lazy/30-lazy_firstboot.desktop.done
        echo "Disabled autostart entry."
    fi
    sleep 2

    # Final messages + reboot
    printf "\n\nConversion to Lazyvoid is complete!\n"
    printf "Your system is now on the LTS kernel and fully automated.\n"
    sleep 4
    printf "\nSYSTEM WILL REBOOT NOW!\n"
    sleep 5
    sudo reboot

    printf "\nERROR: Reboot failed. Press ENTER to close.\n"
    read _
}

do_offline_msg() {
    printf '#############################################################\n'
    printf '#                                                           #\n'
    printf '#  WARNING: No internet connection detected.                #\n'
    printf '#                                                           #\n'
    printf '#  Please connect to the internet to run the setup.         #\n'
    printf '#                                                           #\n'
    printf '#############################################################\n\n'
    printf "Press ENTER to close this window..."
    read _
}

# ==============================================================================
# 2. MAIN LOGIC
# ==============================================================================

if [ "$1" = "--setup" ]; then
    do_setup
    exit 0
fi

if [ "$1" = "--offline" ]; then
    do_offline_msg
    exit 0
fi

if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
touch "$LOCK_FILE"

# Detect live system (Installer present)
if [ -f "/usr/bin/void-installer" ]; then
    printf "Live system detected, launching void-installer.\n" >> "$log"
    rm -f "$LOCK_FILE"
    xterm -geometry 550x350+100 -e "sudo void-installer"
    exit 0
fi

printf "Starting Lazyvoid Converter.\n" >> "$log"
sleep 1

if ping -c1 1.1.1.1 >/dev/null 2>&1; then
    printf "System is ONLINE. Starting setup.\n" >> "$log"
    
    # Check for xterm and install if missing
    if ! command -v xterm >/dev/null 2>&1; then
        printf "\nxterm is missing. Updating xbps and installing xterm to display the GUI...\n"
        sudo xbps-install -Syu xbps
        sudo xbps-install -y xterm
    fi

    # Execute setup in xterm if available
    if command -v xterm >/dev/null 2>&1; then
        xterm -T "Lazyvoid Installer" -geometry 100x30 -e "sh $0 --setup"
    else
        # Fallback if xterm install failed
        sh "$0" --setup
    fi
else
    printf "System is OFFLINE. Displaying user notice.\n" >> "$log"
    if command -v xterm >/dev/null 2>&1; then
        xterm -title "Network Error" -geometry 80x15 -e "sh $0 --offline"
    else
        sh "$0" --offline
    fi
fi

exit 0
