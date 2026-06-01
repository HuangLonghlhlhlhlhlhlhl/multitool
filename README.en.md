# STATUS CTRL

<div align="center">

**macOS Status Bar Hardware Diagnostics & Fan Control Utility**

Real-time Temp/Battery Telemetry · Independent Dual Fan Speed Control · Power Policy Tuning · Animated Keyboard Backlight Effects · Zero-Lag Fluid Experience

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-green)
![Version](https://img.shields.io/badge/Version-1.9.3-orange)
![Size](https://img.shields.io/badge/Size-~9.5MB-lightgrey)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[English](README.en.md) | [简体中文](README.md)

</div>

<div align="center">
  <img src="assets/screenshots/dashboard.png" width="32%" alt="STATUS CTRL Dashboard" />
  <img src="assets/screenshots/ssd_health.png" width="32%" alt="STATUS CTRL SSD Health" />
  <img src="assets/screenshots/settings.png" width="32%" alt="STATUS CTRL Settings" />
</div>

---

## 📦 Installation

1. **Download** `STATUS CTRL-v1.9.3.dmg` from the [Latest Release](https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest).
2. Open the DMG, drag **`STATUS CTRL.app`** to the **`Applications`** folder on the right.
3. Launch "STATUS CTRL" from your Launchpad or Applications folder.
4. **First-time launch**: If macOS warns about an "unidentified developer", go to  
   `System Settings → Privacy & Security` and click `Open Anyway`.

> The App runs silently in your screen's top **Status Bar** (menu bar) with no Dock icon.

---

## ✨ Features at a Glance

| Feature | Description |
|------|------|
| 🌡️ CPU / GPU Temp | Real-time processor die core temperature telemetry. Supports both Apple Silicon & Intel. |
| 🔋 Battery Monitoring | Diagnostics for battery percentage, voltage, current, cell temperature, charge/remaining time. |
| 🌀 Dual Fan Control | Standalone RPM indicators. Supports Silent, Balanced, Turbo presets + custom temperature curves. |
| 🔗 Sync / Standalone | Toggle dual fans to work together in sync or control them separately. |
| ⌨️ Keyboard Backlight | Brightness slider with static, breathing, and wave effect animations. |
| ⚡ Power Policy Tuning | Silent, Balanced, and Turbo presets. Separate policies for AC power and battery power. |
| 📊 Est. Runtime Budgeting | Deductive remaining runtime based on current discharge rate and custom power limit. |
| 🧹 Deep RAM Clean | Multi-column Memory Page with a dynamic water-level ring, live scanning of top 7 active user processes, and deep memory purge feedback. |
| 🧹 Deep Storage Clean | **[NEW]** Deeply scans and cleans Xcode DerivedData, system log caches, general application caches, and leftover application data (bundle match validation). |
| 👯 Duplicate File Finder | **[NEW]** Progressive 3-step MD5 search engine to instantly identify and safely remove duplicate files. |
| 📈 Live Throughput Chart | **[NEW]** Live dual line glowing line chart plotting real-time SSD MB/s read/write speed on System Health Tab. |
| 🔌 AC/Idle Self-Maintenance| **[NEW]** Automates memory purge and APFS preboot index rebuilding when connected to AC power and user is idle for >= 5 minutes. |
| 🛡️ Device Privacy Guard | 4-way privacy switches (Camera, Mic, Screen, Auto Action) alongside a randomized scrambled keylogger-proof on-screen keyboard. |
| ⚙️ Customize Status Bar | Dedicated settings tab with interactive macOS menu bar mockup preview to show/hide 8 status indicators with perfect alignment. |
| 🔄 Auto-Updater & Upgrade | Integrates GitHub Releases API to automatically check for updates. Supports background download, live progress bar, automatic mounting/opening of `.dmg` installers, version skipping, and a neon notification dot. |
| 🩺 System Health & SSD | Dedicated 4th Tab with a premium dark glassmorphic health dial and glowing ring to show health %; card-based telemetry for TBW & Read total (precision to 3 decimal places in TB), visual bar tracking against the standard 300 TBW SSD lifespan limit. |
| 🖱️ Context Menu | Right-click the status bar icon for Settings, About, and Quit. |

---

## 🖱️ Usage

| Interaction | Action / Effect |
|------|------|
| **Left Click** Status Icon | Toggle the main dashboard panel. |
| **Right Click** Status Icon | Open the context menu (Settings / About / Quit). |
| **Two-finger Tap** on Trackpad | Open the context menu. |
| **Scroll / Swipe** on Panel | Page up/down between the main dashboard and the second page (Battery Care / Keyboard Light). |

---

## 🔐 SMC Fan Control Authorization

Manual fan speed control requires writing to SMC registers, which requires root privileges. **Initial setup process:**

1. Open main panel → "Fan Control" → enable "Manual Force".
2. Enter your **administrator password** once when prompted.
3. The app automatically copies the secured `smchelper` to `/Library/PrivilegedHelperTools/com.hl.smchelper` and configures execution permissions.
4. Once authorized, **password-free fan control is permanently enabled**, even if you move, rename, or update the App.

> Authorization is strictly scoped to `com.hl.smchelper`. The code is open-source for auditing, ensuring safety and security.

---

## ⚡ Power Saving & Policies

v1.7.0 introduces high-precision native battery telemetry without percentage conversion and corrects estimated runtime display, alongside independent power policies:

- **🔌 AC Power**: 🚀 Turbo / ⚖️ Balanced / 🍃 Eco Silent performance presets.
- **🔋 Battery Power**: Three standalone presets + "Target System Power Limit" slider.
- **Runtime Budgeting**: Dynamically and precisely estimates and compares "Limit Budgeted Runtime" vs "Live Estimated Runtime" using native mAh values, completely eliminating fluctuations.
- **Auto-Align Settings**: Automatically matches fan curve presets, keyboard backlight, and screen sleep timeout with the current performance level.

---

## 🩺 SSD Lifespan & Health Diagnostics (New in v1.8.0)

STATUS CTRL v1.8.0 introduces a highly requested solid-state drive lifespan and health diagnostics dashboard designed for power users and developers:

- **🌀 Neon Health Circle Gauge**: Displays a dynamic, colorful circular health status dial that ranges from vibrant green to warned red, placing the exact remaining life percentage `%` right at the center.
- **📊 Precise TBW Telemetry**: High-fidelity rounded diagnostic cards display your exact cumulative **bytes written (TBW)** and **bytes read** down to 3 decimal places in TB. Includes an elegant linear budget bar that maps your usage against the standard 300 TBW limits.
- **🛡️ Sandboxed Privilege Bypass**: Executes NVMe SMART diagnostics as root using the secured helper `smchelper`, bypasses strict sandboxed directory permissions of standard macOS applications.
- **🛠️ One-Click Automatic Environment Configuration**: Detects missing diagnostic backends and provides a sleek, glowing floating helper button. Click once to automatically install `smartmontools` using Homebrew (`brew install smartmontools`) in a silent background thread. Once done, the dashboard fades in with detailed telemetry.
- **🔌 No-Dependency Plist Fallback**: Automatically downgrades to a zero-dependency Plist parser using `diskutil info` if Homebrew is unavailable. Restores basic device models (e.g. `APPLE SSD AP0512R`), raw device capacity, and verified SMART status immediately.
- **⏱️ Zero Background Overhead**: Adheres to our zero-lag principle. SSD disk telemetry runs only when the "System Health" tab is actively viewed. Telemetry goes fully silent when the dashboard is closed or when switching tabs, yielding **0ms main-thread lag and 0% CPU consumption**.

---

## 🧹 Smart Storage Cleaning, Duplicate Finding & Idle Maintenance (New in v1.9.0)

STATUS CTRL v1.9.0 introduces a comprehensive storage cleanup and optimization suite to safeguard your board-soldered SSD and reclaim valuable space:

- **🧹 Caches & Leftovers Deep Cleaner**:
  - **Xcode Build Sweeper**: Safely sweeps large compile cache directories (`Xcode DerivedData`).
  - **Logs & System Cache Scans**: Clears system logs under `/Library/Logs` and app caches under `~/Library/Caches`.
  - **Bundle ID Residual Scanner**: Automatically compares sub-directories in `~/Library/Application Support` with current active application bundle IDs to identify and clean abandoned app configurations and leftover folders.

- **👯 Progressive Duplicate File Finder**:
  - **Progressive Tri-Stage Algorithm**: Employs an ultra-fast "file size pre-filtering ── 10KB partial MD5 hash ── full-file MD5 signature" validation pipeline. Swiftly locates exact duplicates within seconds, even across tens of thousands of files.
  - **Custom Folder Target**: One-click scanner for the default `~/Downloads` directory or any custom directory via a native folder sheet.
  - **Safe Trash/Delete Actions**: Move selected duplicates securely to the System Trash (`trashItem`) or permanently delete them with complete confirmation checks.

- **📈 Real-Time Disk Throughput Chart**:
  - Leverages low-level **IOKit Block Storage Drivers** to read physical sector transaction differentials.
  - Plots a glowing, smooth double-line graph representing live read/write speeds in MB/s on the System Health tab.

- **🔌 Intelligent AC/Idle Automation (Idle-Purger)**:
  - **Silent Purge**: Listens to system user idle status (`CGEventSource.secondsSinceLastEventType`). If idle for $\ge 5$ minutes and RAM occupancy $\ge 80\%$, automatically launches a silent Mach memory optimization.
  - **AC Preboot Optimizer**: Rebuilds APFS preboot index structures (`diskutil apfs updatePreboot`) and clears caches in a privileged background process when the Mac is idle for $\ge 5$ minutes and connected to AC wall power.

---

## 🛡️ Device Security, Auto-Updater & Memory Purging (New in v1.6.0)

STATUS CTRL v1.6.0 introduces four major advanced upgrades focusing on device privacy protection and system resource optimization:

### 1. 🧹 Deep Memory Clean (Memory Purge detail)
- **Visual Ring Monitoring**: An intuitive neon percentage ring dynamically reflecting the physical RAM load.
- **Active Process Ranking**: A background queue runs a non-blocking `ps` command to scan and aggregate the Resident Set Size (RSS) of active user-space processes (such as Google Chrome, WeChat, VS Code, Finder, etc.), cleanly presenting the top 7 memory-consuming applications in descending order with GB/MB units.
- **Deep Reclaiming Sequence**: Combines Mach core memory pressure allocation with a cache-sweeping sequence. Displays a smooth countdown percent indicator during the purge and instantly reports the exact volume of memory reclaimed (e.g., "Reclaimed 1240 MB").

### 2. 🛡️ Privacy Guard & Secure Scrambled Keyboard
- **Real-Time Privacy Controls**: Includes 4 indicator cards for Camera, Microphone, Screen Recording, and High-Risk Auto-Action monitoring, complete with smooth breathing backlights and micro-animations when enabled.
- **Secure Scrambled Keyboard**: Designed to counter screen-recording spyware, keyloggers, and physical shoulder surfing. A fully randomized on-screen input matrix (combining 0-9 and A-Z) shuffles dynamically using `.shuffled()` every time the guard opens or when refreshed. Features eye-toggle masking, strength analysis, and secure one-click clipboard copying.

### 3. ⚙️ Customize Status Bar Tab (StatusBar Customize Panel)
- Introduces a dedicated **"Status Bar"** tab in the Settings window, featuring a pixel-perfect, high-fidelity macOS menu bar mockup preview.
- **Dynamic Grid Selectors**: Customize and toggle exactly what appears in the top-right status area: `Logo` (gradual gradient icon), `CPU %`, `RAM %`, `Disk %`, `CPU Temp`, `Fan Speed`, `Net Speed`, `GPU %`.
- **Align and Auto-Resize**: Adjusting selections dynamically reshapes the status bar's length and shifts columns with pixel-perfect top-and-bottom text alignment.

### 4. 🔄 Smart Auto-Updater & Celsius Refactoring
- **Releases API Integration**: "Check for Updates" button seamlessly connects to GitHub Releases API.
- **Notification Dot**: A glowing red indicator overlays the Dashboard's settings gear and settings buttons when an update is available and not ignored.
- **Background Download & Auto-Mount**: Clicking "Online Update" initiates a non-blocking background download with a live percentage bar. Once finished, it automatically mounts and opens the downloaded `.dmg` file.
- **Celsius Refactoring**: All raw `°` temperature markings have been restructured into the international standard `°C`. The format has been meticulously padded (e.g. `  45°` ➡️ ` 45°C`) to preserve a fixed character length of **5**, guaranteeing strict monospaced vertical grid alignment.

---

## 🌡️ Temperature Sensors

- **CPU Temperature**: Reads the CPU die core (`Tp0b` / `TC0F`), normal range **35–90°C**.
- **GPU Temperature**: Reads the GPU die core (`Tg05`), normal range **35–80°C**.
- Apple Silicon VR voltage regulator hot spots (`Tp05`) are automatically ignored as they safely peak at 90–100°C under load.
- **Sensor Matrix**: Monitors CPU performance cores, efficiency cores, SSD, Wi-Fi, RAM, palm rest, and internal airflow.

---

## 🏎️ Performance Architecture & Telemetry Refactoring (v1.6.0 - v1.7.0 底层革命)

STATUS CTRL underwent systemic diagnostic upgrades to hardware I/O and data telemetry to eliminate all UI stuttering, yielding ultimate power efficiency and flawless telemetry calculations:

### 🌀 SMC Key Metadata Caching & Persistent Blacklist (v1.7.0 Heavyweight)
- **50% Less Physical I/O Overhead**: Introduces a thread-safe SMC Key metadata cache (`keyInfoCache`). The size and type of each SMC key are cached in-memory after their first read. Subsequent operations skip the auxiliary `kSMCGetKeyInfo` hardware query, doubling access speed and cutting SMC bus energy footprint in half.
- **Persistent Blacklist**: Unrecognized/faulty keys that fail 3 consecutive hardware reads are automatically registered into `UserDefaults` asynchronously. Subsequent launches load this blacklist immediately and skip invalid keys entirely, avoiding hardware bus blockages.
- **Precise Concurrency Locking**: Redesigned internal `cacheLock` scopes to guarantee 100% deadlock-free execution when the main thread draws UI while the background telemetry queue frequently reads SMC registers.

### 🔋 Raw Coulomb Counter Battery Reading (v1.7.0 Heavyweight)
- **Native mAh Diagnostics**: Rewrote the capacity retrieval loop in `PowerMonitor`. On Apple Silicon and modern Intel Mac models, when `AppleRawCurrentCapacity` and `AppleRawMaxCapacity` dictionary keys are exposed, STATUS CTRL bypasses computed percentage-based data to read the lossless physical milliampere-hours (mAh) straight from the hardware.
- **Fluctuation-Free Estimates**: Completely resolves minor numerical truncation errors that previously caused remaining battery runtime and time-to-full forecasts to jitter. Calculations are now 100% smooth, uniform, and precise.

### ⚡ Zero-Block Main Thread Architecture (v1.6.0 Foundation)
- **0ms Main Thread Wait**: All SMC bus interactions are delegated to high-priority background queues.
- **Non-Blocking tryLock**: The main thread immediately falls back to cache values if the SMC bus lock is contested by background activities, eliminating all potential UI lags.
- **Graceful Telemetry Caching**: All sensor arrays (CPU, GPU, Fans, Network) utilize a dual-level memory cache for smooth down-scaling.
- **Panel Visibility Lifecycle**: Background hardware polling and I/O tasks are completely suspended when the Popover panel is closed, achieving **0% background CPU / hardware overhead**.

---

## 🖥️ System Requirements

| Item | Requirement |
|------|------|
| OS | macOS 12 Monterey or higher |
| Processor | Apple Silicon (M1/M2/M3/M4) or Intel x86_64 |
| RAM Usage | ~30 MB |
| File Size | ~6 MB |

---

## ⚠️ Known Limitations

- Intel MacBook keyboard backlight relies on private APIs; compatibility on early legacy models may vary.
- Fanless models (e.g. MacBook Air) will automatically hide the fan control section.
- System upgrades (e.g. macOS 15 → 16) might require re-authorizing the helper tool.
- Ad-Hoc signed build; first-time launch requires manual permission in system settings.

---

## 🛠️ Build from Source

```bash
git clone https://github.com/HuangLonghlhlhlhlhlhlhl/multitool.git
cd multitool

# Build Universal Binary App
make

# Package DMG (exported to Desktop)
make dmg
```

Prerequisite: Xcode Command Line Tools (`xcode-select --install`)

---

## 🌟 About the Project

**STATUS CTRL** is a macOS status bar hardware monitoring and fan speed control tool that the author **uses heavily every single day** in their daily work and development.

The original motivation for developing this project was that existing tools on the market were either too resource-intensive, had noticeable UI polling lag (especially with hardware I/O blocking the main thread), or lacked comprehensive feature integration (such as power saving policies, deep memory cleaning, physical device privacy controls, and a secure scrambled keyboard). To solve this, the author carefully designed and completely refactored the underlying mechanics, utilizing non-blocking `tryLock` and multi-level memory caching to achieve **0ms UI lock contention** on the main thread, resulting in a truly seamless and lightweight experience.

After long-term personal use and experiencing firsthand the **incredible smoothness and convenience** it offers, the author decided to open-source and release it to the community! This is **by no means just a simple learning or personal study project**, but rather a highly polished, production-ready utility forged through daily real-world use, balancing premium aesthetics with peak performance.

### 💖 Follow, Star & Share Your Ideas

Your support is the author's ultimate motivation to keep iterating and optimizing! If you find STATUS CTRL helpful:
1. 🌟 Give this repository a **Star** to help others discover it!
2. 📢 Follow the author's updates, and feel free to submit an Issue if you run into any trouble.
3. 💡 **Inspire the Author**: If you have any cool, innovative, or highly practical features or ideas, please share them in the Issues or Discussions! The author will actively review and implement them.
4. ☕ **Support & Donation**: Buy the author a cup of coffee to stay energized, or sponsor some tokens for the AI assistant (that's me! 🦾) to keep evolving!

<div align="center">
  <table style="margin: 0 auto; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 20px; border: 1px solid #333;">
        <img src="wechat_qr.png" width="220px" alt="微信打赏 WeChat Pay" /><br/>
        <br/><b>Scan with WeChat to Donate</b>
      </td>
      <td align="center" style="padding: 20px; border: 1px solid #333;">
        <img src="alipay_qr.png" width="220px" alt="支付宝打赏 Alipay" /><br/>
        <br/><b>Scan with Alipay to Donate</b>
      </td>
    </tr>
  </table>
</div>

---

*Developed by HL · 2026 · Ultra-smooth, the ultimate geek productivity utility*
