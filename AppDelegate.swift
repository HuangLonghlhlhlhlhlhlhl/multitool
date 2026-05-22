import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    
    // MARK: - Launch
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] Launching status bar helper app...")
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Popover（左键展开的主面板）
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 620)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: DashboardView())
        self.popover = popover
        
        // 2. 状态栏按钮
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = self.statusBarItem?.button {
            button.image = makeStatusBarIcon()
            
            // 同时响应左键（主动作）和右键（菜单）
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleStatusBarClick(_:))
            button.target = self
        }
        
        // 启动高密度状态栏遥测定时器
        startTelemetryTimer()
    }
    
    // MARK: - Icon
    
    private func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            
            // Gradient ring
            context.saveGState()
            let ringPath = CGPath(ellipseIn: rect.insetBy(dx: 1.5, dy: 1.5), transform: nil)
            context.addPath(ringPath)
            context.setLineWidth(1.8)
            context.replacePathWithStrokedPath()
            context.clip()
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradientColors = [
                NSColor(red: 0.00, green: 0.95, blue: 1.00, alpha: 1.0).cgColor,
                NSColor(red: 0.62, green: 0.00, blue: 1.00, alpha: 1.0).cgColor,
                NSColor(red: 1.00, green: 0.00, blue: 0.67, alpha: 1.0).cgColor,
                NSColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 1.0).cgColor,
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 0.33, 0.66, 1.0]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 18, y: 0), options: [])
            }
            context.restoreGState()
            
            // Power symbol
            context.saveGState()
            context.setLineWidth(1.8)
            context.setLineCap(.round)
            context.setStrokeColor(NSColor.white.cgColor)
            context.addArc(center: center, radius: 4.2,
                           startAngle: CGFloat(120.0 * Double.pi / 180.0),
                           endAngle:   CGFloat(60.0  * Double.pi / 180.0),
                           clockwise: false)
            context.strokePath()
            context.move(to: CGPoint(x: center.x, y: center.y - 1.0))
            context.addLine(to: CGPoint(x: center.x, y: center.y + 4.5))
            context.strokePath()
            context.restoreGState()
            return true
        }
        image.isTemplate = false
        return image
    }
    
    // MARK: - Click Handler
    
    @objc func handleStatusBarClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // 右键 / Control+左键 → 弹出菜单
            showContextMenu()
        } else {
            // 左键 → 打开 / 关闭主面板
            togglePopover(sender)
        }
    }
    
    private func togglePopover(_ sender: AnyObject?) {
        guard let button = self.statusBarItem?.button, let popover = self.popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    // MARK: - Context Menu
    
    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 标题（不可点击）
        let titleItem = NSMenuItem(title: "STATUS CTRL", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        if let font = NSFont.systemFont(ofSize: 12, weight: .semibold) as NSFont? {
            titleItem.attributedTitle = NSAttributedString(
                string: "STATUS CTRL",
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }
        menu.addItem(titleItem)
        menu.addItem(.separator())
        
        // 打开主面板
        let openItem = NSMenuItem(title: "打开主面板", action: #selector(openDashboard), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)
        menu.addItem(openItem)
        
        menu.addItem(.separator())
        
        // 设置
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        
        // 关于
        let aboutItem = NSMenuItem(title: "关于 STATUS CTRL…", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)
        
        menu.addItem(.separator())
        
        // 退出
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
        
        // 在按钮位置弹出
        if let button = statusBarItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
        }
    }
    
    // MARK: - Menu Actions
    
    @objc private func openDashboard() {
        togglePopover(nil)
    }
    
    @objc private func openSettings() {
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hostingController)
        win.title = "设置"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 440, height: 380))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = win
    }
    
    @objc private func openAbout() {
        if let win = aboutWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingController = NSHostingController(rootView: AboutView())
        let win = NSWindow(contentViewController: hostingController)
        win.title = "关于"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 360, height: 280))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.aboutWindow = win
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Telemetry Integration
    
    private var telemetryTimer: Timer?
    private let cpuMonitor = CPUMonitor()
    
    func startTelemetryTimer() {
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTelemetryText()
        }
        RunLoop.current.add(telemetryTimer!, forMode: .common)
        updateTelemetryText()
    }
    
    private func updateTelemetryText() {
        guard let button = self.statusBarItem?.button else { return }
        
        let cpuTemp = SMCController.shared.getCPUTemperature()
        let cpuUsage = cpuMonitor.getUsage()
        
        let ramTemp = SMCController.shared.getMemoryTemperature()
        let ramUsage = getRAMUsage()
        
        let ssdTemp = SMCController.shared.getSSDTemperature()
        let ssdUsage = getSSDUsage()
        
        // Format: C:45° 5% M:36° 42% S:32° 48%
        let text = String(format: "C:%.0f° %.0f%% M:%.0f° %.0f%% S:%.0f° %.0f%%",
                          cpuTemp, cpuUsage,
                          ramTemp, ramUsage,
                          ssdTemp, ssdUsage)
        
        let font = NSFont.monospacedSystemFont(ofSize: 7.5, weight: .regular)
        let attribs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let attributedString = NSAttributedString(string: " " + text, attributes: attribs)
        
        DispatchQueue.main.async {
            button.attributedTitle = attributedString
            button.imagePosition = .imageLeft
        }
    }
    
    func getRAMUsage() -> Double {
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
    
    func getSSDUsage() -> Double {
        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity, total > 0 {
                let used = total - available
                return (Double(used) / Double(total)) * 100.0
            }
        } catch {
            print("[Telemetry] Error getting SSD usage: \(error)")
        }
        return 0.0
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 1.5
    @AppStorage("showCPUTemp") private var showCPUTemp: Bool = true
    @AppStorage("showGPUTemp") private var showGPUTemp: Bool = true
    @AppStorage("showBattery") private var showBattery: Bool = true
    @AppStorage("showFan") private var showFan: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 12) {
                    
                    // 显示内容
                    SettingsSection(title: "面板显示项目") {
                        SettingsToggleRow(label: "显示 CPU 温度", icon: "thermometer", isOn: $showCPUTemp)
                        Divider().padding(.leading, 36)
                        SettingsToggleRow(label: "显示 GPU 温度", icon: "cpu", isOn: $showGPUTemp)
                        Divider().padding(.leading, 36)
                        SettingsToggleRow(label: "显示电池信息", icon: "battery.100", isOn: $showBattery)
                        Divider().padding(.leading, 36)
                        SettingsToggleRow(label: "显示风扇转速", icon: "fan", isOn: $showFan)
                    }
                    
                    // 刷新频率
                    SettingsSection(title: "性能") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text("刷新间隔")
                                Spacer()
                                Text(String(format: "%.1f 秒", refreshInterval))
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            Slider(value: $refreshInterval, in: 0.5...5.0, step: 0.5)
                                .padding(.leading, 28)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("完成") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 440, height: 380)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - About View

struct AboutView: View {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    
    var body: some View {
        VStack(spacing: 20) {
            // App 图标区
            if let nsImage = NSApp.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.08, green: 0.08, blue: 0.15),
                                         Color(red: 0.12, green: 0.05, blue: 0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                        .shadow(color: .purple.opacity(0.4), radius: 12)
                    
                    Image(systemName: "fan.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .purple, .pink],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                }
            }
            
            VStack(spacing: 6) {
                Text("STATUS CTRL")
                    .font(.system(size: 20, weight: .bold))
                
                Text("版本 \(version)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Text("macOS 硬件监控与风扇控制工具")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 4) {
                Text("支持 Apple Silicon · Intel · Universal Binary")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("macOS 12 Monterey 或更高版本")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("© 2026 HL. 保留所有权利。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Button("关闭") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(32)
        .frame(width: 360, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Settings Helpers

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            
            VStack(spacing: 0) {
                content
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }
}

struct SettingsToggleRow: View {
    let label: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(label)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
