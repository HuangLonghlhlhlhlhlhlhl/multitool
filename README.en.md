# STATUS CTRL

<div align="center">

**macOS Status Bar Hardware Diagnostics & Fan Control Utility**

Real-time Temp/Battery Telemetry · Independent Dual Fan Speed Control · Power Policy Tuning · Animated Keyboard Backlight Effects · Zero-Lag Fluid Experience

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%7C%20Intel-green)
![Version](https://img.shields.io/badge/Version-1.5.0-orange)
![Size](https://img.shields.io/badge/Size-~6MB-lightgrey)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[English](README.en.md) | [简体中文](README.md)

</div>

---

## 📦 Installation

1. **Download** `STATUS CTRL-v1.5.0.dmg` from the [Latest Release](https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest).
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
| 📊 Est. Runtime Board | Deductive remaining runtime based on current discharge rate and custom power limit. |
| 🧹 One-Click RAM Clean | Force reclaiming inactive physical memory, displaying exact freed megabytes (MB). |
| 🖥️ Advanced Telemetry | Deep metrics including temperature matrix, core voltages, frequencies, and fan load. |
| 🖱️ Context Menu | Right-click the status bar icon for Settings, About, and Quit. |
| ⚙️ Settings Panel | Language toggle (Chinese/English), Launch at Login, and Sponsorship support. |

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

v1.5.0 introduces a brand new independent dual-path energy management system:

- **🔌 AC Power**: 🚀 Turbo / ⚖️ Balanced / 🍃 Eco Silent performance presets.
- **🔋 Battery Power**: Three standalone presets + "Target System Power Limit" slider.
- **Runtime Budgeting**: Dynamically estimates and compares "Limit Budgeted Runtime" vs "Live Estimated Runtime".
- **Auto-Align Settings**: Automatically matches fan curve presets, keyboard backlight, and screen sleep timeout with the current performance level.

---

## 🌡️ Temperature Sensors

- **CPU Temperature**: Reads the CPU die core (`Tp0b` / `TC0F`), normal range **35–90°C**.
- **GPU Temperature**: Reads the GPU die core (`Tg05`), normal range **35–80°C**.
- Apple Silicon VR voltage regulator hot spots (`Tp05`) are automatically ignored as they safely peak at 90–100°C under load.
- **Sensor Matrix**: Monitors CPU performance cores, efficiency cores, SSD, Wi-Fi, RAM, palm rest, and internal airflow.

---

## 🏎️ Performance Architecture (v1.5.0)

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

## 🤝 Support & Sponsorship

If you find STATUS CTRL useful, feel free to sponsor the project via Alipay or WeChat Pay!  
Open App → Settings → Sponsor & Support to scan the QR codes.

---

*Developed by HL · 2026 · For learning and personal use only*
