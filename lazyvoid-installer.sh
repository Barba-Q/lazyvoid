#!/bin/sh
# Version 20260407 - Lazyvoid Universal Installer / Firstboot

log="/var/log/lazy_installer.log"
LOCK_FILE="/tmp/lazy_installer.lock"

trap 'rm -f "$LOCK_FILE"' EXIT INT TERM QUIT

# ==============================================================================
# 1. INTERNAL FUNCTIONS
# ==============================================================================

wait_for_internet() {
    while ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; do
        clear
        printf "====================================================\n"
        printf "   WARNING: NO INTERNET CONNECTION       \n"
        printf "====================================================\n\n"
        printf " This installer needs an online connection.\n\n"
        printf " 1. Please provide a connection to the Internet.\n"
        printf " 2. Hit ENTER to continue.\n\n"
        printf "====================================================\n"
        read -r _
        printf "checking...\n"
        sleep 1
    done
    printf "Connection found...\n\n"
    sleep 2
}

install_nvidia_open_latest() {
    printf "\n--- STARTING ADVANCED NVIDIA OPEN MODULE INSTALLATION ---\n"

    # Install dependencies for building
    sudo xbps-install -y base-devel linux-lts-headers dkms libglvnd curl

    # Scrape latest version number from Nvidia servers (with User-Agent fake)
    printf "Scraping Nvidia servers for latest driver version...\n"
    LATEST_VERSION=$(curl -s -A "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" https://download.nvidia.com/XFree86/Linux-x86_64/ | grep -oP 'href="\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=/")' | sort -V | tail -n 1)

    if [ -z "$LATEST_VERSION" ]; then
        printf "ERROR: Failed to fetch latest version from Nvidia! Falling back to Void repos...\n"
        sudo xbps-install -y nvidia
        return 1
    fi

    printf "Latest version found: %s\n" "$LATEST_VERSION"
    RUN_URL="https://download.nvidia.com/XFree86/Linux-x86_64/${LATEST_VERSION}/NVIDIA-Linux-x86_64-${LATEST_VERSION}.run"
    INSTALLER_PATH="/var/tmp/NVIDIA-Linux-x86_64-${LATEST_VERSION}.run"

    printf "Downloading %s...\n" "$RUN_URL"
    curl -# -A "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0" "$RUN_URL" -o "$INSTALLER_PATH"
    chmod +x "$INSTALLER_PATH"

    # --- Applying the Tegra Dummy-Header Hack ---
    KERNEL_VER=$(uname -r)
    HEADERS_DIR=$(find /usr/src -maxdepth 1 -type d -name "kernel-headers-${KERNEL_VER}*" | sort -V | head -n 1)

    if [ -n "$HEADERS_DIR" ] && [ -d "$HEADERS_DIR" ]; then
        printf "Applying Tegra hack in: %s\n" "$HEADERS_DIR"
        mkdir -p "$HEADERS_DIR/include/soc/tegra"
        touch "$HEADERS_DIR/include/soc/tegra/bpmp-abi.h" "$HEADERS_DIR/include/soc/tegra/bpmp.h" "$HEADERS_DIR/include/soc/tegra/mc.h" "$HEADERS_DIR/include/soc/tegra/tegra-icc.h"
        mkdir -p "$HEADERS_DIR/include/linux/platform_data"
        touch "$HEADERS_DIR/include/linux/platform_data/tegra_mc.h"
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
    sudo sh "$INSTALLER_PATH" -x --target "$TEMP_EXTRACT_DIR/extract" > /dev/null
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

    printf "Building OPEN modules via DKMS...\n"
    sudo dkms add -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}"
    sudo dkms build -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}"
    sudo dkms install -m "${DKMS_MODULE_NAME}" -v "${LATEST_VERSION}"

    printf "Installing userspace libraries...\n"
    sudo sh "$INSTALLER_PATH" -s --no-kernel-module --install-libglvnd --run-nvidia-xconfig

    printf "Rebuilding initramfs...\n"
    sudo dracut --force

    # Cleanup
    sudo rm -rf "$TEMP_EXTRACT_DIR" "$INSTALLER_PATH"
    printf "--- ADVANCED NVIDIA INSTALLATION COMPLETE ---\n"
}

