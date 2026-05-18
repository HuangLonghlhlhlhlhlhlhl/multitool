import SwiftUI
import Combine
import ServiceManagement

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DashboardView: View {
    
    // Core Managers
    private let smc = SMCController()
    
    // smchelper path: embedded in app bundle (Contents/MacOS/smchelper)
    // Falls back to legacy Desktop path for dev builds
    private var smcHelperPath: String {
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
    @State private var cpuTemp: Float = 42.0
    @State private var gpuTemp: Float = 40.0
    
    // Fan states — per-fan independent control
    @State private var fanCount: Int = 0
    @State private var fanSpeed: [Float] = [0.0, 0.0]          // actual RPM per fan
    @State private var fanMinSpeed: [Float] = [1200.0, 1200.0] // SMC min per fan
    @State private var fanMaxSpeed: [Float] = [6000.0, 6000.0] // SMC max per fan
    @State private var targetFanSpeed: [Float] = [2000.0, 2000.0] // target per fan
    @State private var isManualFan: Bool = false
    @State private var fanLinked: Bool = true  // true = both fans move together
    @State private var fanRotationAngle: Double = 0.0
    
    // Keyboard Light States
    @State private var keyboardBrightness: Float = 0.5
    @State private var keyboardMode: Int = UserDefaults.standard.integer(forKey: "KeyboardLightingMode") // 0 = Static, 1 = Breathing, 2 = Wave
    @State private var breathingSpeed: Double = 4.0 // Period in seconds
    @State private var wavePhase: Double = 0.0
    
    // Power Monitor States
    @State private var powerStats = PowerMonitor.PowerStats()
    
    // Interactive feedback
    @State private var messagePrompt: String = ""
    @State private var showPrivilegeWarning: Bool = false
    
    // Helper breathing variables
    @State private var breathingTask: AnyCancellable?
    @State private var breathingStartTime = Date()
    
    // Settings States
    @State private var showSettings: Bool = false
    @State private var currentLanguage: String = UserDefaults.standard.string(forKey: "AppLanguage") ?? "zh-Hans"
    @State private var launchAtLogin: Bool = false
    @State private var donateMethod: Int = 0 // 0 = Alipay, 1 = WeChat
    @State private var qrScanOffset: CGFloat = -50.0
    @State private var showDonateAlert: Bool = false
    
    // Localization Helper
    private let translations: [String: [String: String]] = [
        "zh-Hans": [
            "title": "多功能小助手",
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
            "wave_status": "🌊 键盘背光交替波浪中..."
        ],
        "en": [
            "title": "Helper Menu Bar",
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
            "wave_status": "🌊 Keyboard wave shifting..."
        ]
    ]
    
    private func t(_ key: String) -> String {
        let dict = translations[currentLanguage] ?? translations["zh-Hans"]!
        return dict[key] ?? key
    }
    
    var body: some View {
        ZStack {
            // Main Dashboard View Panel
            VStack(spacing: 16) {
                // Header Bar
                headerSection
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Power Monitor Section
                        powerSection
                        
                        // Fan Control Section
                        if fanCount > 0 {
                            fanSection
                        } else {
                            fanlessSection
                        }
                        
                        // Keyboard Backlight Section
                        keyboardSection
                        
                        // System info footer
                        footerSection
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(18)
            .blur(radius: showSettings ? 12 : 0)
            
            // Slide-Over Settings Panel Overlay (With elegant transitions)
            if showSettings {
                settingsSection
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(width: 380, height: 620)
        .background(
            ZStack {
                // High-end Dark Morandi Gradient Background
                Color(red: 0.08, green: 0.09, blue: 0.12)
                
                // Abstract Glowing Orbs (Premium visual depth)
                RadialGradient(colors: [Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 200)
                RadialGradient(colors: [Color(red: 0.22, green: 0.80, blue: 0.45).opacity(0.08), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 200)
            }
        )
        .preferredColorScheme(.dark)
        .onAppear {
            initializeHardware()
        }
        .onReceive(statsTimer) { _ in
            refreshStats()
        }
        .onReceive(fanRotationTimer) { _ in
            updateFanRotation()
        }
        .onReceive(waveTimer) { _ in
            updateWaveAnimation()
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
            
            // Temperature Quick Badges & Settings Trigger
            HStack(spacing: 8) {
                tempBadge(title: "CPU", temp: cpuTemp, color: Color(red: 0.18, green: 0.62, blue: 0.95))
                tempBadge(title: "GPU", temp: gpuTemp, color: Color(red: 0.62, green: 0.32, blue: 0.88))
                
                // Settings Gear Button with spring feedback
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
            .padding(.top, 4)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                
                // Auto / Manual mode selector
                HStack(spacing: 0) {
                    Button(action: { toggleManualFan(false) }) {
                        Text(t("fan_auto"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(!isManualFan ? Color(red: 0.18, green: 0.62, blue: 0.95) : .white.opacity(0.5))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(!isManualFan ? Color.white.opacity(0.08) : Color.clear)
                            .cornerRadius(6)
                    }.buttonStyle(.plain)
                    
                    Button(action: { toggleManualFan(true) }) {
                        Text(t("fan_manual"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(isManualFan ? Color(red: 0.95, green: 0.60, blue: 0.18) : .white.opacity(0.5))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(isManualFan ? Color.white.opacity(0.08) : Color.clear)
                            .cornerRadius(6)
                    }.buttonStyle(.plain)
                }
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
            }
            
            // Fan speed status cards (one per fan)
            let displayCount = max(fanCount, 1)
            HStack(spacing: 10) {
                ForEach(0..<displayCount, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(i == 0 ? "左风扇" : "右风扇")
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
            
            // Manual sliders
            if isManualFan {
                VStack(spacing: 10) {
                    // Linked / Independent toggle
                    if fanCount == 2 {
                        HStack(spacing: 6) {
                            Image(systemName: fanLinked ? "link" : "link.badge.plus")
                                .font(.system(size: 10))
                                .foregroundColor(fanLinked ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color(red: 0.62, green: 0.32, blue: 0.88))
                            Text(fanLinked ? "联动调节" : "独立调节")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(fanLinked ? Color(red: 0.18, green: 0.62, blue: 0.95) : Color(red: 0.62, green: 0.32, blue: 0.88))
                            Spacer()
                            Toggle("", isOn: $fanLinked)
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.18, green: 0.62, blue: 0.95)))
                                .labelsHidden()
                                .scaleEffect(0.75)
                        }
                        .padding(.horizontal, 4)
                    }
                    
                    // Per-fan sliders
                    ForEach(0..<displayCount, id: \.self) { i in
                        fanSliderRow(index: i, displayCount: displayCount)
                    }
                }
                .padding(.top, 6)
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
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
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
        let label    = (i == 0 ? "左风扇" : "右风扇") + (fanLinked && fanCount == 2 ? "（联动）" : "")

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
        .frame(width: 380, height: 620)
        .background(
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                RadialGradient(colors: [Color(red: 0.18, green: 0.62, blue: 0.95).opacity(0.14), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
                RadialGradient(colors: [Color(red: 0.62, green: 0.32, blue: 0.88).opacity(0.09), .clear], center: .bottomLeading, startRadius: 0, endRadius: 200)
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
        
        // Launch behavior sync
        launchAtLogin = LaunchAtLoginHelper.isEnabled
    }
    
    private func refreshStats() {
        cpuTemp = smc.getCPUTemperature()
        gpuTemp = smc.getGPUTemperature()
        powerStats = PowerMonitor.getPowerStats()
        
        if fanCount > 0 {
            for i in 0..<fanCount {
                let ac = smc.getFanSpeed(i)
                if i < fanSpeed.count { fanSpeed[i] = ac }
            }
        }
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
    
    private func toggleManualFan(_ manual: Bool) {
        let bitmask = UInt16(fanCount == 2 ? 3 : 1)
        let helperPath = smcHelperPath
        
        // 1. Try direct SMC write (if already root)
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
        
        // 2. sudo via /bin/sh -c
        let manualCmd = "sudo -n '\(helperPath)' manual \(manual ? 1 : 0) \(bitmask)"
        let proc = Process()
        proc.launchPath = "/bin/sh"
        proc.arguments  = ["-c", manualCmd]
        
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { /* Process launch failed, best-effort */ }
        
        isManualFan = manual
        showPrivilegeWarning = false
        
        if manual {
            let targets = targetFanSpeed
            let fc      = fanCount > 0 ? fanCount : 2
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<fc {
                    let speed = targets[safe: i] ?? 2000
                    let cmd   = "sudo -n '\(helperPath)' speed \(i) \(Int(speed))"
                    let p = Process(); p.launchPath = "/bin/sh"; p.arguments = ["-c", cmd]
                    try? p.run(); p.waitUntilExit()
                }
            }
        }
    }
    

    private func authorizeFanControl() {
        let helperPath = smcHelperPath
        let currentUser = NSUserName()
        let sudoersContent = "\(currentUser) ALL=(root) NOPASSWD: \(helperPath)"
        
        // Securely write to /etc/sudoers.d/smchelper with root ownership and 440 permissions
        let script = #"do shell script "mkdir -p /etc/sudoers.d; echo '\#(sudoersContent)' > /etc/sudoers.d/smchelper; chmod 440 /etc/sudoers.d/smchelper" with administrator privileges"#
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
                // Build the shell command
                let shellCmd = "sudo -n '\(helperPath)' speed \(i) \(Int(speed))"
                
                // Use /bin/sh -c for reliable execution (same as terminal)
                let proc = Process()
                proc.launchPath = "/bin/sh"
                proc.arguments  = ["-c", shellCmd]
                
                do {
                    try proc.run()
                    proc.waitUntilExit()
                } catch { /* best-effort */ }
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
