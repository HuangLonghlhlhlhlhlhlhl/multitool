import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusBarItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    var statusBarCustomView: StatusBarCustomView?
    
    // MARK: - Launch
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] Launching status bar helper app...")
        NSApp.setActivationPolicy(.accessory)
        
        // 1. Popover（左键展开的主面板）
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 680, height: 530)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: DashboardView())
        self.popover = popover
        
        // 2. 状态栏按钮
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = self.statusBarItem?.button {
            button.image = nil
            button.title = ""
            
            // 添加高精度绝对居中及 Logo 绘制自定义视图
            let customView = StatusBarCustomView()
            customView.logoImage = makeStatusBarIcon()
            customView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(customView)
            
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                customView.topAnchor.constraint(equalTo: button.topAnchor),
                customView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            self.statusBarCustomView = customView
            
            // Configure cell for multi-line layout and auto-wrapping
            button.cell?.usesSingleLineMode = false
            button.cell?.wraps = true
            button.cell?.lineBreakMode = .byClipping
            
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
    private let networkMonitor = NetworkMonitor()
    private let telemetryQueue = DispatchQueue(label: "com.statusctrl.appdelegate.telemetry", qos: .utility)
    private var isUpdatingTelemetry = false
    
    func startTelemetryTimer() {
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateTelemetryText()
        }
        RunLoop.current.add(telemetryTimer!, forMode: .common)
        updateTelemetryText()
    }
    
    private func updateTelemetryText() {
        guard !isUpdatingTelemetry else { return }
        isUpdatingTelemetry = true
        
        telemetryQueue.async { [weak self] in
            guard let self = self else { return }
            
            let cpuUsage = self.cpuMonitor.getUsage()
            let ramUsage = self.getRAMUsage()
            let ssdUsage = self.getSSDUsage()
            let (upSpeed, downSpeed) = self.networkMonitor.getSpeed()
            
            let cpuTemp = SMCController.shared.getCPUTemperature()
            let ramTemp = SMCController.shared.getMemoryTemperature()
            let ssdTemp = SMCController.shared.getSSDTemperature()
            
            DispatchQueue.main.async {
                self.isUpdatingTelemetry = false
                self.renderTelemetry(
                    cpuUsage: cpuUsage, cpuTemp: Double(cpuTemp),
                    ramUsage: ramUsage, ramTemp: Double(ramTemp),
                    ssdUsage: ssdUsage, ssdTemp: Double(ssdTemp),
                    upSpeed: upSpeed, downSpeed: downSpeed
                )
            }
        }
    }
    
    private func padSpeedRight(_ speedStr: String, toLength length: Int = 7) -> String {
        let paddingCount = length - speedStr.count
        if paddingCount > 0 {
            return speedStr + String(repeating: " ", count: paddingCount)
        }
        return String(speedStr.prefix(length))
    }
    
    private func renderTelemetry(
        cpuUsage: Double, cpuTemp: Double,
        ramUsage: Double, ramTemp: Double,
        ssdUsage: Double, ssdTemp: Double,
        upSpeed: Double, downSpeed: Double
    ) {
        guard self.statusBarItem?.button != nil else { return }
        
        // 限制最大值为 99%，防止 100% 导致排版位移，同时保证等宽对齐
        let displayCpu = min(cpuUsage, 99.0)
        let displayRam = min(ramUsage, 99.0)
        let displaySsd = min(ssdUsage, 99.0)
        
        // 第一行：效率指标 (格式固定为 5 字符，例如 "C: 8%")
        let cpuUsageStr = String(format: "C:%2.0f%%", displayCpu)
        let ramUsageStr = String(format: "M:%2.0f%%", displayRam)
        let ssdUsageStr = String(format: "S:%2.0f%%", displaySsd)
        
        // 第二行：温度指标 (前置两个空格以和第一行数字及单位完美上下垂直重合对齐，使用真正的度数符号，例如 "  45°")
        let cpuTempStr = String(format: "  %2.0f°", cpuTemp)
        let ramTempStr = String(format: "  %2.0f°", ramTemp)
        let ssdTempStr = String(format: "  %2.0f°", ssdTemp)
        
        // 网速处理：将网速数字与箭头紧贴拼接，然后在右侧补齐空格，保持总长度 7 字符且没有间隙，同时实现箭头左侧完全对齐
        let upSpeedCompact = formatSpeedCompact(upSpeed)
        let upSpeedRaw = "⇡" + upSpeedCompact
        let upSpeedStr = padSpeedRight(upSpeedRaw, toLength: 7)
        
        let downSpeedCompact = formatSpeedCompact(downSpeed)
        let downSpeedRaw = "⇣" + downSpeedCompact
        let downSpeedStr = padSpeedRight(downSpeedRaw, toLength: 7)
        
        // 拼接双行内容，使用 1 个空格分隔 C-M-S，2 个空格分隔 S-网速，以严格符合用户提供的紧凑样式和完美对齐结构
        let line1 = "\(cpuUsageStr) \(ramUsageStr) \(ssdUsageStr)  \(upSpeedStr)"
        let line2 = "\(cpuTempStr) \(ramTempStr) \(ssdTempStr)  \(downSpeedStr)"
        let combinedString = "\(line1)\n\(line2)"
        
        // 字体放大 10% (9.0 -> 10.0)，设置自适应紧凑行距以减小两行总高度，从而实现在自定义绘图中的绝对完美居中
        let font = NSFont.monospacedSystemFont(ofSize: 10.0, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = -3.2 // 紧密拉近两行行距，防止超出状态栏被裁切
        paragraphStyle.alignment = .left
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let attrString = NSAttributedString(string: combinedString, attributes: attributes)
        
        // 1. 更新自适应自平衡宽度：左边距 2 + Logo 18 + 间距 4 + 文字宽度 + 右边距 6 = 文字宽度 + 30pt
        let totalSize = attrString.size()
        let requiredWidth = ceil(totalSize.width) + 30
        self.statusBarItem?.length = requiredWidth
        
        // 2. 将数据赋给自定义高精度垂直居中视图进行渲染
        self.statusBarCustomView?.attributedString = attrString
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

// MARK: - Network Monitor and Helpers

class NetworkMonitor {
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTime: Date = Date()
    
    init() {
        let (bytesIn, bytesOut) = getNetworkBytes()
        self.lastBytesIn = bytesIn
        self.lastBytesOut = bytesOut
        self.lastTime = Date()
    }
    
    func getSpeed() -> (uploadSpeed: Double, downloadSpeed: Double) {
        let (bytesIn, bytesOut) = getNetworkBytes()
        let now = Date()
        let timeDelta = now.timeIntervalSince(lastTime)
        
        guard timeDelta > 0.1 else {
            return (0.0, 0.0)
        }
        
        let deltaIn = bytesIn >= lastBytesIn ? (bytesIn - lastBytesIn) : 0
        let deltaOut = bytesOut >= lastBytesOut ? (bytesOut - lastBytesOut) : 0
        
        let downloadSpeed = Double(deltaIn) / timeDelta
        let uploadSpeed = Double(deltaOut) / timeDelta
        
        self.lastBytesIn = bytesIn
        self.lastBytesOut = bytesOut
        self.lastTime = now
        
        return (uploadSpeed, downloadSpeed)
    }
    
    private func getNetworkBytes() -> (bytesIn: UInt64, bytesOut: UInt64) {
        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0
        
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let firstAddr = ptr else {
            return (0, 0)
        }
        
        defer {
            freeifaddrs(ptr)
        }
        
        var tempAddr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while tempAddr != nil {
            if let addr = tempAddr?.pointee {
                if let sa = addr.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = addr.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self)
                        totalBytesIn += UInt64(networkData.pointee.ifi_ibytes)
                        totalBytesOut += UInt64(networkData.pointee.ifi_obytes)
                    }
                }
            }
            tempAddr = tempAddr?.pointee.ifa_next
        }
        
        return (totalBytesIn, totalBytesOut)
    }
}

