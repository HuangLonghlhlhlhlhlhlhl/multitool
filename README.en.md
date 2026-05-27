# STATUS CTRL

<div align="center">

**macOS Status Bar Hardware Diagnostics & Fan Control Utility**

Real-time Temp/Battery Telemetry · Independent Dual Fan Speed Control · Power Policy Tuning · Animated Keyboard Backlight Effects · Zero-Lag Fluid Experience

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-green)
![Version](https://img.shields.io/badge/Version-1.5.1-orange)
![Size](https://img.shields.io/badge/Size-~6MB-lightgrey)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[English](README.en.md) | [简体中文](README.md)

</div>

---

## 📦 Installation

1. **Download** `STATUS CTRL-v1.5.1.dmg` from the [Latest Release](https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest).
2. Open the DMG, then drag **`STATUS CTRL.app`** into the **`Applications`** folder.
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
| 🧹 Deep RAM Clean | **[NEW]** Multi-column Memory Page with a dynamic water-level ring, live scanning of top 7 active user processes, and deep memory purge feedback. |
| 🛡️ Device Privacy Guard | **[NEW]** 4-way privacy switches (Camera, Mic, Screen, Auto Action) alongside a randomized scrambled keylogger-proof on-screen keyboard. |
| ⚙️ Customize Status Bar | **[NEW]** Dedicated settings tab with interactive macOS menu bar mockup preview to show/hide 8 status indicators with perfect alignment. |
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

v1.5.1 introduces a brand new independent dual-path energy management system:

- **🔌 AC Power**: 🚀 Turbo / ⚖️ Balanced / 🍃 Eco Silent performance presets.
- **🔋 Battery Power**: Three standalone presets + "Target System Power Limit" slider.
- **Runtime Budgeting**: Dynamically estimates and compares "Limit Budgeted Runtime" vs "Live Estimated Runtime".
- **Auto-Align Settings**: Automatically matches fan curve presets, keyboard backlight, and screen sleep timeout with the current performance level.

---

## 🛡️ Device Security & Memory Purging (New in v1.5.1)

STATUS CTRL v1.5.1 introduces three major advanced upgrades focusing on device privacy protection and system resource optimization:

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

---

## 🌡️ Temperature Sensors

- **CPU Temperature**: Reads the CPU die core (`Tp0b` / `TC0F`), normal range **35–90°C**.
- **GPU Temperature**: Reads the GPU die core (`Tg05`), normal range **35–80°C**.
- Apple Silicon VR voltage regulator hot spots (`Tp05`) are automatically ignored as they safely peak at 90–100°C under load.
- **Sensor Matrix**: Monitors CPU performance cores, efficiency cores, SSD, Wi-Fi, RAM, palm rest, and internal airflow.

---

## 🏎️ Performance Architecture (v1.5.1)

Underwent a systemic rewrite to achieve 0ms main thread lag:

- **0ms Main Thread Wait**: All hardware SMC I/O runs asynchronously on background queues.
- **Non-Blocking `tryLock`**: The UI never freezes by immediately returning cached values when the SMC bus is locked.
- **Faulty Key Blacklist**: SMC keys that fail 3 consecutive reads are permanently blacklisted to eliminate bus delays.
- **Persistent Cache**: Dual-level memory caching provides graceful fallback values for all hardware sensors.
- **Idle Silence**: Timers automatically pause when the panel is closed, reducing background CPU usage to 0%.

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
4. ☕ Feel free to sponsor the project via WeChat/Alipay to buy the author a cup of coffee!

---

*Developed by HL · 2026 · Ultra-smooth, the ultimate geek productivity utility*
