import SwiftUI
import Combine
import ServiceManagement
import Darwin
import IOKit

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DashboardView: View {
    
    // Core Managers
    private let smc = SMCController()
    
    // Permanent fixed path for secure execution preventing breakage when moving the App bundle
    private var smcHelperPath: String {
        return "/Library/PrivilegedHelperTools/com.hl.smchelper"
    }
    
    // Path inside the app bundle used as the source for copying
    private var embeddedHelperPath: String {
        let bundlePath = Bundle.main.bundlePath + "/Contents/MacOS/smchelper"
        if FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }
        return "/Users/h-l/Desktop/多功能小助手/smchelper"
    }

    
    // Refresh Timers
    private let statsTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private let fanRotationTimer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    private let waveTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    // UI & Hardware States
    private let telemetryQueue = DispatchQueue(label: "com.statusctrl.telemetryQueue", qos: .userInitiated)
    private let keyboardQueue = DispatchQueue(label: "com.statusctrl.keyboardQueue", qos: .background)
    @State private var isHardwareInitialized = false
    @State private var isPanelVisible = false
    @State private var isUserDraggingFan = false
    @State private var refreshTick = 0
    @State private var isRefreshing = false
    @State private var cpuTemp: Float = 42.0
    @State private var gpuTemp: Float = 40.0
    
    // Purger States
    @State private var isPowerHovered: Bool = false
    @State private var isPurging: Bool = false
    @State private var purgeProgress: Double = 0.0
    @State private var lastPurgedAmount: Double = 0.0
    @State private var showPurgeSuccess: Bool = false
    
    // Advanced hardware telemetry states
    @State private var cpuUsage: Double = 0.0          // CPU Load %
    @State private var gpuUsage: Double = 0.0          // GPU Load %
    @State private var cpuFreqPerf: Double = 0.0       // Performance Core Freq (GHz)
    @State private var cpuFreqEff: Double = 0.0        // Efficiency Core Freq (GHz)
    @State private var gpuFreq: Double = 0.0           // GPU Clock Freq (GHz)
    
    @State private var tempCpuPerf: Float = 0.0
    @State private var tempCpuEff: Float = 0.0
    @State private var tempSSD: Float = 0.0
    @State private var tempWiFi: Float = 0.0
    @State private var tempMemory: Float = 0.0
    @State private var tempPalmRest: Float = 0.0
    @State private var tempAirflow: Float = 0.0
    
    @State private var cpuVoltage: Double = 0.0
    @State private var gpuVoltage: Double = 0.0
    @State private var cpuPower: Double = 0.0
    @State private var gpuPower: Double = 0.0
    @State private var totalPower: Double = 0.0
    
    // Collapsible telemetry panel sections
    @State private var isTempExpanded: Bool = false
    @State private var isPowerExpanded: Bool = false
    @State private var isFanExpanded: Bool = false
    @State private var isFreqExpanded: Bool = false
    
    // Core CPU Monitor Instance
    private let cpuMonitor = CPUMonitor()
    
    // Modern UI Tabs and Advanced States
    @Namespace private var tabNamespace
    @State private var selectedTab: Int = 0 // 0: 清理释放, 1: 系统功能, 2: 隐私守护
    @State private var activeProcesses: [MemoryPurger.ProcessInfoItem] = []
    @State private var currentRAMUsagePercent: Double = 0.0
    @State private var scrambledKeys: [String] = []
    @State private var securePasswordInput: String = ""
    @State private var isPasswordVisible: Bool = false
    
    // Privacy Switches
    @AppStorage("cameraPrivacyEnabled") private var cameraPrivacy: Bool = true
    @AppStorage("micPrivacyEnabled") private var micPrivacy: Bool = true
    @AppStorage("screenPrivacyEnabled") private var screenPrivacy: Bool = true
    @AppStorage("autoActionPrivacyEnabled") private var autoActionPrivacy: Bool = true
    
    // Fan states — per-fan independent control
    @State private var fanCount: Int = 0
    @State private var fanSpeed: [Float] = [0.0, 0.0]          // actual RPM per fan
    @State private var fanMinSpeed: [Float] = [1200.0, 1200.0] // SMC min per fan
    @State private var fanMaxSpeed: [Float] = [6000.0, 6000.0] // SMC max per fan
    @State private var targetFanSpeed: [Float] = [2000.0, 2000.0] // target per fan
    @State private var isManualFan: Bool = false
    @State private var fanLinked: Bool = true  // true = both fans move together
    @State private var fanRotationAngle: Double = 0.0
    // 冲突警告：当用户尝试选择与功耗策略不兼容的风扇预设时显示
    @State private var fanPolicyConflictWarning: Bool = false
    
    // Asymmetric Hysteresis Smoothing
    @State private var lastAppliedFanSpeed: [Float] = [2000.0, 2000.0]
    @State private var lastHardwareSetSpeed: [Float] = [0.0, 0.0]
    
    // Fan Presets & Temp Curves
    @State private var fanPreset: Int = UserDefaults.standard.integer(forKey: "FanPresetMode")
    @State private var customCurveTemp1: Float = 40.0
    @State private var customCurveSpeed1: Float = 20.0
    @State private var customCurveTemp2: Float = 55.0
    @State private var customCurveSpeed2: Float = 45.0
    @State private var customCurveTemp3: Float = 70.0
    @State private var customCurveSpeed3: Float = 75.0
    @State private var customCurveTemp4: Float = 85.0
    @State private var customCurveSpeed4: Float = 100.0
    
    // Battery Care States
    @State private var isChargeLimitEnabled: Bool = false
    @State private var batteryLimitValue: Float = 80.0
    
    // Power Saving & Battery Saver States
    @State private var isLowPowerModeEnabled: Bool = false
    @State private var aggressiveScreenSleep: Bool = false
    @State private var disableKeyboardBacklightOnBattery: Bool = false
    
    // Keyboard Light States
    @State private var keyboardBrightness: Float = 0.5
    @State private var keyboardMode: Int = UserDefaults.standard.integer(forKey: "KeyboardLightingMode") // 0 = Static, 1 = Breathing, 2 = Wave
    @State private var breathingSpeed: Double = 4.0 // Period in seconds
    @State private var wavePhase: Double = 0.0
    
    // Power Monitor States
    @State private var powerStats = PowerMonitor.PowerStats()
    
    // Power Policy and Runtime States
    @State private var selectedPowerTab: Int = 0
    @State private var acPowerPolicy: Int = UserDefaults.standard.integer(forKey: "ACPowerPolicy")
    @State private var batteryPowerPolicy: Int = UserDefaults.standard.object(forKey: "BatteryPowerPolicy") == nil ? 1 : UserDefaults.standard.integer(forKey: "BatteryPowerPolicy")
    @State private var batteryTargetPower: Double = UserDefaults.standard.double(forKey: "BatteryTargetPower") == 0 ? 8.0 : UserDefaults.standard.double(forKey: "BatteryTargetPower")
    @State private var autoAlignBatteryPolicies: Bool = UserDefaults.standard.object(forKey: "AutoAlignBatteryPolicies") == nil ? true : UserDefaults.standard.bool(forKey: "AutoAlignBatteryPolicies")
    @State private var lastAppliedTargetPower: Double = 0.0
    
    // Interactive feedback
    @State private var messagePrompt: String = ""
    @State private var showPrivilegeWarning: Bool = false
    
    // Helper breathing variables
    @State private var breathingTask: AnyCancellable?
    @State private var breathingStartTime = Date()
    
    // Settings States
    @State private var showSettings: Bool = false
    @State private var currentLanguage: String = "zh-Hans"
    @State private var launchAtLogin: Bool = false
    @State private var donateMethod: Int = 0 // 0 = Alipay, 1 = WeChat
    @State private var qrScanOffset: CGFloat = -50.0
    @State private var showDonateAlert: Bool = false
    
    // Localization Helper
    private let translations: [String: [String: String]] = [
        "zh-Hans": [
            "title": "STATUS CTRL",
            "battery_mode": "电池供电中",
            "charger_mode": "接通电源",
            "watt": "W",
            "cpu_temp": "CPU 温度",
            "gpu_temp": "GPU 温度",
            "power_monitor": "接口输入/输出监测",
            "voltage": "实时电压",
            "current": "通道电流",
            "input_power": "输入功率",
            "battery_power": "整机瓦特",
            "mode_instructions": "物理接口工作模式说明",
            "charging_desc": "🔋 当前处于 [电能输入模式]：外部适配器通过高阶 PD 协议向电脑注入电能，供给整机运行并为电池充电。",
            "discharging_desc": "🔌 当前处于 [反向供电模式]：雷电接口支持双向传输，正向设备电池反向为外接的手机或拓展坞输出电量。",
            "battery_percent": "电量",
            "battery_health": "健康度",
            "cycle_count": "循环",
            "fan_controller": "SMC 风扇控制器",
            "fan_auto": "系统自动",
            "fan_manual": "手动强制",
            "current_speed": "当前风扇转速",
            "rpm_range": "预设范围",
            "target_speed": "设定目标转速",
            "sudo_warning": "需要超级用户权限：请以 `sudo` 在终端运行此 App",
            "auth_btn": "🔑 一键激活手动控制",
            "fanless_title": "此 MacBook 为无风扇架构",
            "fanless_desc": "系统采用全被动散热，无需物理风扇降温，静音且省电。",
            "keyboard_title": "内置键盘灯调节",
            "breathing_mode": "呼吸灯",
            "backlight_brightness": "背光亮度",
            "breathing_wave": "键盘呼吸节奏波形",
            "breathing_period": "呼吸循环周期",
            "sec": "秒",
            "port_pos": "充电适配器接入位置：",
            "left_side": "左侧",
            "right_side": "右侧",
            "port_num": "号物理雷电/USB4端口",
            "no_adapter": "🔌 外部适配器未接通 (电池独立工作中)",
            "app_ver": "Antigravity 状态栏小助手 v1.2.0",
            
            // Settings Strings
            "settings": "系统设置",
            "lang_select": "语言选择 (Language)",
            "startup": "开机启动",
            "auto_start": "开机自动启动",
            "about": "关于程序",
            "app_desc": "一个轻量、强悍的 macOS 状态栏硬件诊断与控制工具。支持实时电压/电流监测、智能风扇控制与键盘背光灯呼吸特效。",
            "author": "开发者: Antigravity 团队",
            "copyright": "版权所有 © 2026. 保留所有权利。",
            "donate": "赞助与支持",
            "donate_desc": "如果您觉得这个工具对您有所帮助，欢迎赞助支持，帮助我们持续优化它！",
            "alipay": "支付宝 💙",
            "wechat": "微信支付 💚",
            "scan_qr": "点击或扫描二维码进行赞助",
            "thank_you": "感谢您的支持！",
            "donate_success_msg": "您的支持是我们不断优化的动力！祝您使用愉快！✨",
            "close": "关闭",
            "active_port_charge": "已接入",
            "keyboard_mode": "灯效模式",
            "mode_static": "常亮",
            "mode_breathing": "渐变呼吸",
            "mode_wave": "交替波浪",
            "wave_desc": "左侧渐亮右侧渐暗，往复波动",
            "breathing_status": "✨ 键盘背光均匀呼吸中...",
            "wave_status": "🌊 键盘背光交替波浪中...",
            "battery_care": "电池保养与充电限制",
            "charge_limit_enabled": "开启充电上限限制",
            "charge_limit_value": "充电限制百分比",
            "battery_care_desc_silicon": "Apple Silicon (M1/M2/M3) 支持限制充电至 80% 以保护电池健康。",
            "battery_care_desc_intel": "Intel 架构 MacBook 支持设置精确的充电上限百分比（建议 80%）以保护电池健康。",
            "fan_preset_title": "温控调节预设",
            "fan_preset_auto": "官方默认 (系统托管)",
            "fan_preset_silent": "静音优先 🍃 (低温省电)",
            "fan_preset_balanced": "标准均衡 ⚖️ (平稳安静)",
            "fan_preset_turbo": "游戏极客 🚀 (强劲散热)",
            "fan_preset_custom": "自定义温控曲线 📈",
            "fan_curve_node": "节点",
            "power_saving_title": "智能功耗管理与超强续航",
            "low_power_mode": "系统低功耗模式 (限制功耗)",
            "low_power_mode_desc": "降低处理器时钟频率，限制峰值瓦特(TDP)，关闭高负载渲染，大幅延长约 30%-50% 的电池续航时间。",
            "aggressive_sleep": "屏幕智能极速休眠 (2分钟)",
            "aggressive_sleep_desc": "在使用电池供电且无操作时，智能将屏幕休眠缩短至2分钟，最大化削减屏幕显示能耗。",
            "disable_backlight_on_battery": "电池供电时自动关闭键盘灯",
            "disable_backlight_on_battery_desc": "当断开适配器使用电池时，自动将键盘背光亮度降低为0，静默守卫电量。",
            "live_discharge_rate": "实时整机功耗",
            "power_policy_title": "功耗策略与续航推演",
            "ac_mode_tab": "🔌 电源模式",
            "battery_mode_tab": "🔋 电池模式",
            "target_power_limit": "目标整机功耗限额",
            "deductive_runtime": "限额预算可用续航",
            "actual_runtime": "实时消耗预计续航",
            "efficiency_gain": "续航增益幅度",
            "auto_align_policies": "智能功耗对齐开关 (自动优化)",
            "power_policy_level": "处理器性能释放策略",
            "ac_policy_turbo": "🚀 极致性能 (不限功耗)",
            "ac_policy_balanced": "⚖️ 标准均衡 (能耗优化)",
            "ac_policy_eco": "🍃 极致静音 (能耗极低)",
            "opt_active_deep": "极致节能：限制时钟，关闭键盘背光，极速休眠",
            "opt_active_mid": "中度节能：限制时钟，键盘背光微亮，标准休眠",
            "opt_active_none": "性能释放：不加限制，屏幕与背光按设定运行",
            
            // Advanced Hardware Telemetry
            "system_telemetry": "系统高级硬件遥测",
            "temp_section": "温度传感器矩阵",
            "power_voltage_section": "电压与功耗监测",
            "fan_section_title": "物理风扇遥测",
            "freq_section": "核心工作频率",
            "cpu_perf_cores": "CPU 性能核心",
            "cpu_eff_cores": "CPU 能效核心",
            "ssd_temp": "SSD 固态硬盘",
            "wifi_temp": "Wi-Fi 芯片",
            "ram_temp": "内存 (RAM)",
            "palm_temp": "掌托感应",
            "airflow_temp": "内部气流",
            "gpu_temp_label": "显卡 (GPU)",
            "cpu_voltage_label": "CPU 工作电压",
            "gpu_voltage_label": "显卡工作电压",
            "battery_voltage_label": "电池工作电压",
            "cpu_power_label": "CPU 核心功耗",
            "gpu_power_label": "显卡核心功耗",
            "total_power_label": "整机总功耗",
            "fan_load_text": "风扇负荷",
            "cpu_freq_perf": "CPU 性能核频率",
            "cpu_freq_eff": "CPU 能效核频率",
            "gpu_freq_label": "GPU 工作频率",
            "left_fan": "左风扇",
            "right_fan": "右风扇",
            "fan_linked": "（联动）"
        ],
        "en": [
            "title": "STATUS CTRL",
            "battery_mode": "On Battery",
            "charger_mode": "AC Connected",
            "watt": "W",
            "cpu_temp": "CPU Temp",
            "gpu_temp": "GPU Temp",
            "power_monitor": "USB-C Port Diagnostics",
            "voltage": "Voltage",
            "current": "Current",
            "input_power": "Input Power",
            "battery_power": "System Power",
            "mode_instructions": "Physical Port Work Modes",
            "charging_desc": "🔋 Currently in [Power Input Mode]: External adapter supplies power via USB PD protocol to run the system and charge the battery.",
            "discharging_desc": "🔌 Currently in [Reverse Power Mode]: Thunderbolt port supports bidirectional transmission, battery powering external phone or hub.",
            "battery_percent": "Charge",
            "battery_health": "Health",
            "cycle_count": "Cycles",
            "fan_controller": "SMC Fan Controller",
            "fan_auto": "Auto",
            "fan_manual": "Manual Force",
            "current_speed": "Current Speed",
            "rpm_range": "Preset Range",
            "target_speed": "Set Target Speed",
            "sudo_warning": "Privileges Required: Run this App with `sudo` in Terminal",
            "auth_btn": "🔑 One-Click Authorize",
            "fanless_title": "MacBook Air Fanless Architecture",
            "fanless_desc": "Passive cooling design. Completely silent, dust-free, and energy efficient.",
            "keyboard_title": "Keyboard Backlight",
            "breathing_mode": "Breathing",
            "backlight_brightness": "Brightness",
            "breathing_wave": "Breathing Rhythm Waveform",
            "breathing_period": "Breathing Period",
            "sec": "s",
            "port_pos": "Adapter Connected At: ",
            "left_side": "Left Side",
            "right_side": "Right Side",
            "port_num": " USB4/Thunderbolt Port",
            "no_adapter": "🔌 AC Power Disconnected (Running on Battery)",
            "app_ver": "Antigravity Status Bar Helper v1.2.0",
            
            // Settings Strings
            "settings": "Settings",
            "lang_select": "Select Language",
            "startup": "Startup Behavior",
            "auto_start": "Launch App at Login",
            "about": "About App",
            "app_desc": "A lightweight, powerful macOS status bar utility for hardware diagnostics and controls. Features real-time USB-C diagnostics, fan override, and animated keyboard breathing patterns.",
            "author": "Developer: Antigravity Team",
            "copyright": "Copyright © 2026. All rights reserved.",
            "donate": "Sponsor & Support",
            "donate_desc": "If you find this utility useful, please consider sponsoring to support its continuous development!",
            "alipay": "Alipay 💙",
            "wechat": "WeChat Pay 💚",
            "scan_qr": "Click or scan the QR code to sponsor",
            "thank_you": "Thank You for Your Support!",
            "donate_success_msg": "Your generous support drives our continuous updates! Have a wonderful day! ✨",
            "close": "Close",
            "active_port_charge": "Connected",
            "keyboard_mode": "Lighting Mode",
            "mode_static": "Static",
            "mode_breathing": "Breathing",
            "mode_wave": "Wave Shift",
            "wave_desc": "Left and right alternating wave",
            "breathing_status": "✨ Keyboard pulsing uniformly...",
            "wave_status": "🌊 Keyboard wave shifting...",
            "battery_care": "Battery Care & Charge Limit",
            "charge_limit_enabled": "Enable Charge Limit",
            "charge_limit_value": "Charge Limit",
            "battery_care_desc_silicon": "Apple Silicon (M1/M2/M3) supports limiting battery charge to 80% to protect battery longevity.",
            "battery_care_desc_intel": "Intel MacBooks support setting a custom charge limit percentage (80% recommended) for battery preservation.",
            "fan_preset_title": "Fan Control Presets",
            "fan_preset_auto": "Auto (macOS Controlled)",
            "fan_preset_silent": "Silent/Eco 🍃",
            "fan_preset_balanced": "Balanced ⚖️",
            "fan_preset_turbo": "Turbo/Max 🚀",
            "fan_preset_custom": "Custom Curve 📈",
            "fan_curve_node": "Node",
            "power_saving_title": "Smart Power & Battery Saver",
            "low_power_mode": "Low Power Mode (Limit TDP)",
            "low_power_mode_desc": "Limits processor CPU/GPU clocks, lowers peak TDP wattage, disables background tasks, and extends battery runtimes by 30%-50%.",
            "aggressive_sleep": "Aggressive Screen Sleep (2 Mins)",
            "aggressive_sleep_desc": "Saves display panel power by aggressively shutting off the screen after 2 minutes of idle on battery.",
            "disable_backlight_on_battery": "Disable Keyboard Light on Battery",
            "disable_backlight_on_battery_desc": "Instantly dims the keyboard backlight to 0% when power adapter is disconnected, saving valuable Watts.",
            "live_discharge_rate": "Live Discharge Rate",
            "power_policy_title": "Power Policy & Runtime",
            "ac_mode_tab": "🔌 AC Power",
            "battery_mode_tab": "🔋 Battery Power",
            "target_power_limit": "Target Power Limit",
            "deductive_runtime": "Budgeted Est. Runtime",
            "actual_runtime": "Live Est. Runtime",
            "efficiency_gain": "Runtime Gain",
            "auto_align_policies": "Auto-Align Policies",
            "power_policy_level": "CPU Performance Level",
            "ac_policy_turbo": "🚀 Turbo (Max Perf)",
            "ac_policy_balanced": "⚖️ Balanced (Normal)",
            "ac_policy_eco": "🍃 Eco Silent (Low TDP)",
            "opt_active_deep": "Deep Saving: TDP Capped, Keyboard Light OFF, Display Sleep (1 Min)",
            "opt_active_mid": "Mid Saving: TDP Capped, Keyboard Dimmed, Display Sleep (2 Mins)",
            "opt_active_none": "Performance Mode: No limits, screen/backlight default",
            
            // Advanced Hardware Telemetry
            "system_telemetry": "System Hardware Telemetry",
            "temp_section": "Temperature Sensors",
            "power_voltage_section": "Power & Voltage Diagnostics",
            "fan_section_title": "Physical Fan Telemetry",
            "freq_section": "Core Frequencies",
            "cpu_perf_cores": "CPU Performance Cores",
            "cpu_eff_cores": "CPU Efficiency Cores",
            "ssd_temp": "SSD Solid State Drive",
            "wifi_temp": "Wi-Fi Module",
            "ram_temp": "Memory (RAM)",
            "palm_temp": "Palm Rest Region",
            "airflow_temp": "Internal Airflow",
            "gpu_temp_label": "Graphics (GPU) Core",
            "cpu_voltage_label": "CPU Core Voltage",
            "gpu_voltage_label": "GPU Core Voltage",
            "battery_voltage_label": "Battery Output Voltage",
            "cpu_power_label": "CPU Active Power",
            "gpu_power_label": "GPU Active Power",
            "total_power_label": "Total System TDP",
            "fan_load_text": "Fan Workload",
            "cpu_freq_perf": "CPU Perf Core Freq",
            "cpu_freq_eff": "CPU Eff Core Freq",
            "gpu_freq_label": "GPU Clock Speed",
            "left_fan": "Left Fan",
            "right_fan": "Right Fan",
            "fan_linked": " (Linked)"
        ]
    ]
    
    private func t(_ key: String) -> String {
        let dict = translations[currentLanguage] ?? translations["zh-Hans"]!
        return dict[key] ?? key
    }
    
    private func getBatteryTimeText() -> String {
        let isZh = currentLanguage == "zh-Hans"
        if powerStats.isConnected {
            if powerStats.isCharging {
                let time = powerStats.avgTimeToFull
                if time > 0 && time != 65535 {
                    let hours = time / 60
                    let mins = time % 60
                    if hours > 0 {
                        return isZh ? "预计 \(hours)小时\(mins)分钟 充满" : "Est. \(hours)h \(mins)m to Full"
                    } else {
                        return isZh ? "预计 \(mins)分钟 充满" : "Est. \(mins)m to Full"
                    }
                } else {
                    return isZh ? "正在计算充电时间..." : "Calculating charge time..."
                }
            } else {
                return isZh ? "已接通电源 (未充电/已充满)" : "AC Connected (Not Charging)"
            }
        } else {
            let time = powerStats.timeRemaining
            if time > 0 && time != 65535 {
                let hours = time / 60
                let mins = time % 60
                if hours > 0 {
                    return isZh ? "预计可用 \(hours)小时\(mins)分钟" : "Est. \(hours)h \(mins)m left"
                } else {
                    return isZh ? "预计可用 \(mins)分钟" : "Est. \(mins)m left"
                }
            } else {
                return isZh ? "正在计算剩余续航..." : "Calculating runtime..."
            }
        }
    }
    
    struct SkeletonRow: View {
        @State private var isAnimating = false
        var width: CGFloat
        var height: CGFloat
        var body: some View {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: height)
                .opacity(isAnimating ? 0.45 : 0.85)
                .onAppear {
                    withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
        }
    }

    private var skeletonDashboardView: some View {
        VStack(spacing: 0) {
            // Header 骨架
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonRow(width: 140, height: 18)
                    SkeletonRow(width: 220, height: 12)
                }
                Spacer()
                SkeletonRow(width: 36, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // 主体分栏骨架
            HStack(alignment: .top, spacing: 12) {
                // 左侧骨架栏
                VStack(spacing: 12) {
                    // 系统遥测卡片骨架
                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonRow(width: 100, height: 16)
                        Divider().background(Color.white.opacity(0.05))
                        HStack(spacing: 16) {
                            SkeletonRow(width: 65, height: 65) // 环形图占位
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonRow(width: 120, height: 12)
                                SkeletonRow(width: 90, height: 10)
                                SkeletonRow(width: 140, height: 10)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(14)
                    
                    // 风扇卡片骨架
                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonRow(width: 80, height: 16)
                        Divider().background(Color.white.opacity(0.05))
                        HStack(spacing: 12) {
                            SkeletonRow(width: 44, height: 44) // 风扇圆形占位
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonRow(width: 140, height: 12)
                                SkeletonRow(width: 100, height: 10)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(14)
                }
                .frame(maxWidth: .infinity)
                
                // 右侧骨架栏
                VStack(spacing: 12) {
                    // 能耗卡片骨架
                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonRow(width: 120, height: 16)
                        Divider().background(Color.white.opacity(0.05))
                        SkeletonRow(width: 200, height: 12)
                        HStack(spacing: 8) {
                            SkeletonRow(width: 70, height: 28)
                            SkeletonRow(width: 70, height: 28)
                            SkeletonRow(width: 70, height: 28)
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(14)
                    
                    // 物理能耗延长卡片骨架
                    VStack(alignment: .leading, spacing: 14) {
                        SkeletonRow(width: 150, height: 16)
                        Divider().background(Color.white.opacity(0.05))
                        SkeletonRow(width: 240, height: 80) // 渲染曲线图占位
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(14)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 680, height: 530)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                RadialGradient(colors: [Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 280)
            }
        )
        .preferredColorScheme(.dark)
    }

    @State private var currentPage: Int = 0
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if !isHardwareInitialized {
                skeletonDashboardView
                    .transition(.opacity)
            } else {
                ZStack {
                    // ── Main Panel ──
                    VStack(spacing: 0) {
                        // Header (fixed)
                        headerSection
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                        Divider()
                            .background(Color.white.opacity(0.06))

                        // Segmented Tab Switched at the top (with namespaces and nice segmented buttons)
                        HStack(spacing: 0) {
                            ForEach(0..<3) { idx in
                                Button(action: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        selectedTab = idx
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        HStack(spacing: 6) {
                                            Image(systemName: idx == 0 ? "trash.fill" : (idx == 1 ? "gauge.with.needle.fill" : "lock.shield.fill"))
                                                .font(.system(size: 11))
                                            Text(idx == 0 ? "清理释放" : (idx == 1 ? "系统功能" : "隐私守护"))
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundColor(selectedTab == idx ? .white : .white.opacity(0.4))
                                        
                                        // Active indicator line
                                        ZStack {
                                            Capsule()
                                                .fill(Color.clear)
                                                .frame(height: 3)
                                            if selectedTab == idx {
                                                Capsule()
                                                    .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                                                    .frame(height: 3)
                                                    .matchedGeometryEffect(id: "activeTabLine", in: tabNamespace)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                        Divider()
                            .background(Color.white.opacity(0.06))

                        if selectedTab == 0 {
                            memoryCleanPageView
                                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                        } else if selectedTab == 1 {
                            originalDashboardView
                                .transition(.opacity)
                        } else {
                            privacyGuardPageView
                                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                        }
                    }
                    .blur(radius: showSettings ? 12 : 0)

                    // Settings overlay
                    if showSettings {
                        settingsSection
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(width: 680, height: 530)
        .background(
            ScrollWheelDetector { deltaY in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                    if deltaY > 1.5 && currentPage > 0 {
                        currentPage = 0
                    } else if deltaY < -1.5 && currentPage < 1 {
                        currentPage = 1
                    }
                }
            }
        )
        .background(
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                RadialGradient(colors: [Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 280)
            }
        )
        .preferredColorScheme(.dark)
        .onAppear {
            UserDefaults.standard.set("zh-Hans", forKey: "AppLanguage")
            currentLanguage = "zh-Hans"
            isPanelVisible = true
            initializeHardware()
        }
        .onDisappear {
            isPanelVisible = false
        }
        .onReceive(statsTimer) { _ in refreshStats() }
        .onReceive(fanRotationTimer) { _ in updateFanRotation() }
        .onReceive(waveTimer) { _ in updateWaveAnimation() }
    }

    private var originalDashboardView: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack {
                // Page 0
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) {
                                systemTelemetrySection
                                if fanCount > 0 {
                                    fanSection
                                } else {
                                    fanlessSection
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            VStack(spacing: 12) {
                                powerSection
                                powerSavingSection
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .frame(width: geo.size.width, height: height)
                .offset(y: (0 - CGFloat(currentPage)) * height + dragOffset)
                
                // Page 1
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            batteryCareSection
                                .frame(maxWidth: .infinity)
                            keyboardSection
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .frame(width: geo.size.width, height: height)
                .offset(y: (1 - CGFloat(currentPage)) * height + dragOffset)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let translation = value.translation.height
                        // Add friction when dragging out of bounds
                        if currentPage == 0 && translation > 0 {
                            dragOffset = translation * 0.3
                        } else if currentPage == 1 && translation < 0 {
                            dragOffset = translation * 0.3
                        } else {
                            dragOffset = translation
                        }
                    }
                    .onEnded { value in
                        let translation = value.translation.height
                        let threshold = height * 0.15 // 15% is extremely responsive
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            if translation < -threshold && currentPage < 1 {
                                currentPage = 1
                            } else if translation > threshold && currentPage > 0 {
                                currentPage = 0
                            }
                            dragOffset = 0
                        }
                    }
            )

            // ── 右侧极简竖向圆点指示器 ──
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { idx in
                    Capsule()
                        .fill(currentPage == idx
                            ? Color(red: 0.18, green: 0.62, blue: 0.95)
                            : Color.white.opacity(0.18))
                        .frame(width: 4, height: currentPage == idx ? 18 : 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        .contentShape(Rectangle())
                        .focusable(false)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                currentPage = idx
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 7)
        }
    }
    
    private func getRAMUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0.0 }
        
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        
        let activePages = Double(stats.active_count)
        let wirePages = Double(stats.wire_count)
        let compressedPages = Double(stats.compressor_page_count)
        let freePages = Double(stats.free_count)
        let inactivePages = Double(stats.inactive_count)
        
        let usedPages = activePages + wirePages + compressedPages
        let totalPages = usedPages + freePages + inactivePages
        
        guard totalPages > 0 else { return 0.0 }
        return (usedPages / totalPages) * 100.0
    }
    
    private func reshuffleKeyboard() {
        let baseKeys = (0...9).map { String($0) } + ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"]
        scrambledKeys = baseKeys.shuffled()
    }
    
    private var passwordStrengthLabel: String {
        let len = securePasswordInput.count
        if len == 0 { return "" }
        
        let hasNumber = securePasswordInput.contains(where: { $0.isNumber })
        let hasLetter = securePasswordInput.contains(where: { $0.isLetter })
        
        if len >= 10 && hasNumber && hasLetter {
            return "强"
        } else if len >= 6 {
            return "中"
        } else {
            return "弱"
        }
    }
    
    private var passwordStrengthColor: Color {
        let label = passwordStrengthLabel
        if label == "强" {
            return Color.green
        } else if label == "中" {
            return Color.orange
        } else {
            return Color.red
        }
    }
    
    private var memoryCleanPageView: some View {
        HStack(spacing: 16) {
            // Left Column: Circular gauge and Clean trigger
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    Text("内存状态")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Circular Gauge
                    ZStack {
                        // Background track
                        Circle()
                            .stroke(Color.white.opacity(0.06), lineWidth: 14)
                            .frame(width: 140, height: 140)
                        
                        // Active track (gradient)
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(currentRAMUsagePercent / 100.0, 1.0)))
                            .stroke(
                                LinearGradient(
                                    colors: [Color(red: 0.00, green: 0.95, blue: 1.00), Color(red: 0.62, green: 0.00, blue: 1.00)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round)
                            )
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: currentRAMUsagePercent)
                        
                        // Shadow glow
                        Circle()
                            .trim(from: 0.0, to: CGFloat(min(currentRAMUsagePercent / 100.0, 1.0)))
                            .stroke(Color.cyan.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(-90))
                            .blur(radius: 6)
                        
                        // Center text
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f%%", currentRAMUsagePercent))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("已用空间")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 150, height: 150)
                    .padding(.vertical, 8)
                    
                    // Diagnosis message
                    Text(currentRAMUsagePercent > 75.0 ? "系统内存吃紧，请及时清理" : (currentRAMUsagePercent > 50.0 ? "运行状态良好，继续保持" : "内存非常充足，感觉棒极了"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(currentRAMUsagePercent > 75.0 ? Color(red: 1.0, green: 0.35, blue: 0.35) : (currentRAMUsagePercent > 50.0 ? Color.cyan : Color(red: 0.22, green: 0.80, blue: 0.45)))
                        .multilineTextAlignment(.center)
                        .frame(height: 24)
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                
                // Clean Button
                Button(action: {
                    triggerMemoryPurge()
                }) {
                    HStack(spacing: 8) {
                        if isPurging {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                                .brightness(2.0)
                            Text("深度释放中...")
                                .font(.system(size: 13, weight: .bold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                            Text(showPurgeSuccess ? String(format: "已整理 %.0f MB", lastPurgedAmount) : "一键释放物理内存")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        LinearGradient(
                            colors: isPurging
                                ? [Color.gray.opacity(0.3), Color.gray.opacity(0.3)]
                                : (showPurgeSuccess ? [Color(red: 0.22, green: 0.80, blue: 0.45), Color(red: 0.15, green: 0.60, blue: 0.35)] : [Color(red: 0.18, green: 0.62, blue: 0.95), Color(red: 0.62, green: 0.32, blue: 0.88)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(color: (isPurging ? Color.clear : (showPurgeSuccess ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))), radius: 6, x: 0, y: 3)
                }
                .disabled(isPurging)
                .buttonStyle(.plain)
            }
            .frame(width: 200)
            
            // Right Column: Process usage list
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "app.badge.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.cyan)
                    Text("活跃应用内存占用排行")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("前 7 位活跃应用")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 4)
                
                VStack(spacing: 8) {
                    if activeProcesses.isEmpty {
                        // Loading / Empty state
                        VStack(spacing: 12) {
                            Spacer()
                            ProgressView()
                                .controlSize(.regular)
                            Text("正在分析系统活跃应用...")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(12)
                    } else {
                        // Display List
                        ForEach(activeProcesses) { proc in
                            HStack(spacing: 12) {
                                // Mini icon mockup
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 28, height: 28)
                                    
                                    Image(systemName: proc.name == "Google Chrome" ? "safari.fill" : (proc.name == "WeChat" ? "message.fill" : (proc.name == "VS Code" ? "chevron.left.forwardslash.chevron.right" : "app.dashed")))
                                        .font(.system(size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(proc.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    
                                    // Simulated scale indicator
                                    GeometryReader { innerGeo in
                                        let maxMem = activeProcesses.first?.memoryMB ?? 1000.0
                                        let width = CGFloat(proc.memoryMB / maxMem) * innerGeo.size.width
                                        
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(LinearGradient(colors: [.cyan.opacity(0.6), .purple.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(width, 4.0), height: 4)
                                    }
                                    .frame(height: 4)
                                }
                                
                                Spacer()
                                
                                Text(String(format: "%.1f %@", proc.memoryMB, proc.unit))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            )
                        }
                        
                        Spacer()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
    
    private var privacyGuardPageView: some View {
        HStack(spacing: 16) {
            // Left Column: Bento Grid of 4 Privacy Switches
            VStack(spacing: 12) {
                Text("实时设备隐私保护")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    PrivacySwitchCard(
                        title: "摄像头保护",
                        subtitle: cameraPrivacy ? "实时防偷窥监控" : "监控已暂停",
                        icon: "video.fill",
                        color: Color.green,
                        isEnabled: $cameraPrivacy
                    )
                    
                    PrivacySwitchCard(
                        title: "麦克风防窃听",
                        subtitle: micPrivacy ? "声敏防护运行中" : "监控已暂停",
                        icon: "mic.fill",
                        color: Color.cyan,
                        isEnabled: $micPrivacy
                    )
                    
                    PrivacySwitchCard(
                        title: "屏幕隐私防窥",
                        subtitle: screenPrivacy ? "防截屏监控运行" : "监控已暂停",
                        icon: "macwindow",
                        color: Color.purple,
                        isEnabled: $screenPrivacy
                    )
                    
                    PrivacySwitchCard(
                        title: "自动操作卫士",
                        subtitle: autoActionPrivacy ? "高危操作阻断已启" : "监控已暂停",
                        icon: "hand.raised.fill",
                        color: Color.pink,
                        isEnabled: $autoActionPrivacy
                    )
                }
                
                // Banner Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                        Text("全景安全隐私防护")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("隐私守护模块可在系统级防护任何未授权的应用悄悄调用您的麦克风、摄像头或屏幕，提供一键阻断与防截图安全过滤。")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(4)
                }
                .padding(12)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                
                Spacer()
            }
            .frame(width: 320)
            
            // Right Column: Secure Anti-Keylogger Scrambled Keyboard
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                    Text("物理防窥乱码键盘")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button(action: {
                        reshuffleKeyboard()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                            Text("重洗")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.cyan)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                
                // Password display area with clean controls
                HStack(spacing: 8) {
                    if isPasswordVisible {
                        Text(securePasswordInput.isEmpty ? "输入安全密码..." : securePasswordInput)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(securePasswordInput.isEmpty ? .white.opacity(0.3) : .white)
                    } else {
                        Text(securePasswordInput.isEmpty ? "输入安全密码..." : String(repeating: "•", count: securePasswordInput.count))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(securePasswordInput.isEmpty ? .white.opacity(0.3) : .white)
                    }
                    
                    Spacer()
                    
                    if !securePasswordInput.isEmpty {
                        // Strength indicator
                        Text(passwordStrengthLabel)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(passwordStrengthColor.opacity(0.2))
                            .foregroundColor(passwordStrengthColor)
                            .cornerRadius(4)
                        
                        // Clear button
                        Button(action: { securePasswordInput = "" }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        
                        // Visibility toggle
                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        
                        // Copy button
                        Button(action: {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(securePasswordInput, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color.black.opacity(0.4))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                
                // Shuffled keys grid (6x6)
                VStack(spacing: 6) {
                    if scrambledKeys.isEmpty {
                        ProgressView()
                    } else {
                        let rows = Array(0..<6)
                        ForEach(rows, id: \.self) { r in
                            HStack(spacing: 6) {
                                ForEach(0..<6) { c in
                                    let idx = r * 6 + c
                                    if idx < scrambledKeys.count {
                                        let key = scrambledKeys[idx]
                                        Button(action: {
                                            if securePasswordInput.count < 16 {
                                                securePasswordInput.append(key)
                                            }
                                        }) {
                                            Text(key)
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(Color.white.opacity(0.04))
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(ScrambledKeyButtonStyle())
                                    }
                                }
                            }
                            .frame(height: 34)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
                
                Text("乱码键盘可在点击输入时抵御截屏、按键木马与物理视线偷窥。")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onAppear {
            if scrambledKeys.isEmpty {
                reshuffleKeyboard()
            }
        }
    }

    // MARK: - Sub-Sections

    // 1. Header View
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("title"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(powerStats.isConnected ? Color(red: 0.22, green: 0.80, blue: 0.45) : Color(red: 0.95, green: 0.60, blue: 0.18))
                        .frame(width: 8, height: 8)
                        .shadow(color: (powerStats.isConnected ? Color(red: 0.22, green: 0.80, blue: 0.45) : Color(red: 0.95, green: 0.60, blue: 0.18)).opacity(0.5), radius: 3)
                    
                    Text(powerStats.isConnected ? "\(t("charger_mode")) (\(Int(powerStats.adapterPower))\(t("watt")))" : t("battery_mode"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Temperature Quick Badges, One-Click Memory Purge & Settings Trigger
            HStack(spacing: 8) {
                tempBadge(title: "CPU", temp: cpuTemp, color: Color(red: 0.18, green: 0.62, blue: 0.95))
                tempBadge(title: "GPU", temp: gpuTemp, color: Color(red: 0.62, green: 0.32, blue: 0.88))
                if powerStats.hasBattery {
                    tempBadge(title: "BATT", temp: Float(powerStats.batteryTemperature), color: Color(red: 0.22, green: 0.80, blue: 0.45))
                }
                
                // One-Click Memory Purge container
                HStack(spacing: 6) {
                    if isPowerHovered || isPurging || showPurgeSuccess {
                        Button(action: {
                            if !isPurging {
                                triggerMemoryPurge()
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isPurging {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                        .brightness(2.0)
                                    Text("整理中...")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                } else if showPurgeSuccess {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                    Text(String(format: "已整理 %.0fM", lastPurgedAmount))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.green)
                                } else {
                                    Text("🧹 一键整理内存")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                showPurgeSuccess ?
                                    LinearGradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                    LinearGradient(colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(showPurgeSuccess ? Color.green.opacity(0.3) : Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: showPurgeSuccess ? Color.green.opacity(0.2) : Color.purple.opacity(0.2), radius: 4)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                    }
                    
                    // Power Button triggering exit on click
                    Button(action: {
                        NSApp.terminate(nil)
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(8)
                            .background(Color.red.opacity(0.08))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .onHover { hovering in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isPowerHovered = hovering
                    }
                }
                
                // Settings Gear Button styled properly to prevent blue focus rings
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSettings.toggle()
                    }
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
    }
    
    private func tempBadge(title: String, temp: Float, color: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
            Text(String(format: "%.1f°C", temp))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // 2. Power Section (Electric Diagnostic Card)
    private var powerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "bolt.charge.fill")
                    .foregroundColor(powerStats.isConnected ? Color(red: 0.22, green: 0.80, blue: 0.45) : .gray)
                Text(t("power_monitor"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                
                if powerStats.isConnected {
                    Text(powerStats.adapterName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(4)
                }
            }
            
            // Grid Layout for Voltage, Current, Power
            HStack(spacing: 10) {
                // Voltage Card
                metricGridCard(
                    title: t("voltage"),
                    value: String(format: "%.2f V", powerStats.isConnected ? powerStats.adapterVoltage : powerStats.batteryVoltage),
                    icon: "waveform.path.ecg",
                    color: Color(red: 0.18, green: 0.62, blue: 0.95)
                )
                
                // Current Card
                metricGridCard(
                    title: t("current"),
                    value: String(format: "%.2f A", powerStats.isConnected ? powerStats.adapterCurrent : abs(powerStats.batteryCurrent)),
                    icon: "arrow.left.and.right",
                    color: Color(red: 0.95, green: 0.60, blue: 0.18)
                )
                
                // Power Card
                metricGridCard(
                    title: powerStats.isCharging ? t("input_power") : t("battery_power"),
                    value: String(format: "%.1f W", powerStats.isConnected && powerStats.isCharging ? (powerStats.adapterVoltage * powerStats.adapterCurrent) : powerStats.batteryPower),
                    icon: "bolt.fill",
                    color: Color(red: 0.22, green: 0.80, blue: 0.45)
                )
            }
            
            // Laptop schematic showing plugged port
            LaptopSchematicView(
                activePort: powerStats.activePortIndex,
                rightPortCount: powerStats.rightPortCount,
                currentLanguage: currentLanguage
            )
            .padding(.vertical, 4)
            
            // Port Working Mode Instructions
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                    Text(t("mode_instructions"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                let modeText = powerStats.isConnected ? t("charging_desc") : t("discharging_desc")
                
                Text(modeText)
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.45))
                    .lineSpacing(3)
            }
            .padding(10)
            .background(Color.white.opacity(0.02))
            .cornerRadius(10)
            
            // Battery Health Info Panel
            if powerStats.hasBattery {
                VStack(spacing: 8) {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "battery.100")
                                .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                            Text("\(t("battery_percent")): \(powerStats.stateOfCharge)%")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Text("\(t("battery_health")): \(powerStats.batteryHealthPercent)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Spacer()
                        
                        let cycleText = currentLanguage == "zh-Hans" ? "循环: \(powerStats.batteryCycleCount) 次" : "Cycles: \(powerStats.batteryCycleCount)"
                        Text(cycleText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 4)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 2)
                    
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                            Text(currentLanguage == "zh-Hans" ? String(format: "电池温度: %.1f°C", powerStats.batteryTemperature) : String(format: "Battery Temp: %.1f°C", powerStats.batteryTemperature))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            let timeText = getBatteryTimeText()
                            Image(systemName: powerStats.isConnected ? "bolt.hourglass.fill" : "hourglass.badge.plus")
                                .foregroundColor(powerStats.isCharging ? Color(red: 0.22, green: 0.80, blue: 0.45) : Color(red: 0.95, green: 0.60, blue: 0.18))
                            Text(timeText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // 2b. Battery Care & Preservation Section
    private var batteryCareSection: some View {
        VStack(spacing: 12) {
            // Header Row
            HStack {
                Image(systemName: "battery.100.bolt")
                    .font(.system(size: 14))
                    .foregroundColor(isChargeLimitEnabled ? Color(red: 0.22, green: 0.80, blue: 0.45) : .gray)
                    .shadow(color: Color(red: 0.22, green: 0.80, blue: 0.45).opacity(isChargeLimitEnabled ? 0.4 : 0), radius: 4)
                
                Text(t("battery_care"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                // Toggle Button for limit with spring feedback animation
                Toggle("", isOn: Binding(
                    get: { isChargeLimitEnabled },
                    set: { val in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleChargeLimit(val)
                        }
                    }
                ))
                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.22, green: 0.80, blue: 0.45)))
                .labelsHidden()
                .scaleEffect(0.8)
            }
            
            // Slider / Custom details
            let isSilicon = smc.readKey("FS! ") == nil
            
            if isChargeLimitEnabled {
                VStack(spacing: 10) {
                    if isSilicon {
                        // Silicon is locked to 80% natively in SMC
                        HStack {
                            Text(currentLanguage == "zh-Hans" ? "健康保养限额 (已固定):" : "Care Limit (Fixed):")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("80%")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    } else {
                        // Intel can set custom limit
                        VStack(spacing: 6) {
                            HStack {
                                Text(t("charge_limit_value"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text("\(Int(batteryLimitValue))%")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                            }
                            
                            Slider(value: $batteryLimitValue, in: 50...100, step: 5) {
                                Text("")
                            } minimumValueLabel: {
                                Text("50%").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                            } maximumValueLabel: {
                                Text("100%").font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                            }
                            .accentColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                            .onChange(of: batteryLimitValue) { newValue in
                                applyChargeLimit(Int(newValue), enabled: true)
                            }
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                    }
                    
                    // Maintenance Tips Info block
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 13))
                            .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                        Text(isSilicon ? t("battery_care_desc_silicon") : t("battery_care_desc_intel"))
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.5))
                            .lineSpacing(3)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.08))
                    .cornerRadius(10)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Text(currentLanguage == "zh-Hans" ? "已开启全量充电模式，电池将充至 100%。建议开启充电限制以延长寿命。" : "Full charge mode active. The battery will charge to 100%. Enable charge limit to prolong lifespan.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.4))
                        .lineSpacing(3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var powerSavingSection: some View {
        VStack(spacing: 12) {
            // Header Row
            HStack {
                Image(systemName: "bolt.batteryblock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(powerStats.isConnected ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color(red: 0.22, green: 0.80, blue: 0.45))
                    .shadow(color: (powerStats.isConnected ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color(red: 0.22, green: 0.80, blue: 0.45)).opacity(0.4), radius: 4)
                
                Text(t("power_policy_title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                // Flat Tab Selector
                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedPowerTab = 0
                        }
                    }) {
                        Text(currentLanguage == "zh-Hans" ? "电源" : "AC")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(selectedPowerTab == 0 ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedPowerTab == 0 ? Color.white.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedPowerTab = 1
                        }
                    }) {
                        Text(currentLanguage == "zh-Hans" ? "电池" : "Battery")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(selectedPowerTab == 1 ? .white : .white.opacity(0.5))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedPowerTab == 1 ? Color.white.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(2)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
            }
            
            if selectedPowerTab == 0 {
                // AC Adapter Mode Controls
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("power_policy_level"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 8) {
                        ForEach(0..<3) { policy in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    acPowerPolicy = policy
                                    UserDefaults.standard.set(policy, forKey: "ACPowerPolicy")
                                    applyDynamicPowerSavingSettings()
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text(policyEmoji(policy))
                                        .font(.system(size: 14))
                                    Text(acPolicyText(policy))
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(acPowerPolicy == policy ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(acPowerPolicy == policy ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                                .foregroundColor(acPowerPolicy == policy ? .white : .white.opacity(0.6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Text(acPolicyTipText(acPowerPolicy))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                }
                .transition(.opacity)
            } else {
                // Battery Power Mode Controls
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("power_policy_level"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    
                    HStack(spacing: 8) {
                        ForEach(0..<3) { policy in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    batteryPowerPolicy = policy
                                    UserDefaults.standard.set(policy, forKey: "BatteryPowerPolicy")
                                    // 联动滑块到预设功耗
                                    if policy == 0 {
                                        batteryTargetPower = 6.0
                                    } else if policy == 1 {
                                        batteryTargetPower = 12.0
                                    } else {
                                        batteryTargetPower = 25.0
                                    }
                                    UserDefaults.standard.set(batteryTargetPower, forKey: "BatteryTargetPower")
                                    applyDynamicPowerSavingSettings()
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text(policyEmoji(policy))
                                        .font(.system(size: 14))
                                    Text(batteryPolicyText(policy))
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(batteryPowerPolicy == policy ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(batteryPowerPolicy == policy ? Color(red: 0.22, green: 0.80, blue: 0.45) : Color.white.opacity(0.05), lineWidth: 1)
                                )
                                .foregroundColor(batteryPowerPolicy == policy ? .white : .white.opacity(0.6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Text(batteryPolicyTipText(batteryPowerPolicy))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    
                    // Target Power Slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(t("target_power_limit"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: "%.1f W", batteryTargetPower))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                        }
                        
                        Slider(value: Binding(
                            get: { batteryTargetPower },
                            set: { val in
                                batteryTargetPower = val
                                UserDefaults.standard.set(val, forKey: "BatteryTargetPower")
                                
                                // 联动更新按钮状态
                                if val <= 8.0 {
                                    batteryPowerPolicy = 0
                                } else if val <= 15.0 {
                                    batteryPowerPolicy = 1
                                } else {
                                    batteryPowerPolicy = 2
                                }
                                UserDefaults.standard.set(batteryPowerPolicy, forKey: "BatteryPowerPolicy")
                                
                                if autoAlignBatteryPolicies {
                                    applyDynamicPowerSavingSettings()
                                }
                            }
                        ), in: 5.0...25.0, step: 0.5) {
                            Text("")
                        } minimumValueLabel: {
                            Text("5W").font(.system(size: 8)).foregroundColor(.gray)
                        } maximumValueLabel: {
                            Text("25W").font(.system(size: 8)).foregroundColor(.gray)
                        }
                        .accentColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                    }
                    
                    // Deductive Runtime Panel (超精细时间推演视图)
                    let wh = remainingWh
                    
                    // 1. 预计可使用时长
                    let targetHours = wh / batteryTargetPower
                    let targetH = Int(targetHours)
                    let targetM = Int((targetHours - Double(targetH)) * 60)
                    let budgetedText = String(format: "%d%@%02d%@", targetH, currentLanguage == "zh-Hans" ? "小时" : "h ", targetM, currentLanguage == "zh-Hans" ? "分钟" : "m")
                    
                    // 2. 基准（默认15W，即极致性能状态）
                    let baselineWatts = 15.0
                    let targetDiff = targetHours - (wh / baselineWatts)
                    
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentLanguage == "zh-Hans" ? "预计可使用时长" : "Est. Battery Life")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(budgetedText)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            let liveWatts = max(1.0, powerStats.batteryPower)
                            let liveHours = wh / liveWatts
                            let liveH = Int(liveHours)
                            let liveM = Int((liveHours - Double(liveH)) * 60)
                            let liveText = String(format: "%d%@%02d%@", liveH, currentLanguage == "zh-Hans" ? "小时" : "h ", liveM, currentLanguage == "zh-Hans" ? "分钟" : "m")
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("actual_runtime"))
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                Text(liveText)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if targetDiff > 0.05 {
                            let extH = Int(targetDiff)
                            let extM = Int((targetDiff - Double(extH)) * 60)
                            let extText = String(format: "%d%@%02d%@", extH, currentLanguage == "zh-Hans" ? "小时" : "h ", extM, currentLanguage == "zh-Hans" ? "分钟" : "m")
                            
                            HStack {
                                Text(currentLanguage == "zh-Hans" ? "⚡️ 已为您额外延长续航" : "⚡️ Extra Life Gained")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Text(currentLanguage == "zh-Hans" ? "额外延长 \(extText)" : "+\(extText)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.15))
                                    .cornerRadius(4)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    
                    // Auto-align switch
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { autoAlignBatteryPolicies },
                            set: { val in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    autoAlignBatteryPolicies = val
                                    UserDefaults.standard.set(val, forKey: "AutoAlignBatteryPolicies")
                                    applyDynamicPowerSavingSettings()
                                }
                            }
                        ))
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.22, green: 0.80, blue: 0.45)))
                        .labelsHidden()
                        .scaleEffect(0.7)
                        
                        Text(t("auto_align_policies"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                    }
                    
                    // Hardware Active policy indicator
                    if autoAlignBatteryPolicies {
                        let policyText = batteryPowerPolicy == 0 ? t("opt_active_deep") : (batteryPowerPolicy == 1 ? t("opt_active_mid") : t("opt_active_none"))
                        let policyColor = batteryPowerPolicy == 0 ? Color(red: 0.22, green: 0.80, blue: 0.45) : (batteryPowerPolicy == 1 ? Color.orange : Color(red: 0.18, green: 0.62, blue: 0.95))
                        
                        HStack(spacing: 6) {
                            Image(systemName: batteryPowerPolicy <= 1 ? "leaf.fill" : "cpu.fill")
                                .font(.system(size: 10))
                                .foregroundColor(policyColor)
                            
                            Text(policyText)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                        }
                        .padding(8)
                        .background(policyColor.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(policyColor.opacity(0.15), lineWidth: 1)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    private func metricGridCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.03))
        .cornerRadius(10)
    }
    
    // 3. Fan Section
    private var fanSection: some View {
        VStack(spacing: 12) {
            // Header row
            HStack {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 14))
                    .rotationEffect(.degrees(fanRotationAngle))
                    .foregroundColor((fanSpeed.first ?? 0) > 100 ? Color(red: 0.18, green: 0.62, blue: 0.95) : .gray)
                    .shadow(color: Color(red: 0.18, green: 0.62, blue: 0.95).opacity((fanSpeed.first ?? 0) > 100 ? 0.4 : 0), radius: 4)
                
                Text(t("fan_controller"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
            }
            
            // Fan speed status cards (one per fan)
            let displayCount = max(fanCount, 1)
            HStack(spacing: 10) {
                ForEach(0..<displayCount, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i == 0 ? t("left_fan") : t("right_fan"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                        Text("\(Int(i < fanSpeed.count ? fanSpeed[i] : 0)) RPM")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor((i < fanSpeed.count && fanSpeed[i] > 3000)
                                ? Color(red: 0.95, green: 0.60, blue: 0.18)
                                : Color(red: 0.18, green: 0.62, blue: 0.95))
                        Text("\(Int(i < fanMinSpeed.count ? fanMinSpeed[i] : 1200))–\(Int(i < fanMaxSpeed.count ? fanMaxSpeed[i] : 6000)) RPM")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
            }
            .padding(.top, 4)
            
            // Presets Panel: Dynamic One-Key Presets Selector
            VStack(spacing: 6) {
                Text(currentLanguage == "zh-Hans" ? "一键温控预设" : "One-Key Presets")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                
                HStack(spacing: 6) {
                    // Auto
                    Button(action: { applyPreset(0) }) {
                        VStack(spacing: 3) {
                            Text("🍃")
                            Text(t("fan_preset_auto"))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(fanPreset == 0 ? Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(fanPreset == 0 ? Color(red: 0.18, green: 0.62, blue: 0.95) : .white.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fanPreset == 0 ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                    
                    // Silent
                    Button(action: { applyPreset(1) }) {
                        VStack(spacing: 3) {
                            Text("🤫")
                            Text(t("fan_preset_silent"))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(fanPreset == 1 ? Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(fanPreset == 1 ? Color(red: 0.18, green: 0.62, blue: 0.95) : .white.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fanPreset == 1 ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                    
                    // Balanced
                    Button(action: { applyPreset(2) }) {
                        VStack(spacing: 3) {
                            Text("⚖️")
                            Text(t("fan_preset_balanced"))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(fanPreset == 2 ? Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(fanPreset == 2 ? Color(red: 0.62, green: 0.32, blue: 0.88) : .white.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fanPreset == 2 ? Color(red: 0.62, green: 0.32, blue: 0.88) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                    
                    // Turbo
                    Button(action: { applyPreset(3) }) {
                        VStack(spacing: 3) {
                            Text("🚀")
                            Text(t("fan_preset_turbo"))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(fanPreset == 3 ? Color(red: 0.95, green: 0.60, blue: 0.18).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(fanPreset == 3 ? Color(red: 0.95, green: 0.60, blue: 0.18) : .white.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fanPreset == 3 ? Color(red: 0.95, green: 0.60, blue: 0.18) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                    
                    // Custom Curve
                    Button(action: { applyPreset(4) }) {
                        VStack(spacing: 3) {
                            Text("📈")
                            Text(t("fan_preset_custom"))
                                .font(.system(size: 8, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(fanPreset == 4 ? Color(red: 0.95, green: 0.30, blue: 0.18).opacity(0.15) : Color.white.opacity(0.04))
                        .foregroundColor(fanPreset == 4 ? Color(red: 0.95, green: 0.30, blue: 0.18) : .white.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(fanPreset == 4 ? Color(red: 0.95, green: 0.30, blue: 0.18) : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
            
            // Dynamic Curve Graph
            if fanPreset > 0 {
                fanCurveGraph
                    .transition(.opacity)
            }
            
            // Custom Curve node sliders editor
            if fanPreset == 4 {
                fanCurveNodeAdjusters
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Privilege warning
            if showPrivilegeWarning {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.18))
                        Text(t("sudo_warning"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.18))
                    }
                    .padding(6)
                    .background(Color(red: 0.95, green: 0.60, blue: 0.18).opacity(0.1))
                    .cornerRadius(6)
                    
                    Button(action: { authorizeFanControl() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill").font(.system(size: 10))
                            Text(t("auth_btn")).font(.system(size: 9.5, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color(red: 0.18, green: 0.62, blue: 0.95))
                        .cornerRadius(6)
                        .shadow(color: Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.4), radius: 3)
                    }.buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
            
            // 冲突警告：功耗策略与风扇预设不兼容
            if fanPolicyConflictWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.95, green: 0.30, blue: 0.18))
                    Text(currentLanguage == "zh-Hans" ? "⚠️ 极致性能模式下禁止使用静音风扇，此组合可能导致处理器过热" : "⚠️ Cannot use Silent fan preset with Turbo power policy. Risk: CPU overheating.")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.30, blue: 0.18))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color(red: 0.95, green: 0.30, blue: 0.18).opacity(0.1))
                .cornerRadius(6)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    
    private var fanCurveGraph: some View {
        VStack(spacing: 8) {
            // Live Temperature Indicator Header
            let currentTemp = max(cpuTemp, gpuTemp)
            HStack {
                Text(currentLanguage == "zh-Hans" ? "实时温控曲线" : "Live Temp Curve")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.62, blue: 0.95))
                        .frame(width: 6, height: 6)
                    Text("\(Int(currentTemp))°C")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.12))
                .cornerRadius(4)
            }
            
            // The Graph Drawing Box
            ZStack {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    
                    // Coordinates mapping helper
                    // Temp: 30°C to 95°C -> X-axis
                    // Speed %: 0% to 100% -> Y-axis (Inverted since Y goes down in SwiftUI)
                    let getPoint: (Float, Float) -> CGPoint = { temp, speed in
                        let tMin: Float = 30.0
                        let tMax: Float = 95.0
                        let x = CGFloat((temp - tMin) / (tMax - tMin)) * w
                        let y = h - CGFloat(speed / 100.0) * h
                        return CGPoint(x: x, y: y)
                    }
                    
                    // Draw grid lines
                    Path { path in
                        // Y-axis grid lines (25%, 50%, 75%)
                        for pct in [25.0, 50.0, 75.0] {
                            let pStart = getPoint(30, Float(pct))
                            let pEnd = getPoint(95, Float(pct))
                            path.move(to: pStart)
                            path.addLine(to: pEnd)
                        }
                        // X-axis grid lines (40°C, 55°C, 70°C, 85°C)
                        for t in [40.0, 55.0, 70.0, 85.0] {
                            let pStart = getPoint(Float(t), 0)
                            let pEnd = getPoint(Float(t), 100)
                            path.move(to: pStart)
                            path.addLine(to: pEnd)
                        }
                    }
                    .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    
                    // Tiny Y-Axis Labels
                    Group {
                        Text("75%").position(x: 14, y: getPoint(30, 75).y)
                        Text("50%").position(x: 14, y: getPoint(30, 50).y)
                        Text("25%").position(x: 14, y: getPoint(30, 25).y)
                    }
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    
                    // Tiny X-Axis Labels
                    Group {
                        Text("40°C").position(x: getPoint(40, 0).x, y: h - 6)
                        Text("55°C").position(x: getPoint(55, 0).x, y: h - 6)
                        Text("70°C").position(x: getPoint(70, 0).x, y: h - 6)
                        Text("85°C").position(x: getPoint(85, 0).x, y: h - 6)
                    }
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    
                    let p1 = getPoint(customCurveTemp1, customCurveSpeed1)
                    let p2 = getPoint(customCurveTemp2, customCurveSpeed2)
                    let p3 = getPoint(customCurveTemp3, customCurveSpeed3)
                    let p4 = getPoint(customCurveTemp4, customCurveSpeed4)
                    
                    // Draw Curve Path
                    Path { path in
                        path.move(to: getPoint(30, customCurveSpeed1))
                        path.addLine(to: p1)
                        path.addLine(to: p2)
                        path.addLine(to: p3)
                        path.addLine(to: p4)
                        path.addLine(to: getPoint(95, customCurveSpeed4))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.18, green: 0.62, blue: 0.95),
                                Color(red: 0.62, green: 0.32, blue: 0.88),
                                Color(red: 0.95, green: 0.60, blue: 0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Draw Nodes
                    let nodeColor = fanPreset == 4 ? Color(red: 0.95, green: 0.60, blue: 0.18) : Color.white.opacity(0.4)
                    
                    Circle().fill(nodeColor).frame(width: 6, height: 6).position(p1)
                    Circle().fill(nodeColor).frame(width: 6, height: 6).position(p2)
                    Circle().fill(nodeColor).frame(width: 6, height: 6).position(p3)
                    Circle().fill(nodeColor).frame(width: 6, height: 6).position(p4)
                    
                    // Live Temperature indicator bubble moving along the curve
                    let currentPct = interpolateSpeedPercentage(temp: currentTemp)
                    let livePt = getPoint(currentTemp, currentPct)
                    
                    if currentTemp >= 30 && currentTemp <= 95 {
                        // Dynamic crosshair lines intersecting at the active point
                        Path { path in
                            // Horizontal crosshair
                            path.move(to: CGPoint(x: 0, y: livePt.y))
                            path.addLine(to: CGPoint(x: w, y: livePt.y))
                            // Vertical crosshair
                            path.move(to: CGPoint(x: livePt.x, y: 0))
                            path.addLine(to: CGPoint(x: livePt.x, y: h))
                        }
                        .stroke(Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        
                        // Interactive numeric speed badge directly at the crosshair right end
                        Text("\(Int(currentPct))%")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(3)
                            .position(x: w - 20, y: livePt.y)
                        
                        // Glowing indicator point
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.3))
                                .frame(width: 14, height: 14)
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                                .shadow(color: Color(red: 0.18, green: 0.62, blue: 0.95), radius: 4)
                        }
                        .position(livePt)
                    }
                }
            }
            .frame(height: 75)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.05), lineWidth: 1))
        }
    }
    
    private var fanCurveNodeAdjusters: some View {
        VStack(spacing: 8) {
            Text(currentLanguage == "zh-Hans" ? "调节曲线控制节点" : "Adjust Curve Nodes")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            
            VStack(spacing: 8) {
                // Node 1
                VStack(spacing: 4) {
                    HStack {
                        Text("\(t("fan_curve_node")) 1 (低温)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(customCurveTemp1))°C → \(Int(customCurveSpeed1))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                    }
                    HStack(spacing: 12) {
                        Slider(value: $customCurveTemp1, in: 30...50, step: 1) { Text("") }
                            .accentColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                        Slider(value: $customCurveSpeed1, in: 0...50, step: 5) { Text("") }
                            .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                }
                
                // Node 2
                VStack(spacing: 4) {
                    HStack {
                        Text("\(t("fan_curve_node")) 2 (常温)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(customCurveTemp2))°C → \(Int(customCurveSpeed2))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                    }
                    HStack(spacing: 12) {
                        Slider(value: $customCurveTemp2, in: 50...65, step: 1) { Text("") }
                            .accentColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                        Slider(value: $customCurveSpeed2, in: 10...75, step: 5) { Text("") }
                            .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                }
                
                // Node 3
                VStack(spacing: 4) {
                    HStack {
                        Text("\(t("fan_curve_node")) 3 (高负荷)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(customCurveTemp3))°C → \(Int(customCurveSpeed3))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                    }
                    HStack(spacing: 12) {
                        Slider(value: $customCurveTemp3, in: 65...80, step: 1) { Text("") }
                            .accentColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                        Slider(value: $customCurveSpeed3, in: 30...90, step: 5) { Text("") }
                            .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                }
                
                // Node 4
                VStack(spacing: 4) {
                    HStack {
                        Text("\(t("fan_curve_node")) 4 (极限)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(Int(customCurveTemp4))°C → \(Int(customCurveSpeed4))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.18))
                    }
                    HStack(spacing: 12) {
                        Slider(value: $customCurveTemp4, in: 80...95, step: 1) { Text("") }
                            .accentColor(Color(red: 0.95, green: 0.60, blue: 0.18))
                        Slider(value: $customCurveSpeed4, in: 70...100, step: 5) { Text("") }
                            .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            .onChange(of: customCurveTemp1) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveSpeed1) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveTemp2) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveSpeed2) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveTemp3) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveSpeed3) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveTemp4) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
            .onChange(of: customCurveSpeed4) { _ in saveCustomCurveSettings(); evaluateAndApplyFanCurve() }
        }
    }
    
    // Per-fan slider row
    private func fanSliderRow(index i: Int, displayCount: Int) -> some View {
        let mn       = i < fanMinSpeed.count ? fanMinSpeed[i] : 1200
        let mx       = i < fanMaxSpeed.count ? fanMaxSpeed[i] : 6000
        let sMin     = min(mn, mx - 50)
        let sMax     = max(mx, mn + 50)
        let dotColor = i == 0 ? Color(red: 0.18, green: 0.62, blue: 0.95)
                               : Color(red: 0.62, green: 0.32, blue: 0.88)
        let valColor = i == 0 ? Color(red: 0.95, green: 0.60, blue: 0.18)
                               : Color(red: 0.62, green: 0.32, blue: 0.88)
        // Compute label here for the header — this updates when the view re-renders
        let label    = (i == 0 ? t("left_fan") : t("right_fan")) + (fanLinked && fanCount == 2 ? t("fan_linked") : "")

        return VStack(spacing: 5) {
            HStack {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(Int(i < targetFanSpeed.count ? targetFanSpeed[i] : 2000)) RPM")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(valColor)
            }

            Slider(
                value: Binding<Float>(
                    get: { i < targetFanSpeed.count ? targetFanSpeed[i] : 2000 },
                    set: { [self] newVal in
                        // ALWAYS read fanLinked at call time — not a captured constant
                        if fanLinked && fanCount == 2 {
                            // Linked mode: drive both fans together
                            if targetFanSpeed.count >= 2 {
                                targetFanSpeed[0] = newVal
                                targetFanSpeed[1] = newVal
                            }
                            applyFanSpeed(newVal, forFan: -1)
                        } else {
                            // Independent mode: only this fan
                            if i < targetFanSpeed.count { targetFanSpeed[i] = newVal }
                            applyFanSpeed(newVal, forFan: i)
                        }
                    }
                ),
                in: sMin...sMax,
                step: 50
            )
            .accentColor(valColor)
        }
    }





    // 3b. Fanless Alert
    private var fanlessSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "fanblades")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(t("fanless_title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Text(t("fanless_desc"))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // 4. Keyboard Light Section
    private var keyboardSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard.fill")
                    .foregroundColor(keyboardMode > 0 || keyboardBrightness > 0 ? Color(red: 0.62, green: 0.32, blue: 0.88) : .gray)
                    .shadow(color: Color(red: 0.62, green: 0.32, blue: 0.88).opacity(keyboardMode > 0 || keyboardBrightness > 0 ? 0.4 : 0), radius: 4)
                Text(t("keyboard_title"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
                
                Text(t("keyboard_mode"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            // Premium custom Segmented Control for lighting modes
            HStack(spacing: 0) {
                ForEach(0..<3) { mode in
                    let label = mode == 0 ? t("mode_static") : (mode == 1 ? t("mode_breathing") : t("mode_wave"))
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            keyboardMode = mode
                            UserDefaults.standard.set(mode, forKey: "KeyboardLightingMode")
                            toggleKeyboardAnimation(mode: mode)
                        }
                    }) {
                        Text(label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(keyboardMode == mode ? .white : .white.opacity(0.4))
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(keyboardMode == mode ? Color(red: 0.62, green: 0.32, blue: 0.88) : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(2)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            
            if keyboardMode == 0 {
                // Static brightness control
                VStack(spacing: 6) {
                    HStack {
                        Text(t("backlight_brightness"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text("\(Int(keyboardBrightness * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                    
                    Slider(value: $keyboardBrightness, in: 0.0...1.0, step: 0.05)
                        .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                        .onChange(of: keyboardBrightness) { newValue in
                            applyKeyboardBrightness(newValue)
                        }
                }
                .padding(.top, 4)
            } else {
                // Dynamic Breathing / Wave Deck Panel
                VStack(spacing: 12) {
                    // Custom Horizontal Key Deck Visualizer
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.2))
                            .frame(height: 56)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                        
                        VStack(spacing: 4) {
                            // Upper row of 10 keys
                            HStack(spacing: 4) {
                                ForEach(0..<10) { i in
                                    let offset = Double(i) * 0.35
                                    let intensity: Double = {
                                        if keyboardMode == 2 {
                                            // True horizontal wave phase shift
                                            return pow(sin(wavePhase * 0.5 - offset), 2.0)
                                        } else {
                                            // Uniform Breathing
                                            return pow(sin(wavePhase * 0.5), 2.0)
                                        }
                                    }()
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.15 + 0.85 * intensity),
                                                    Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.15 + 0.85 * intensity)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 16, height: 11)
                                        .shadow(color: Color(red: 0.62, green: 0.32, blue: 0.88).opacity(intensity * 0.5), radius: 2)
                                }
                            }
                            
                            // Lower row of 10 keys
                            HStack(spacing: 4) {
                                ForEach(0..<10) { i in
                                    let offset = Double(i) * 0.35 + 0.17
                                    let intensity: Double = {
                                        if keyboardMode == 2 {
                                            return pow(sin(wavePhase * 0.5 - offset), 2.0)
                                        } else {
                                            return pow(sin(wavePhase * 0.5), 2.0)
                                        }
                                    }()
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.15 + 0.85 * intensity),
                                                    Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.15 + 0.85 * intensity)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 16, height: 11)
                                        .shadow(color: Color(red: 0.62, green: 0.32, blue: 0.88).opacity(intensity * 0.5), radius: 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    
                    // State description text under visualizer
                    Text(keyboardMode == 1 ? t("breathing_status") : t("wave_status"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.top, -4)
                    
                    // Control variables (Period speed)
                    VStack(spacing: 6) {
                        HStack {
                            Text(t("breathing_period"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(String(format: currentLanguage == "zh-Hans" ? "%.1f 秒" : "%.1fs", breathingSpeed))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                        }
                        
                        Slider(value: $breathingSpeed, in: 1.5...8.0, step: 0.5)
                            .accentColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    }
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    // 5. System info footer
    private var footerSection: some View {
        HStack {
            Spacer()
            Text(t("app_ver"))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // 6. Settings Panel Slide-Over (Stunning glassmorphic dashboard overlay)
    private var settingsSection: some View {
        VStack(spacing: 16) {
            // Settings Header Bar
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSettings = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text(currentLanguage == "zh-Hans" ? "返回" : "Back")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(t("settings"))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                // A blank placeholder of exact same width to keep title perfectly centered
                Color.clear
                    .frame(width: 58, height: 1)
            }
            .padding(.bottom, 6)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    
                    // Card 1: Language Selection
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "character.bubble.fill")
                                .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                                .font(.system(size: 14))
                            Text(t("lang_select"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Picker("", selection: $currentLanguage) {
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: currentLanguage) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "AppLanguage")
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    
                    // Card 2: Autostart Launch Behavior
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                                .font(.system(size: 14))
                            Text(t("startup"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Toggle(isOn: $launchAtLogin) {
                            Text(t("auto_start"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.22, green: 0.80, blue: 0.45)))
                        .onChange(of: launchAtLogin) { newValue in
                            LaunchAtLoginHelper.isEnabled = newValue
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    
                    // Card 3: About Program (With glowing graphics)
                    VStack(spacing: 12) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(
                                LinearGradient(colors: [Color(red: 0.18, green: 0.62, blue: 0.95), Color(red: 0.62, green: 0.32, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .shadow(color: Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.5), radius: 6)
                            .padding(.top, 4)
                        
                        Text(t("title"))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        HStack(spacing: 6) {
                            Text("v1.2.0")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(6)
                            
                            if !powerStats.friendlyModelName.isEmpty {
                                Text(powerStats.friendlyModelName)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.12))
                                    .cornerRadius(6)
                            }
                        }
                        
                        Text(t("app_desc"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 6)
                        
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.vertical, 2)
                        
                        VStack(spacing: 4) {
                            Text(t("author"))
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(t("copyright"))
                                .font(.system(size: 8.5))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    
                    // Card 4: Sponsor Section (Animated payment visual effects)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.circle.fill")
                                .foregroundColor(Color(red: 0.95, green: 0.32, blue: 0.48))
                                .font(.system(size: 14))
                            Text(t("donate"))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Text(t("donate_desc"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(3)
                        
                        // Payment tabs switching Alipays and WeChat Pay
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.easeInOut) { donateMethod = 0 }
                            }) {
                                Text(t("alipay"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(donateMethod == 0 ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(donateMethod == 0 ? Color(red: 0.10, green: 0.56, blue: 0.91) : Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(donateMethod == 0 ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                withAnimation(.easeInOut) { donateMethod = 1 }
                            }) {
                                Text(t("wechat"))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(donateMethod == 1 ? .white : .white.opacity(0.6))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(donateMethod == 1 ? Color(red: 0.03, green: 0.76, blue: 0.38) : Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(donateMethod == 1 ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Animated Stylized Vector QR Code container
                        VStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.3))
                                    .frame(width: 140, height: 140)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(donateMethod == 0 ? Color(red: 0.10, green: 0.56, blue: 0.91).opacity(0.4) : Color(red: 0.03, green: 0.76, blue: 0.38).opacity(0.4), lineWidth: 1.5)
                                    )
                                
                                ZStack {
                                    // High-Fidelity Alipay/WeChat QR Code image loading from bundle resources
                                    if let imagePath = Bundle.main.path(forResource: donateMethod == 0 ? "alipay_qr" : "wechat_qr", ofType: "png"),
                                       let nsImage = NSImage(contentsOfFile: imagePath) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .interpolation(.medium)
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 126, height: 126)
                                            .cornerRadius(8)
                                    } else {
                                        // Fallback vector targets if image is not loaded
                                        VStack(spacing: 8) {
                                            Image(systemName: donateMethod == 0 ? "creditcard.fill" : "message.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(donateMethod == 0 ? Color(red: 0.10, green: 0.56, blue: 0.91) : Color(red: 0.03, green: 0.76, blue: 0.38))
                                            Text("Loading QR...")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.4))
                                        }
                                    }
                                    
                                    // Animated scan-line overlay for futuristic feel
                                    VStack {
                                        Spacer()
                                        Rectangle()
                                            .fill(
                                                LinearGradient(colors: [.clear, donateMethod == 0 ? Color(red: 0.10, green: 0.56, blue: 0.91).opacity(0.8) : Color(red: 0.03, green: 0.76, blue: 0.38).opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                                            )
                                            .frame(height: 3)
                                            .shadow(color: donateMethod == 0 ? Color(red: 0.10, green: 0.56, blue: 0.91) : Color(red: 0.03, green: 0.76, blue: 0.38), radius: 3)
                                            .offset(y: qrScanOffset)
                                            .onAppear {
                                                withAnimation(Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                                                    qrScanOffset = 50.0
                                                }
                                            }
                                        Spacer()
                                    }
                                    .frame(width: 120, height: 120)
                                }
                            }
                            .onTapGesture {
                                showDonateAlert = true
                            }
                            
                            Text(t("scan_qr"))
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.black.opacity(0.18))
                        .cornerRadius(10)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .alert(isPresented: $showDonateAlert) {
                        Alert(
                            title: Text(t("thank_you")),
                            message: Text(t("donate_success_msg")),
                            dismissButton: .default(Text(t("close")))
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(18)
        .frame(width: 680, height: 530)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                RadialGradient(colors: [Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
                RadialGradient(colors: [Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.09), .clear], center: .bottomLeading, startRadius: 0, endRadius: 280)
            }
        )
        .preferredColorScheme(.dark)
    }
    
    private func qrTarget(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3.5)
            .stroke(color, lineWidth: 2.2)
            .frame(width: 22, height: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 8, height: 8)
            )
    }
    
    // MARK: - Core Logic & Functions
    
    private func triggerMemoryPurge() {
        isPurging = true
        showPurgeSuccess = false
        MemoryPurger.purge(progressHandler: { progress in
            self.purgeProgress = progress
        }, completion: { reclaimedMB in
            self.lastPurgedAmount = reclaimedMB
            self.isPurging = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                self.showPurgeSuccess = true
            }
            // Auto hide success state after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    self.showPurgeSuccess = false
                }
            }
        })
    }
    
    private func initializeHardware() {
        // SMC init
        smc.doOpen()
        
        fanCount = smc.getFanCount()
        if fanCount > 0 {
            // Initialize per-fan arrays
            var mins: [Float] = []
            var maxs: [Float] = []
            var speeds: [Float] = []
            var targets: [Float] = []
            
            for i in 0..<fanCount {
                let rawMin = smc.getFanMinSpeed(i)
                let rawMax = smc.getFanMaxSpeed(i)
                let lo = min(rawMin, rawMax - 50)
                let hi = max(rawMax, rawMin + 50)
                let ac  = smc.getFanSpeed(i)
                let tg  = smc.getFanTargetSpeed(i)
                mins.append(lo)
                maxs.append(hi)
                speeds.append(ac)
                targets.append(max(lo, min(tg > 0 ? tg : lo, hi)))
            }
            fanMinSpeed    = mins
            fanMaxSpeed    = maxs
            fanSpeed       = speeds
            targetFanSpeed = targets
            lastAppliedFanSpeed = targets
            lastHardwareSetSpeed = Array(repeating: 0.0, count: fanCount)
            
            // Detect manual mode (F0Md for Apple Silicon, FS! for Intel)
            if let f0md = smc.readKey("F0Md") {
                isManualFan = (f0md.0 != 0)
            } else if let fs = smc.readKey("FS! ") {
                isManualFan = (fs.0 > 0 || fs.1 > 0)
            }
        }
        
        // Keyboard init
        let currentB = KeyboardBacklightPrivate.getBrightness()
        keyboardBrightness = currentB
        
        if keyboardMode > 0 {
            toggleKeyboardAnimation(mode: keyboardMode)
        }
        
        // Power monitor init
        powerStats = PowerMonitor.getPowerStats()
        cpuTemp = smc.getCPUTemperature()
        gpuTemp = smc.getGPUTemperature()
        selectedPowerTab = powerStats.isConnected ? 0 : 1
        
        // Power Optimization Init
        isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        disableKeyboardBacklightOnBattery = UserDefaults.standard.bool(forKey: "DisableKeyboardBacklightOnBattery")
        applyDynamicPowerSavingSettings()
        
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.launchPath = "/usr/bin/pmset"
            task.arguments = ["-g", "custom"]
            let pipe = Pipe()
            task.standardOutput = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    if let range = output.range(of: "Battery Power:") {
                        let sub = output[range.upperBound...]
                        if let lineRange = sub.range(of: "displaysleep") {
                            let line = sub[lineRange.lowerBound...]
                            if let firstLine = line.components(separatedBy: "\n").first {
                                let parts = firstLine.split(separator: " ").compactMap { String($0) }
                                if parts.count >= 2, let val = Int(parts[1]) {
                                    DispatchQueue.main.async {
                                        self.aggressiveScreenSleep = (val <= 2 && val > 0)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {}
        }
        
        // Battery care settings init
        loadBatteryCareSettings()
        
        // Custom fan curve init
        loadCustomCurveSettings()
        evaluateAndApplyFanCurve()
        
        // Launch behavior sync
        launchAtLogin = LaunchAtLoginHelper.isEnabled
        
        // Mark hardware as initialized to transition from skeleton view to main panel
        withAnimation(.easeIn(duration: 0.3)) {
            isHardwareInitialized = true
        }
    }
    
    private func refreshStats() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        // Capture necessary State variables from the main thread
        let currentFanCount = fanCount
        let currentIsManualFan = isManualFan
        let currentFanPreset = fanPreset
        
        let currentFanMinSpeed = fanMinSpeed
        let currentFanMaxSpeed = fanMaxSpeed
        let currentLastAppliedFanSpeed = lastAppliedFanSpeed
        let currentLastHardwareSetSpeed = lastHardwareSetSpeed
        
        let cCurveTemp1 = customCurveTemp1
        let cCurveSpeed1 = customCurveSpeed1
        let cCurveTemp2 = customCurveTemp2
        let cCurveSpeed2 = customCurveSpeed2
        let cCurveTemp3 = customCurveTemp3
        let cCurveSpeed3 = customCurveSpeed3
        let cCurveTemp4 = customCurveTemp4
        let cCurveSpeed4 = customCurveSpeed4
        
        let currentDisableKeyboardBacklightOnBattery = disableKeyboardBacklightOnBattery
        
        telemetryQueue.async {
            // 1. Perform intensive hardware readings on background queue
            let tempCpu = self.smc.getCPUTemperature()
            let tempGpu = self.smc.getGPUTemperature()
            let statsPower = PowerMonitor.getPowerStats()
            
            let usageCpu = self.cpuMonitor.getUsage()
            let usageGpu = self.getGPUUsage()
            
            let processes = MemoryPurger.getActiveProcessMemoryList()
            let ramPercent = self.getRAMUsage()
            
            let pCpuPerf = self.smc.getCPUPerfCoresTemperature()
            let pCpuEff = self.smc.getCPUEffCoresTemperature()
            let pSSD = self.smc.getSSDTemperature()
            let pWiFi = self.smc.getWiFiTemperature()
            let pMemory = self.smc.getMemoryTemperature()
            let pPalmRest = self.smc.getPalmRestTemperature()
            let pAirflow = self.smc.getAirflowTemperature()
            
            let voltCpu = self.smc.getCPUVoltage(load: usageCpu)
            let voltGpu = self.smc.getGPUVoltage(load: usageGpu)
            let powCpu = self.smc.getCPUPower(load: usageCpu)
            let powGpu = self.smc.getGPUPower(load: usageGpu)
            
            // Total power calculation
            var totalPow = powCpu + powGpu + 2.5
            if !statsPower.isConnected {
                let discharge = abs(statsPower.batteryPower)
                if discharge > 0.1 {
                    totalPow = discharge
                }
            }
            
            // Frequency calculation
            let freqCpuPerf = 1.5 + (usageCpu / 100.0) * 1.7
            let freqCpuEff = 1.0 + (usageCpu / 100.0) * 1.0
            let freqGpu = 0.3 + (usageGpu / 100.0) * 1.0
            
            // Fan speeds
            var actualFanSpeeds = [Float]()
            if currentFanCount > 0 {
                for i in 0..<currentFanCount {
                    actualFanSpeeds.append(self.smc.getFanSpeed(i))
                }
            }
            
            // Custom fan curve temperature regulation evaluation
            var nextTargetFanSpeeds: [Float] = []
            var nextLastAppliedFanSpeed: [Float] = []
            var nextLastHardwareSetSpeed: [Float] = []
            
            if currentIsManualFan && currentFanPreset > 0 {
                let currentTemp = max(tempCpu, tempGpu)
                
                var tmpLastApplied = currentLastAppliedFanSpeed
                if tmpLastApplied.count < currentFanCount {
                    tmpLastApplied = Array(repeating: 2000.0, count: currentFanCount)
                }
                var tmpLastHardware = currentLastHardwareSetSpeed
                if tmpLastHardware.count < currentFanCount {
                    tmpLastHardware = Array(repeating: 0.0, count: currentFanCount)
                }
                var tmpTarget = Array(repeating: Float(2000.0), count: currentFanCount)
                
                let calculatePct: (Float) -> Float = { temp in
                    if currentFanPreset == 1 && temp > 85.0 {
                        let startTemp: Float = 85.0
                        let endTemp: Float = 92.0
                        let ratio = min(max((temp - startTemp) / (endTemp - startTemp), 0.0), 1.0)
                        return 55.0 + (100.0 - 55.0) * ratio
                    }
                    if temp <= cCurveTemp1 {
                        return cCurveSpeed1
                    } else if temp <= cCurveTemp2 {
                        let gap = cCurveTemp2 - cCurveTemp1
                        let ratio = gap > 0 ? (temp - cCurveTemp1) / gap : 0.0
                        return cCurveSpeed1 + (cCurveSpeed2 - cCurveSpeed1) * ratio
                    } else if temp <= cCurveTemp3 {
                        let gap = cCurveTemp3 - cCurveTemp2
                        let ratio = gap > 0 ? (temp - cCurveTemp2) / gap : 0.0
                        return cCurveSpeed2 + (cCurveSpeed3 - cCurveSpeed2) * ratio
                    } else if temp <= cCurveTemp4 {
                        let gap = cCurveTemp4 - cCurveTemp3
                        let ratio = gap > 0 ? (temp - cCurveTemp3) / gap : 0.0
                        return cCurveSpeed3 + (cCurveSpeed4 - cCurveSpeed3) * ratio
                    } else {
                        return cCurveSpeed4
                    }
                }
                
                for i in 0..<currentFanCount {
                    let minRPM = i < currentFanMinSpeed.count ? currentFanMinSpeed[i] : 1200
                    let maxRPM = i < currentFanMaxSpeed.count ? currentFanMaxSpeed[i] : 6000
                    
                    let pct = calculatePct(currentTemp)
                    let rawTargetSpeed = minRPM + (maxRPM - minRPM) * (pct / 100.0)
                    
                    let currentApplied = tmpLastApplied[safe: i] ?? rawTargetSpeed
                    let diff = rawTargetSpeed - currentApplied
                    
                    let alpha: Float = diff > 0 ? 0.25 : 0.03
                    let nextApplied = currentApplied + diff * alpha
                    
                    if i < tmpLastApplied.count {
                        tmpLastApplied[i] = nextApplied
                    }
                    if i < tmpTarget.count {
                        tmpTarget[i] = nextApplied
                    }
                    
                    let lastSet = tmpLastHardware[safe: i] ?? 0.0
                    let isAtEdge = (nextApplied >= maxRPM - 100.0 && lastSet < maxRPM - 100.0) || 
                                   (nextApplied <= minRPM + 100.0 && lastSet > minRPM + 100.0)
                    
                    if abs(nextApplied - lastSet) >= 50.0 || isAtEdge {
                        self.applyFanSpeed(nextApplied, forFan: i)
                        if i < tmpLastHardware.count {
                            tmpLastHardware[i] = nextApplied
                        }
                    }
                }
                nextTargetFanSpeeds = tmpTarget
                nextLastAppliedFanSpeed = tmpLastApplied
                nextLastHardwareSetSpeed = tmpLastHardware
            }
            
            // 2. Dispatch the results back to the main thread to update UI
            DispatchQueue.main.async {
                self.cpuTemp = tempCpu
                self.gpuTemp = tempGpu
                self.powerStats = statsPower
                self.cpuUsage = usageCpu
                self.gpuUsage = usageGpu
                
                self.activeProcesses = processes
                self.currentRAMUsagePercent = ramPercent
                
                self.tempCpuPerf = pCpuPerf
                self.tempCpuEff = pCpuEff
                self.tempSSD = pSSD
                self.tempWiFi = pWiFi
                self.tempMemory = pMemory
                self.tempPalmRest = pPalmRest
                self.tempAirflow = pAirflow
                
                self.cpuVoltage = voltCpu
                self.gpuVoltage = voltGpu
                self.cpuPower = powCpu
                self.gpuPower = powGpu
                self.totalPower = totalPow
                
                self.cpuFreqPerf = freqCpuPerf
                self.cpuFreqEff = freqCpuEff
                self.gpuFreq = freqGpu
                
                for i in 0..<actualFanSpeeds.count {
                    if i < self.fanSpeed.count {
                        self.fanSpeed[i] = actualFanSpeeds[i]
                    }
                }
                
                if !nextTargetFanSpeeds.isEmpty {
                    self.targetFanSpeed = nextTargetFanSpeeds
                    self.lastAppliedFanSpeed = nextLastAppliedFanSpeed
                    self.lastHardwareSetSpeed = nextLastHardwareSetSpeed
                }
                
                // Dynamic Power/Battery Saving Alignments
                self.applyDynamicPowerSavingSettings()
                
                // Auto Dim Keyboard Backlight on Battery if configured
                if currentDisableKeyboardBacklightOnBattery && !statsPower.isConnected {
                    let currentKB = KeyboardBacklightPrivate.getBrightness()
                    if currentKB > 0.0 {
                        let _ = KeyboardBacklightPrivate.setBrightness(0.0)
                        self.keyboardBrightness = 0.0
                    }
                }
                
                self.isRefreshing = false
            }
        }
    }
    
    private func getGPUUsage() -> Double {
        var usage: Double = 0.0
        let match = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator)
        if kr == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                var serviceProps: Unmanaged<CFMutableDictionary>?
                let propResult = IORegistryEntryCreateCFProperties(service, &serviceProps, kCFAllocatorDefault, 0)
                if propResult == KERN_SUCCESS, let props = serviceProps?.takeRetainedValue() as? [String: Any] {
                    if let stats = props["PerformanceStatistics"] as? [String: Any] {
                        if let util = stats["Device Utilization %"] as? Int {
                            usage = max(usage, Double(util))
                        } else if let utilVal = stats["Device Utilization %"] as? Double {
                            usage = max(usage, utilVal)
                        } else if let utilVal = stats["Device Utilization %"] as? Int64 {
                            usage = max(usage, Double(utilVal))
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        if usage == 0.0 {
            let gpuTempNow = smc.getGPUTemperature()
            let baseGpu = max(0.0, Double(gpuTempNow - 38.0) * 1.5)
            usage = max(0.0, min(100.0, baseGpu))
        }
        
        return usage
    }
    
    private func updateFanRotation() {
        let speed = isManualFan ? (targetFanSpeed.first ?? 2000) : (fanSpeed.first ?? 0)
        fanRotationAngle += Double(speed) / 180.0
    }
    
    private func updateWaveAnimation() {
        if keyboardMode > 0 {
            wavePhase += (2.0 * .pi) / (breathingSpeed * 20.0)
        }
    }
    
    private func saveCustomCurveSettings() {
        UserDefaults.standard.set(customCurveTemp1, forKey: "CustomCurveTemp1")
        UserDefaults.standard.set(customCurveSpeed1, forKey: "CustomCurveSpeed1")
        UserDefaults.standard.set(customCurveTemp2, forKey: "CustomCurveTemp2")
        UserDefaults.standard.set(customCurveSpeed2, forKey: "CustomCurveSpeed2")
        UserDefaults.standard.set(customCurveTemp3, forKey: "CustomCurveTemp3")
        UserDefaults.standard.set(customCurveSpeed3, forKey: "CustomCurveSpeed3")
        UserDefaults.standard.set(customCurveTemp4, forKey: "CustomCurveTemp4")
        UserDefaults.standard.set(customCurveSpeed4, forKey: "CustomCurveSpeed4")
    }
    
    private func loadCustomCurveSettings() {
        if UserDefaults.standard.object(forKey: "CustomCurveTemp1") != nil {
            customCurveTemp1 = UserDefaults.standard.float(forKey: "CustomCurveTemp1")
            customCurveSpeed1 = UserDefaults.standard.float(forKey: "CustomCurveSpeed1")
            customCurveTemp2 = UserDefaults.standard.float(forKey: "CustomCurveTemp2")
            customCurveSpeed2 = UserDefaults.standard.float(forKey: "CustomCurveSpeed2")
            customCurveTemp3 = UserDefaults.standard.float(forKey: "CustomCurveTemp3")
            customCurveSpeed3 = UserDefaults.standard.float(forKey: "CustomCurveSpeed3")
            customCurveTemp4 = UserDefaults.standard.float(forKey: "CustomCurveTemp4")
            customCurveSpeed4 = UserDefaults.standard.float(forKey: "CustomCurveSpeed4")
        } else {
            // Default Custom Curve Nodes
            customCurveTemp1 = 40.0; customCurveSpeed1 = 20.0
            customCurveTemp2 = 55.0; customCurveSpeed2 = 45.0
            customCurveTemp3 = 70.0; customCurveSpeed3 = 75.0
            customCurveTemp4 = 85.0; customCurveSpeed4 = 100.0
        }
    }
    
    // skipPolicyCheck: true 时跳过兼容性检验（仅供内部联动调用）
    private func applyPreset(_ preset: Int, skipPolicyCheck: Bool = false) {
        // 修复冲突#1：用户手动选择预设时，检验与当前功耗策略是否兼容
        // 规则：极致性能(AC Turbo) 模式下，禁止选择「静音优先」风扇
        if !skipPolicyCheck && preset == 1 && powerStats.isConnected && acPowerPolicy == 2 {
            // 不允许在极致性能策略下使用静音风扇——显示冲突提示
            fanPolicyConflictWarning = true
            return
        }
        fanPolicyConflictWarning = false
        fanPreset = preset
        UserDefaults.standard.set(preset, forKey: "FanPresetMode")
        
        if preset == 0 {
            toggleManualFan(false)
        } else {
            // Ensure we are in manual mode
            toggleManualFan(true)
            
            if preset == 1 { // Silent / Eco
                customCurveTemp1 = 45; customCurveSpeed1 = 0
                customCurveTemp2 = 60; customCurveSpeed2 = 12
                customCurveTemp3 = 75; customCurveSpeed3 = 30
                customCurveTemp4 = 85; customCurveSpeed4 = 55
            } else if preset == 2 { // Balanced
                customCurveTemp1 = 40; customCurveSpeed1 = 20
                customCurveTemp2 = 55; customCurveSpeed2 = 40
                customCurveTemp3 = 70; customCurveSpeed3 = 70
                customCurveTemp4 = 82; customCurveSpeed4 = 100
            } else if preset == 3 { // Turbo / Max
                customCurveTemp1 = 30; customCurveSpeed1 = 100
                customCurveTemp2 = 45; customCurveSpeed2 = 100
                customCurveTemp3 = 60; customCurveSpeed3 = 100
                customCurveTemp4 = 75; customCurveSpeed4 = 100
            } else if preset == 4 { // Custom
                loadCustomCurveSettings()
            }
            
            // Instant hardware snap on preset switch to provide instant acoustic feedback
            let currentTemp = max(cpuTemp, gpuTemp)
            let rawPct = interpolateSpeedPercentage(temp: currentTemp)
            for i in 0..<fanCount {
                let minRPM = i < fanMinSpeed.count ? fanMinSpeed[i] : 1200
                let maxRPM = i < fanMaxSpeed.count ? fanMaxSpeed[i] : 6000
                let speed = minRPM + (maxRPM - minRPM) * (rawPct / 100.0)
                
                if i < lastAppliedFanSpeed.count {
                    lastAppliedFanSpeed[i] = speed
                }
                if i < targetFanSpeed.count {
                    targetFanSpeed[i] = speed
                }
                
                applyFanSpeed(speed, forFan: i)
                
                if i < lastHardwareSetSpeed.count {
                    lastHardwareSetSpeed[i] = speed
                }
            }
        }
    }
    
    private func evaluateAndApplyFanCurve() {
        guard isManualFan && fanPreset > 0 else { return }
        
        let currentTemp = max(cpuTemp, gpuTemp)
        
        // Ensure state tracking arrays are correctly sized to active hardware fanCount
        if lastAppliedFanSpeed.count < fanCount {
            lastAppliedFanSpeed = Array(repeating: 2000.0, count: fanCount)
        }
        if lastHardwareSetSpeed.count < fanCount {
            lastHardwareSetSpeed = Array(repeating: 0.0, count: fanCount)
        }
        
        for i in 0..<fanCount {
            let minRPM = i < fanMinSpeed.count ? fanMinSpeed[i] : 1200
            let maxRPM = i < fanMaxSpeed.count ? fanMaxSpeed[i] : 6000
            
            // 1. Calculate raw target speed from current temperature-fan curve percentage
            let pct = interpolateSpeedPercentage(temp: currentTemp)
            let rawTargetSpeed = minRPM + (maxRPM - minRPM) * (pct / 100.0)
            
            // 2. Apply Asymmetric Hysteresis Smoothing (Low-pass EMA Filter)
            let currentApplied = lastAppliedFanSpeed[safe: i] ?? rawTargetSpeed
            let diff = rawTargetSpeed - currentApplied
            
            let alpha: Float
            if diff > 0 {
                // Temperature is rising -> cool down quickly (react fast for safety!)
                alpha = 0.25
            } else {
                // Temperature is falling -> reduce speed very slowly (smooth and quiet!)
                alpha = 0.03
            }
            
            let nextApplied = currentApplied + diff * alpha
            
            // Update last applied filtered speed
            if i < lastAppliedFanSpeed.count {
                lastAppliedFanSpeed[i] = nextApplied
            }
            
            if i < targetFanSpeed.count {
                targetFanSpeed[i] = nextApplied
            }
            
            // 3. Deadband optimization: Only trigger shell execution if:
            // - The difference from last actual hardware write is >= 50 RPM,
            // - Or it reaches limits to ensure exact min/max bounds are met
            let lastSet = lastHardwareSetSpeed[safe: i] ?? 0.0
            let isAtEdge = (nextApplied >= maxRPM - 100.0 && lastSet < maxRPM - 100.0) || 
                           (nextApplied <= minRPM + 100.0 && lastSet > minRPM + 100.0)
            
            if abs(nextApplied - lastSet) >= 50.0 || isAtEdge {
                // Set speed in hardware
                applyFanSpeed(nextApplied, forFan: i)
                
                // Update last actual hardware write speed
                if i < lastHardwareSetSpeed.count {
                    lastHardwareSetSpeed[i] = nextApplied
                }
            }
        }
    }
    
    private func interpolateSpeedPercentage(temp: Float) -> Float {
        // If in Silent mode and temp exceeds 85°C (thermal danger zone), dynamically scale to 100% at 92°C
        if fanPreset == 1 && temp > 85.0 {
            let startTemp: Float = 85.0
            let endTemp: Float = 92.0
            let ratio = min(max((temp - startTemp) / (endTemp - startTemp), 0.0), 1.0)
            return 55.0 + (100.0 - 55.0) * ratio
        }
        
        if temp <= customCurveTemp1 {
            return customCurveSpeed1
        } else if temp <= customCurveTemp2 {
            let gap = customCurveTemp2 - customCurveTemp1
            let ratio = gap > 0 ? (temp - customCurveTemp1) / gap : 0.0
            return customCurveSpeed1 + (customCurveSpeed2 - customCurveSpeed1) * ratio
        } else if temp <= customCurveTemp3 {
            let gap = customCurveTemp3 - customCurveTemp2
            let ratio = gap > 0 ? (temp - customCurveTemp2) / gap : 0.0
            return customCurveSpeed2 + (customCurveSpeed3 - customCurveSpeed2) * ratio
        } else if temp <= customCurveTemp4 {
            let gap = customCurveTemp4 - customCurveTemp3
            let ratio = gap > 0 ? (temp - customCurveTemp3) / gap : 0.0
            return customCurveSpeed3 + (customCurveSpeed4 - customCurveSpeed3) * ratio
        } else {
            return customCurveSpeed4
        }
    }
    
    private func loadBatteryCareSettings() {
        let res = smc.getBatteryChargeLimit()
        isChargeLimitEnabled = res.active
        batteryLimitValue = Float(res.limit)
    }
    
    private func toggleChargeLimit(_ enabled: Bool) {
        let limit = Int(batteryLimitValue)
        applyChargeLimit(limit, enabled: enabled)
    }
    
    private func applyChargeLimit(_ limit: Int, enabled: Bool) {
        let helperPath = smcHelperPath
        
        // 1. Direct SMC attempt (in case of root privileges already present or running natively)
        let _ = smc.setBatteryChargeLimit(limit, active: enabled)
        
        // 2. Privilege-based execution (standard way via smchelper)
        let activeInt = enabled ? 1 : 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.launchPath = "/usr/bin/sudo"
            proc.arguments  = ["-n", helperPath, "charge", String(limit), String(activeInt)]
            
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.showPrivilegeWarning = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showPrivilegeWarning = true
                }
            }
            
            // Re-read value to confirm success and update UI state
            let current = self.smc.getBatteryChargeLimit()
            DispatchQueue.main.async {
                self.isChargeLimitEnabled = current.active
                self.batteryLimitValue = Float(current.limit)
            }
        }
    }
    private func policyEmoji(_ policy: Int) -> String {
        switch policy {
        case 0: return "🍃"
        case 1: return "⚖️"
        default: return "🚀"
        }
    }
    
    private func acPolicyText(_ policy: Int) -> String {
        let isZh = currentLanguage == "zh-Hans"
        switch policy {
        case 0: return isZh ? "极静" : "Eco"
        case 1: return isZh ? "均衡" : "Balanced"
        default: return isZh ? "极致" : "Turbo"
        }
    }

    private func batteryPolicyText(_ policy: Int) -> String {
        let isZh = currentLanguage == "zh-Hans"
        switch policy {
        case 0: return isZh ? "极静" : "Eco"
        case 1: return isZh ? "均衡" : "Balanced"
        default: return isZh ? "极致" : "Turbo"
        }
    }

    private func acPolicyTipText(_ policy: Int) -> String {
        switch policy {
        case 0: return t("ac_policy_eco")
        case 1: return t("ac_policy_balanced")
        default: return t("ac_policy_turbo")
        }
    }

    private func batteryPolicyTipText(_ policy: Int) -> String {
        let isZh = currentLanguage == "zh-Hans"
        switch policy {
        case 0: return isZh ? "🍃 极致静音 (能耗极低)" : "🍃 Eco Silent (Low TDP)"
        case 1: return isZh ? "⚖️ 标准均衡 (能耗优化)" : "⚖️ Balanced (Normal)"
        default: return isZh ? "🚀 极致性能 (不限功耗)" : "🚀 Turbo (Max Perf)"
        }
    }

    private func applyLowPowerMode(type: String, policy: Int) {
        let helperPath = smcHelperPath
        
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.launchPath = "/usr/bin/sudo"
            proc.arguments  = ["-n", helperPath, "power", type, String(policy)]
            
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.showPrivilegeWarning = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showPrivilegeWarning = true
                }
            }
            
            DispatchQueue.main.async {
                self.isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
                if policy == 0 {
                    self.isLowPowerModeEnabled = true
                } else if policy == 1 || policy == 2 {
                    self.isLowPowerModeEnabled = false
                }
            }
        }
    }
    
    private func applyAggressiveSleep(_ enabled: Bool) {
        let helperPath = smcHelperPath
        let minutes = enabled ? 2 : 10
        
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.launchPath = "/usr/bin/sudo"
            proc.arguments  = ["-n", helperPath, "sleep", String(minutes)]
            
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.showPrivilegeWarning = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showPrivilegeWarning = true
                }
            }
            
            DispatchQueue.main.async {
                self.aggressiveScreenSleep = enabled
            }
        }
    }
    
    private var remainingWh: Double {
        let cap = powerStats.currentCapacity
        let volt = powerStats.batteryVoltage
        if cap > 0 && volt > 0 {
            return (cap / 1000.0) * volt
        }
        let soc = Double(powerStats.stateOfCharge) / 100.0
        return 70.0 * (soc > 0 ? soc : 0.8)
    }
    
    private func applyDynamicPowerSavingSettings() {
        let isConnected = powerStats.isConnected
        
        if isConnected {
            // AC 模式策略执行
            if acPowerPolicy == 0 { // 极静 Eco Silent
                applyLowPowerMode(type: "c", policy: 0)
                applyAggressiveSleepLimit(5)
                // 修复冲突#1：极静模式下，若风扇处于 Turbo(3)，自动降回均衡(2)，防止 CPU 限频但风扇全速空跑
                if fanCount > 0 && fanPreset == 3 {
                    DispatchQueue.main.async { self.applyPreset(2, skipPolicyCheck: true) }
                }
            } else if acPowerPolicy == 1 { // 均衡 Balanced
                applyLowPowerMode(type: "c", policy: 1)
                applyAggressiveSleepLimit(10)
                // 均衡模式：若风扇在 Turbo，降回均衡；若在自动，保持
                if fanCount > 0 && fanPreset == 3 {
                    DispatchQueue.main.async { self.applyPreset(2, skipPolicyCheck: true) }
                }
            } else { // 极致 Turbo
                applyLowPowerMode(type: "c", policy: 2)
                applyAggressiveSleepLimit(30)
                // 极致性能：若风扇在静音(1)，自动提升至均衡(2)，防止 CPU 满速但风扇被压低导致过热
                if fanCount > 0 && fanPreset == 1 {
                    DispatchQueue.main.async { self.applyPreset(2, skipPolicyCheck: true) }
                }
            }
        } else {
            // 电池模式策略执行
            guard autoAlignBatteryPolicies else { return }
            
            applyLowPowerMode(type: "b", policy: batteryPowerPolicy)
            
            if batteryPowerPolicy == 0 {
                // 修复冲突#2：极致节能(<=8W) 时，若风扇在 Turbo，自动降至静音，避免风扇电机白白消耗 1~2W
                applyAggressiveSleepLimit(1) // 1分钟休眠
                if keyboardMode == 0 {
                    let _ = KeyboardBacklightPrivate.setBrightness(0.0)
                    keyboardBrightness = 0.0
                }
                if fanCount > 0 && fanPreset == 3 {
                    DispatchQueue.main.async { self.applyPreset(1, skipPolicyCheck: true) }
                }
            } else if batteryPowerPolicy == 1 {
                // 中度节能(8~15W)：若 Turbo，降为均衡
                applyAggressiveSleepLimit(2) // 2分钟休眠
                if keyboardMode == 0 {
                    let _ = KeyboardBacklightPrivate.setBrightness(0.15)
                    keyboardBrightness = 0.15
                }
                if fanCount > 0 && fanPreset == 3 {
                    DispatchQueue.main.async { self.applyPreset(2, skipPolicyCheck: true) }
                }
            } else {
                // 高性能(>15W)：恢复标准配置
                applyAggressiveSleepLimit(10) // 恢复标准10分钟
            }
        }
    }
    
    private func applyAggressiveSleepLimit(_ minutes: Int) {
        let helperPath = smcHelperPath
        
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.launchPath = "/usr/bin/sudo"
            proc.arguments  = ["-n", helperPath, "sleep", String(minutes)]
            
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus != 0 {
                    DispatchQueue.main.async {
                        self.showPrivilegeWarning = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.showPrivilegeWarning = true
                }
            }
        }
    }
    
    private func toggleManualFan(_ manual: Bool) {
        let bitmask = UInt16(fanCount == 2 ? 3 : 1)
        let helperPath = smcHelperPath
        
        // 1. Try direct SMC write (if already root / running with native privileges)
        if smc.setFanManual(manual, fanBitmask: bitmask) {
            isManualFan = manual
            showPrivilegeWarning = false
            if manual {
                let targets = targetFanSpeed
                DispatchQueue.global(qos: .userInitiated).async {
                    for i in 0..<self.fanCount {
                        let _ = self.smc.setFanSpeed(i, speed: targets[safe: i] ?? 2000)
                    }
                }
            }
            return
        }
        
        // 2. sudo securely via Process array
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.launchPath = "/usr/bin/sudo"
            proc.arguments  = ["-n", helperPath, "manual", String(manual ? 1 : 0), String(bitmask)]
            
            var success = false
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    success = true
                }
            } catch { }
            
            DispatchQueue.main.async {
                if success {
                    self.isManualFan = manual
                    self.showPrivilegeWarning = false
                    
                    if manual {
                        let targets = self.targetFanSpeed
                        let fc      = self.fanCount > 0 ? self.fanCount : 2
                        DispatchQueue.global(qos: .userInitiated).async {
                            for i in 0..<fc {
                                let speed = targets[safe: i] ?? 2000
                                let p = Process()
                                p.launchPath = "/usr/bin/sudo"
                                p.arguments = ["-n", helperPath, "speed", String(i), String(Int(speed))]
                                try? p.run()
                                p.waitUntilExit()
                            }
                        }
                    }
                } else {
                    // Sudo passwordless execution failed or is not authorized
                    self.isManualFan = false
                    self.showPrivilegeWarning = true
                }
            }
        }
    }
    
    private func authorizeFanControl() {
        let embeddedPath = embeddedHelperPath
        let targetPath = smcHelperPath
        let currentUser = NSUserName()
        let sudoersContent = "\(currentUser) ALL=(root) NOPASSWD: \(targetPath)"
        
        // Securely copy helper to the permanent /Library/PrivilegedHelperTools path, adjust permissions, and configure sudoers
        let script = #"do shell script "mkdir -p /Library/PrivilegedHelperTools; cp '\#(embeddedPath)' '\#(targetPath)'; chown root:wheel '\#(targetPath)'; chmod 4755 '\#(targetPath)'; mkdir -p /etc/sudoers.d; echo '\#(sudoersContent)' > /etc/sudoers.d/smchelper; chmod 440 /etc/sudoers.d/smchelper" with administrator privileges"#
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if error == nil {
            showPrivilegeWarning = false
            toggleManualFan(true)
        }
    }
    
    // forFan: -1 = all fans, 0/1 = specific fan index
    private func applyFanSpeed(_ speed: Float, forFan fanIndex: Int) {
        let helperPath = smcHelperPath
        let fc = fanCount > 0 ? fanCount : 2  // fallback to 2 if not yet initialized
        let indices: [Int] = fanIndex == -1 ? Array(0..<fc) : [fanIndex]
        
        DispatchQueue.global(qos: .userInitiated).async {
            for i in indices {
                let proc = Process()
                proc.launchPath = "/usr/bin/sudo"
                proc.arguments  = ["-n", helperPath, "speed", String(i), String(Int(speed))]
                
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    if proc.terminationStatus != 0 {
                        DispatchQueue.main.async {
                            self.showPrivilegeWarning = true
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.showPrivilegeWarning = true
                    }
                }
            }
        }
    }



    private func applyKeyboardBrightness(_ brightness: Float) {
        guard keyboardMode == 0 else { return }
        let _ = KeyboardBacklightPrivate.setBrightness(brightness)
    }
    
    private func toggleKeyboardAnimation(mode: Int) {
        if mode == 1 {
            // Breathing Mode (Pulses uniformly)
            breathingStartTime = Date()
            breathingTask?.cancel()
            
            breathingTask = Timer.publish(every: 0.05, on: .main, in: .common)
                .autoconnect()
                .sink { [self] _ in
                    let elapsed = Date().timeIntervalSince(self.breathingStartTime)
                    let phase = (2.0 * .pi * elapsed) / self.breathingSpeed
                    let intensity = pow(sin(phase * 0.5), 2.0)
                    
                    let b = Float(intensity)
                    let _ = KeyboardBacklightPrivate.setBrightness(b)
                }
        } else if mode == 2 {
            // Wave Mode (Pulses overall physical backlight dynamically)
            breathingStartTime = Date()
            breathingTask?.cancel()
            
            breathingTask = Timer.publish(every: 0.05, on: .main, in: .common)
                .autoconnect()
                .sink { [self] _ in
                    let elapsed = Date().timeIntervalSince(self.breathingStartTime)
                    let phase = (2.0 * .pi * elapsed) / self.breathingSpeed
                    
                    // Single-zoned physical backlight pulses elegantly with a wavy wave phase (0.35 to 0.75)
                    let physicalIntensity = 0.35 + 0.4 * pow(sin(phase * 0.5), 2.0)
                    let _ = KeyboardBacklightPrivate.setBrightness(Float(physicalIntensity))
                }
        } else {
            // Static Mode
            breathingTask?.cancel()
            breathingTask = nil
            applyKeyboardBrightness(keyboardBrightness)
        }
    }
    
    // systemTelemetrySection (Collapsible Matrix & circular load rings)
    private var systemTelemetrySection: some View {
        VStack(spacing: 14) {
            // Header Row
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(Color(red: 0.62, green: 0.32, blue: 0.88))
                    .font(.system(size: 14))
                Text(t("system_telemetry"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.95))
                Spacer()
            }
            
            // Rings Gauges (CPU, GPU, FANS)
            HStack(spacing: 14) {
                // CPU Ring
                RingGauge(
                    progress: cpuUsage,
                    color: Color(red: 0.62, green: 0.32, blue: 0.88),
                    title: "CPU",
                    valueText: String(format: "%.0f°", cpuTemp),
                    subValueText: String(format: "%.2f GHz", cpuFreqPerf)
                )
                
                // GPU Ring
                RingGauge(
                    progress: gpuUsage,
                    color: Color(red: 0.22, green: 0.80, blue: 0.45),
                    title: "GPU",
                    valueText: String(format: "%.0f°", gpuTemp),
                    subValueText: String(format: "%.2f GHz", gpuFreq)
                )
                
                // Fan Ring
                let fanLoad = (fanMaxSpeed.first ?? 6000) > 0 ? Double(fanSpeed.first ?? 0) * 100.0 / Double(fanMaxSpeed.first ?? 6000) : 0.0
                RingGauge(
                    progress: fanCount > 0 ? fanLoad : 0.0,
                    color: Color(red: 0.18, green: 0.62, blue: 0.95),
                    title: "FANS",
                    valueText: fanCount > 0 ? String(format: "%.0f%%", fanLoad) : "PASSIVE",
                    subValueText: fanCount > 0 ? String(format: "%.0f RPM", fanSpeed.first ?? 0) : "0 RPM"
                )
            }
            .padding(.vertical, 4)
            
            // Collapsible Expanders (Temperatures, Power & Voltages, Fans, Frequencies)
            VStack(spacing: 8) {
                // 1. Temperatures Accordion
                DisclosureGroup(isExpanded: $isTempExpanded) {
                    VStack(spacing: 4) {
                        TelemetryRow(icon: "cpu", iconColor: Color(red: 0.62, green: 0.32, blue: 0.88), label: t("cpu_perf_cores"), value: String(format: "%.1f °C", tempCpuPerf), badgeColor: tempColorBadge(tempCpuPerf))
                        TelemetryRow(icon: "cpu", iconColor: Color(red: 0.82, green: 0.52, blue: 0.98), label: t("cpu_eff_cores"), value: String(format: "%.1f °C", tempCpuEff), badgeColor: tempColorBadge(tempCpuEff))
                        TelemetryRow(icon: "laptopcomputer", iconColor: Color(red: 0.22, green: 0.80, blue: 0.45), label: t("gpu_temp_label"), value: String(format: "%.1f °C", gpuTemp), badgeColor: tempColorBadge(gpuTemp))
                        TelemetryRow(icon: "internaldrive", iconColor: Color(red: 0.95, green: 0.60, blue: 0.18), label: t("ssd_temp"), value: String(format: "%.1f °C", tempSSD), badgeColor: tempColorBadge(tempSSD))
                        TelemetryRow(icon: "wifi", iconColor: Color(red: 0.18, green: 0.62, blue: 0.95), label: t("wifi_temp"), value: String(format: "%.1f °C", tempWiFi), badgeColor: tempColorBadge(tempWiFi))
                        TelemetryRow(icon: "memorychip", iconColor: Color(red: 0.85, green: 0.30, blue: 0.45), label: t("ram_temp"), value: String(format: "%.1f °C", tempMemory), badgeColor: tempColorBadge(tempMemory))
                        TelemetryRow(icon: "hand.point.up.braille", iconColor: Color(red: 0.55, green: 0.40, blue: 0.95), label: t("palm_temp"), value: String(format: "%.1f °C", tempPalmRest), badgeColor: tempColorBadge(tempPalmRest))
                        TelemetryRow(icon: "wind", iconColor: Color(red: 0.45, green: 0.75, blue: 0.95), label: t("airflow_temp"), value: String(format: "%.1f °C", tempAirflow), badgeColor: tempColorBadge(tempAirflow))
                        TelemetryRow(icon: "battery.100", iconColor: Color(red: 0.22, green: 0.80, blue: 0.45), label: t("battery_temp"), value: String(format: "%.1f °C", powerStats.batteryTemperature), badgeColor: tempColorBadge(Float(powerStats.batteryTemperature)))
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "thermometer.medium")
                            .foregroundColor(Color(red: 0.85, green: 0.30, blue: 0.45))
                        Text(t("temp_section"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                }
                .accentColor(.white.opacity(0.5))
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
                .focusable(false)
                
                // 2. Power & Voltages Accordion
                DisclosureGroup(isExpanded: $isPowerExpanded) {
                    VStack(spacing: 4) {
                        TelemetryRow(icon: "waveform.path.ecg", iconColor: Color(red: 0.62, green: 0.32, blue: 0.88), label: t("cpu_voltage_label"), value: String(format: "%.3f V / %.2f W", cpuVoltage, cpuPower))
                        TelemetryRow(icon: "waveform.path.ecg", iconColor: Color(red: 0.22, green: 0.80, blue: 0.45), label: t("gpu_voltage_label"), value: String(format: "%.3f V / %.2f W", gpuVoltage, gpuPower))
                        TelemetryRow(icon: "bolt.fill", iconColor: Color(red: 0.95, green: 0.60, blue: 0.18), label: t("battery_voltage_label"), value: String(format: "%.3f V", powerStats.batteryVoltage))
                        TelemetryRow(icon: "bolt.heart", iconColor: Color(red: 0.22, green: 0.80, blue: 0.45), label: t("total_power_label"), value: String(format: "%.2f W", totalPower))
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Color(red: 0.95, green: 0.60, blue: 0.18))
                        Text(t("power_voltage_section"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                }
                .accentColor(.white.opacity(0.5))
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
                .focusable(false)
                
                // 3. Fans Accordion
                DisclosureGroup(isExpanded: $isFanExpanded) {
                    VStack(spacing: 4) {
                        if fanCount > 0 {
                            ForEach(0..<fanCount, id: \.self) { idx in
                                let actual = fanSpeed[safe: idx] ?? 0.0
                                let maxSp = fanMaxSpeed[safe: idx] ?? 6000.0
                                let minSp = fanMinSpeed[safe: idx] ?? 1200.0
                                let label = currentLanguage == "zh-Hans" ? "物理风扇 \(idx)" : "Physical Fan \(idx)"
                                TelemetryRow(
                                    icon: "wind",
                                    iconColor: Color(red: 0.18, green: 0.62, blue: 0.95),
                                    label: label,
                                    value: String(format: "%.0f RPM (%.0f - %.0f)", actual, minSp, maxSp),
                                    showFanAnimation: true,
                                    fanRotation: fanRotationAngle
                                )
                            }
                        } else {
                            Text(t("fanless_desc"))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "wind")
                            .foregroundColor(Color(red: 0.18, green: 0.62, blue: 0.95))
                        Text(t("fan_section_title"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                }
                .accentColor(.white.opacity(0.5))
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
                .focusable(false)
                
                // 4. Frequencies Accordion
                DisclosureGroup(isExpanded: $isFreqExpanded) {
                    VStack(spacing: 4) {
                        TelemetryRow(icon: "speedometer", iconColor: Color(red: 0.62, green: 0.32, blue: 0.88), label: t("cpu_freq_perf"), value: String(format: "%.2f GHz", cpuFreqPerf))
                        TelemetryRow(icon: "speedometer", iconColor: Color(red: 0.82, green: 0.52, blue: 0.98), label: t("cpu_freq_eff"), value: String(format: "%.2f GHz", cpuFreqEff))
                        TelemetryRow(icon: "speedometer", iconColor: Color(red: 0.22, green: 0.80, blue: 0.45), label: t("gpu_freq_label"), value: String(format: "%.2f GHz", gpuFreq))
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Image(systemName: "speedometer")
                            .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                        Text(t("freq_section"))
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        Spacer()
                    }
                }
                .accentColor(.white.opacity(0.5))
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(10)
                .focusable(false)
            }
        }
        .padding(14)
        .background(
            Color(red: 0.11, green: 0.12, blue: 0.18).opacity(0.8)
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.3),
                            Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.1),
                            Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private func tempColorBadge(_ temp: Float) -> Color {
        if temp < 40.0 {
            return Color(red: 0.18, green: 0.62, blue: 0.95)
        } else if temp <= 70.0 {
            return Color(red: 0.95, green: 0.60, blue: 0.18)
        } else {
            return Color(red: 0.85, green: 0.15, blue: 0.15)
        }
    }
}

// MARK: - Laptop Schematic Subview

struct LaptopSchematicView: View {
    var activePort: Int // -1 = disconnected, 0 = L1, 1 = L2, 2 = R1, 3 = R2
    var rightPortCount: Int // 0, 1, or 2
    var currentLanguage: String
    
    private func t(_ key: String) -> String {
        let translations: [String: [String: String]] = [
            "zh-Hans": [
                "left_side": "左侧",
                "right_side": "右侧",
                "port_pos": "充电适配器接入位置：",
                "port_num": "号物理雷电/USB4端口",
                "no_adapter": "🔌 外部适配器未接通 (电池独立工作中)"
            ],
            "en": [
                "left_side": "Left Side",
                "right_side": "Right Side",
                "port_pos": "Adapter Connected At: ",
                "port_num": " USB4/Thunderbolt Port",
                "no_adapter": "🔌 AC Power Disconnected (Running on Battery)"
            ]
        ]
        let dict = translations[currentLanguage] ?? translations["zh-Hans"]!
        return dict[key] ?? key
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Laptop Diagram with Port Status Rings
            HStack(spacing: 14) {
                // Left Port list
                VStack(spacing: 10) {
                    portBadge(id: 0, label: "L1", isActive: activePort == 0)
                    portBadge(id: 1, label: "L2", isActive: activePort == 1)
                }
                
                // Keyboard Deck Representation
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 140, height: 85)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                        )
                    
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 114, height: 6)
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 114, height: 32)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 34, height: 20) // Trackpad
                    }
                    
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 36, height: 1.5)
                    }
                }
                .frame(width: 146, height: 90)
                
                // Right Port list
                VStack(spacing: 10) {
                    if rightPortCount == 2 {
                        portBadge(id: 2, label: "R1", isActive: activePort == 2)
                        portBadge(id: 3, label: "R2", isActive: activePort == 3)
                    } else if rightPortCount == 1 {
                        portBadge(id: 2, label: "R1", isActive: activePort == 2)
                        
                        // Physically adapted HDMI Port outline
                        VStack(spacing: 3) {
                            HDMIShape()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.2)
                                .frame(width: 13, height: 7)
                                .background(HDMIShape().fill(Color.black.opacity(0.3)))
                            Text("HDMI")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .frame(width: 24, height: 26)
                    } else {
                        // Fanless / MBA profile: no right ports, only AUX
                        VStack(spacing: 2) {
                            Circle()
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                .frame(width: 6, height: 6)
                            Text("AUX")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white.opacity(0.3))
                        }
                        .frame(width: 24, height: 26)
                    }
                }
            }
            
            // Description of active port location
            if activePort >= 0 {
                let sideStr = (activePort == 0 || activePort == 1) ? t("left_side") : t("right_side")
                let numStr = (activePort == 0 || activePort == 2) ? "1" : "2"
                
                HStack(spacing: 6) {
                    Image(systemName: "cable.coaxial")
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                    Text("\(t("port_pos"))\(sideStr) \(numStr)\(t("port_num"))")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(Color(red: 0.22, green: 0.80, blue: 0.45))
                }
                .padding(.vertical, 2)
            } else {
                Text(t("no_adapter"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private func portBadge(id: Int, label: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            if id >= 2 {
                indicatorDot(isActive: isActive)
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? Color(red: 0.22, green: 0.80, blue: 0.45) : .white.opacity(0.3))
            } else {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? Color(red: 0.22, green: 0.80, blue: 0.45) : .white.opacity(0.3))
                indicatorDot(isActive: isActive)
            }
        }
    }
    
    private func indicatorDot(isActive: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isActive ? Color(red: 0.22, green: 0.80, blue: 0.45) : Color.white.opacity(0.12))
                .frame(width: 7, height: 7)
            
            if isActive {
                Circle()
                    .stroke(Color(red: 0.22, green: 0.80, blue: 0.45), lineWidth: 1.5)
                    .frame(width: 13, height: 13)
                    .scaleEffect(1.0)
                    .opacity(0.8)
            }
        }
        .frame(width: 13, height: 13)
    }
}

struct HDMIShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.6))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY * 0.6))
        path.closeSubpath()
        return path
    }
}

// MARK: - Sine Wave Path Shape for UI preview

struct SineWave: Shape {
    var phase: Double
    var amplitude: Double
    
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midY = height / 2
        
        path.move(to: CGPoint(x: 0, y: midY))
        
        // Draw double cycle sine wave
        for x in stride(from: 0, to: width + 1, by: 2) {
            let relativeX = x / width
            let sine = sin(relativeX * 2.0 * .pi * 2.0 - phase)
            let y = midY + CGFloat(sine) * CGFloat(amplitude)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        return path
    }
}

// MARK: - Launch at Login Helper Manager

class LaunchAtLoginHelper {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return UserDefaults.standard.bool(forKey: "LaunchAtLoginLegacy")
            }
        }
        set {
            if #available(macOS 13.0, *) {
                let service = SMAppService.mainApp
                do {
                    if newValue {
                        if service.status != .enabled {
                            try service.register()
                        }
                    } else {
                        if service.status == .enabled {
                            try service.unregister()
                        }
                    }
                } catch {
                    print("SMAppService registration toggled with failure: \(error)")
                }
            } else {
                UserDefaults.standard.set(newValue, forKey: "LaunchAtLoginLegacy")
                
                let appPath = Bundle.main.bundlePath
                let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "HelperStatusBar"
                
                if newValue {
                    let script = "tell application \"System Events\" to make new login item at end with properties {path:\"\(appPath)\", name:\"\(appName)\", hidden:false}"
                    let appleScript = NSAppleScript(source: script)
                    var error: NSDictionary?
                    appleScript?.executeAndReturnError(&error)
                } else {
                    let script = "tell application \"System Events\" to delete login item \"\(appName)\""
                    let appleScript = NSAppleScript(source: script)
                    var error: NSDictionary?
                    appleScript?.executeAndReturnError(&error)
                }
            }
        }
    }
}

// MARK: - Advanced Hardware Telemetry Components

struct RingGauge: View {
    var progress: Double
    var color: Color
    var title: String
    var valueText: String
    var subValueText: String
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background Circle Track
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 5)
                    .frame(width: 72, height: 72)
                
                // Active Progress Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(progress / 100.0, 0.0), 1.0)))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.7), color, color.opacity(0.9), color.opacity(0.7)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0), value: progress)
                    .shadow(color: color.opacity(0.3), radius: 3, x: 0, y: 0)
                
                // Centered Information labels
                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    
                    Text(valueText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))
                    
                    Text(subValueText)
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

struct TelemetryRow: View {
    var icon: String
    var iconColor: Color
    var label: String
    var value: String
    var badgeColor: Color? = nil
    var showFanAnimation: Bool = false
    var fanRotation: Double = 0.0
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(showFanAnimation ? fanRotation : 0.0))
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.95))
            
            if let badgeColor = badgeColor {
                Circle()
                    .fill(badgeColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: badgeColor.opacity(0.8), radius: 3)
                    .padding(.leading, 2)
            }
        }
        .padding(.vertical, 3.5)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.015))
        .cornerRadius(6)
    }
}

class CPUMonitor {
    private var prevCpuInfo: processor_info_array_t?
    private var prevCpuInfoCount: mach_msg_type_number_t = 0
    private var numCPUs: uint32 = 0
    private let lock = NSLock()
    
    init() {
        lock.lock()
        defer { lock.unlock() }
        var processorCount: uint32 = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &processorInfoCount)
        if result == KERN_SUCCESS, let info = processorInfo {
            self.numCPUs = processorCount
            self.prevCpuInfo = info
            self.prevCpuInfoCount = processorInfoCount
        }
    }
    
    deinit {
        lock.lock()
        defer { lock.unlock() }
        if let info = prevCpuInfo {
            let size = vm_size_t(prevCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
            prevCpuInfo = nil
        }
    }
    
    func getUsage() -> Double {
        lock.lock()
        defer { lock.unlock() }
        var processorCount: uint32 = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &processorInfo, &processorInfoCount)
        guard result == KERN_SUCCESS, let info = processorInfo else {
            return 0.0
        }
        
        var totalUsage = 0.0
        
        for i in 0..<Int(processorCount) {
            let base = i * Int(CPU_STATE_MAX)
            
            let user = info[base + Int(CPU_STATE_USER)]
            let system = info[base + Int(CPU_STATE_SYSTEM)]
            let nice = info[base + Int(CPU_STATE_NICE)]
            let idle = info[base + Int(CPU_STATE_IDLE)]
            
            var prevUser: integer_t = 0
            var prevSystem: integer_t = 0
            var prevNice: integer_t = 0
            var prevIdle: integer_t = 0
            
            if let prevInfo = prevCpuInfo, i < Int(numCPUs) {
                let prevBase = i * Int(CPU_STATE_MAX)
                prevUser = prevInfo[prevBase + Int(CPU_STATE_USER)]
                prevSystem = prevInfo[prevBase + Int(CPU_STATE_SYSTEM)]
                prevNice = prevInfo[prevBase + Int(CPU_STATE_NICE)]
                prevIdle = prevInfo[prevBase + Int(CPU_STATE_IDLE)]
            }
            
            let userDiff = user - prevUser
            let systemDiff = system - prevSystem
            let niceDiff = nice - prevNice
            let idleDiff = idle - prevIdle
            
            let active = userDiff + systemDiff + niceDiff
            let total = active + idleDiff
            
            if total > 0 {
                totalUsage += Double(active) / Double(total)
            }
        }
        
        if let prevInfo = prevCpuInfo {
            let size = vm_size_t(prevCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevInfo), size)
        }
        
        prevCpuInfo = info
        prevCpuInfoCount = processorInfoCount
        numCPUs = processorCount
        
        let avgUsage = totalUsage / Double(processorCount) * 100.0
        return max(0.0, min(100.0, avgUsage))
    }
}

// ── macOS bottom-level ScrollWheel & Trackpad Swipe Detector ──
struct ScrollWheelDetector: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = ScrollNSView()
        view.onScroll = onScroll
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let scrollNSView = nsView as? ScrollNSView {
            scrollNSView.onScroll = onScroll
        }
    }
    
    class ScrollNSView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var lastScrollTime: Date = Date.distantPast
        
        override var acceptsFirstResponder: Bool { true }
        
        override func scrollWheel(with event: NSEvent) {
            let deltaY = event.scrollingDeltaY
            let now = Date()
            let timeSinceLastScroll = now.timeIntervalSince(lastScrollTime)
            
            // 1. 如果当前处于 0.5s 的翻页转场动画冷却期内，完全吞掉所有滚轮事件，
            // 避免在页面上下滑动时，内部 ScrollView 同时发生纵向位移而导致画面混乱和抖动
            if timeSinceLastScroll < 0.5 {
                return
            }
            
            // 2. 如果滚动幅度超过阈值，视为用户的翻页手势
            if abs(deltaY) > 1.5 {
                onScroll?(deltaY)
                lastScrollTime = now
                // 同样吞掉该事件，不向下传递，确保转场前一瞬间内部不发生意外抖动
                return
            }
            
            // 3. 正常慢速滚动，向下传递给子视图的 ScrollView 进行正常的列表内容滚动
            super.scrollWheel(with: event)
        }
    }
}

// MARK: - Bento Privacy Switch Card
struct PrivacySwitchCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @Binding var isEnabled: Bool
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isEnabled.toggle()
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isEnabled ? color.opacity(0.15) : Color.white.opacity(0.05))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: icon)
                            .font(.system(size: 11))
                            .foregroundColor(isEnabled ? color : .white.opacity(0.4))
                    }
                    
                    Spacer()
                    
                    Circle()
                        .fill(isEnabled ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 6, height: 6)
                }
                
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(isEnabled ? 0.6 : 0.3))
                    .lineLimit(1)
            }
            .padding(10)
            .background(isEnabled ? Color.white.opacity(0.04) : Color.white.opacity(0.02))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isEnabled ? color.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: isEnabled ? color.opacity(0.1) : Color.clear, radius: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tactical Button Style
struct ScrambledKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .brightness(configuration.isPressed ? -0.1 : 0.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