func formatSpeedCompact(_ bytesPerSecond: Double) -> String {
    if bytesPerSecond < 1024 {
        return String(format: "%.0fB", bytesPerSecond)
    } else if bytesPerSecond < 1024 * 1024 {
        return String(format: "%.0fK", bytesPerSecond / 1024.0)
    } else {
        return String(format: "%.1fM", bytesPerSecond / (1024.0 * 1024.0))
    }
}

// MARK: - Custom High-Precision Status Bar View with Logo & Precision Alignment
class StatusBarCustomView: NSView {
    var attributedString: NSAttributedString? {
        didSet {
            needsDisplay = true
        }
    }
    
    // 缓存精致的程序 Logo 图像
    var logoImage: NSImage?
    
    // 允许点击穿透，让下方的 NSStatusBarButton 正常接收所有鼠标点击和高亮状态切换
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    // 每次父视图（即状态栏按钮）被请求重绘时，也强制我们重绘
    override func viewWillDraw() {
        super.viewWillDraw()
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 1. 在最左侧绘制程序精致渐变圆环 Logo (18x18)
        if let logo = logoImage {
            let logoSize: CGFloat = 18.0
            let logoY = (bounds.height - logoSize) / 2.0
            let logoRect = NSRect(x: 2.0, y: logoY, width: logoSize, height: logoSize)
            logo.draw(in: logoRect)
        }
        
        // 2. 绘制右侧双行监控文本，并按用户指示“向下靠下”靠底对齐微调
        guard let attrStr = attributedString else { return }
        let totalSize = attrStr.size()
        
        // 状态栏高度通常为 22pt，文字总高度约 16.8pt。
        // 原绝对垂直居中 y 是 (bounds.height - totalSize.height) / 2.0
        // 按照用户指示“向下靠下显示”，我们在此基础上在 y 轴向下挪动 1.5pt，使其完美贴合且具有阅读沉淀感
        let y = (bounds.height - totalSize.height) / 2.0 - 1.5
        
        // 文字的起始 x 坐标紧接在 Logo 区域右侧 (Logo 的 x 是 2，宽度 18，我们保留 4pt 优雅间距，因此设为 24)
        let x: CGFloat = 24.0
        
        let drawRect = NSRect(x: x, y: y, width: totalSize.width, height: totalSize.height)
        
        // 渲染文本
        attrStr.draw(in: drawRect)
    }
}