do_setup() {
    printf "Performing Lazyvoid Conversion.\n"
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

    # Install additional Lazyvoid packages (cleaned up duplicates)
    printf "\n\nInstalling Lazyvoid dependencies...\n"
    sudo xbps-install -y ark zip unzip p7zip unrar grub-btrfs cpupower libgamemode-32bit git curl flatpak wget netcat-openbsd pciutils diffutils btrfs-progs

    # Fetch Lazyvoid Scripts from GitHub (Safe public clone)
    printf "\n\nFetching Lazyvoid Automation Scripts from GitHub...\n"
    TMP_DIR="/tmp/lazyvoid_repo"
    rm -rf "$TMP_DIR"
    if GIT_TERMINAL_PROMPT=0 git clone --depth=1 "https://github.com/Barba-Q/lazyvoid.git" "$TMP_DIR"; then
        sudo cp "$TMP_DIR/etc/runit/core-services/20-lazy-boot.sh" "/etc/runit/core-services/20-lazy-boot.sh"
        sudo cp "$TMP_DIR/usr/local/bin/lazyvoid_main.sh" "/usr/local/bin/lazyvoid_main.sh"
        sudo cp -r "$TMP_DIR/etc/sv/lazyvoid" "/etc/sv/"
        sudo chmod +x /etc/runit/core-services/20-lazy-boot.sh
        sudo chmod +x /usr/local/bin/lazyvoid_main.sh
        sudo chmod +x /etc/sv/lazyvoid/run
        sudo ln -s /etc/sv/lazyvoid /var/service/
        echo "Lazyvoid scripts successfully injected."
    else
        echo "ERROR: Could not download Lazyvoid scripts."
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

        # Create prime-run Wrapper for ALL Nvidia users
        printf "Creating prime-run wrapper for Optimus support...\n"
        sudo tee /usr/local/bin/prime-run > /dev/null << 'EOF'
#!/bin/sh
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"
EOF
        sudo chmod +x /usr/local/bin/prime-run

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
    # HYBRID CLEANUP
    # ==========================================
    printf "\n\nCleaning up first-boot files (if present)...\n"

    if [ -f /etc/lazy/lazyvoid-installer.sh ]; then
        sudo mv /etc/lazy/lazyvoid-installer.sh /etc/lazy/lazyvoid-installer_done.sh
        echo "Disabled firstboot script."
    fi
    if [ -f /etc/xdg/autostart/lazyvoid-installer.desktop ]; then
        sudo mv /etc/xdg/autostart/lazyvoid-installer.desktop /etc/lazy/lazyvoid-installer.desktop.done
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
    sleep 10
    printf "\nERROR: Reboot failed. Press ENTER to close.\n"
    read _
}


# ==============================================================================
# 2. MAIN LOGIC
# ==============================================================================

# CASE 1: Internal setup call in xterm
if [ "$1" = "--setup" ]; then
    wait_for_internet
    do_setup
    exit 0
fi

if [ -f "$LOCK_FILE" ]; then
    exit 0
fi
touch "$LOCK_FILE"

# CASE 2: ISO Live-System
if [ -f "/usr/bin/void-installer" ]; then
    printf "Live system detected, launching void-installer.\n" >> "$log"
    rm -f "$LOCK_FILE"
    DISPLAY=:0 xterm -T "Void Linux Installer" -geometry 100x30+100+100 -e "sudo void-installer"
    exit 0
fi

# CASE 3: Firstboot (Converter/Firstboot)
printf "Starting Lazyvoid Converter Environment.\n" >> "$log"
sudo -v

# Install xterm if missing
if ! command -v xterm >/dev/null 2>&1; then
    if ping -c1 1.1.1.1 >/dev/null 2>&1; then
        sudo xbps-install -Syu xbps && sudo xbps-install -y xterm
    fi
fi

if command -v xterm >/dev/null 2>&1; then
    DISPLAY=:0 xterm -T "Lazyvoid Setup" -geometry 100x30+100+100 -e "sudo -E sh $0 --setup"
else
    # Fallback, if xterm still missing
    sudo -E sh "$0" --setup
fi

exit 0
