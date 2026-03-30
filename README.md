<div align="center">
  <h1>Lazyvoid</h1>
  <p><b>Void Linux with benefits</b></p>
</div>

> You love the speed and simplicity of Void Linux, but you are tired of maintaining it?

Lazyvoid is not a separate distribution. It is an automation layer for Void Linux. It handles system updates, Flatpak management, CPU performance tweaking, and system cleanups entirely in the background. 
It creates fully automated btrfs snapshots - as long as btrfs is utilized - right before every system update. If an update breaks your machine, you just reboot into the previous snapshot.

---

## How to get Lazyvoid

### 💿 Option A: The Lazyvoid ISO (Recommended)
If you want a fresh, out-of-the-box experience with KDE Plasma, Wayland, grab the latest bootable ISO https://drive.google.com/file/d/1-ng8c6OaihttjRaUFz0kB8XM1y7Ju9Ak/view?usp=sharing, boot it, install it, done. It's set and forget.

### 🛠️ Option B: The Universal installer (BETA)
If you're already running Void Linux and don't want to reinstall, use the Lazyvoid installer. 
This script will inject the Lazyvoid automation into your existing Void setup. It detects your hardware, sets up the repos, and even offers to compile the latest open modules if you are running a modern Nvidia GPU.

> ⚠️ **WARNING:** Running this script on a live machine is in BETA but considered stable, it will swap your current kernel to the `linux-lts` package to guarantee long-term stability for the background updates. If you rely on absolute bleeding-edge mainline kernels for specific hardware or just don't want it, this is not for you.

#### 💻 Installation Guide:

1. **Download lazyvoid-installer.sh**
2. **Run the installer** *(it will ask for your root password)*:
   ```bash
   sh lazyvoid-installer.sh --setup
   ```
3. **Profit**

The script will guide you through the process, install the necessary dependencies, fetch the background services, and reboot your machine once it is done.

---

## Embrace laziness
The Lazyvoid automation relies on a **minimal base system**. If you start cluttering your host system by manually installing dozens of arbitrary packages directly from the Void repositories via `xbps`, the risk of automated updates breaking something increases exponentially. 

**Keep the base clean**, use **Flatpaks** for your daily tools and games, and the system will be fine. If you treat the base system like a messy playground, expect things to break.

---

## What's under the hood?
* **Init-System:** `runit` *(Stage 1 boot script prevents update freezes)*
* **Safety Net:** Fully automated BTRFS snapshots before background updates
* **Maintenance:** Silent `xbps` cache cleaning, old kernel purging, and orphaned package removal
* **Apps:** Flathub repository integrated by default

---

## Are you insane !?
Updating blindly on a rolling release distribution is often considered a stupid idea – and honestly, that's generally true. But in the real world, everyday users will just smash the 'update' button anyway and cry over a bricked system later.

Lazyvoid embraces this reality and builds a massive safety net around it. 
* Minimizing the risk by running a rock-solid LTS kernel and keeping the base system extremely slim (all your daily apps are containerized Flatpaks). 
* Automatically creates a BTRFS system snapshot right before applying any background updates. If an update actually manages to break your system, you just reboot, select the previous snapshot in the GRUB menu, and you are back in business within seconds.

## Tested 
Lazyvoid isn't just some weekend experiment. These core scripts have been continuously running, evolving, and actively monitored on multiple different hardware setups for about two years now.

We've thrown everything at it – including booting up test machines that had been collecting dust offline for months, just to see if the background update mechanism survives the massive package backlog. It did. Over time, the scripts have been heavily refined, stripped of unnecessary bloat, and expanded with bulletproof features. What you download is a mature, battle-hardened setup that simply works and refuses to break. It's completely transparent and hackable if you want to.



## Issues ?
If you encounter any issue related to lazyvoid, please let us know: linux[at]knietief[dot]com or create a PR

<br>

<div align="center">
  <i>Built for lazy people who want things to just work.</i>
</div>
