import Foundation
import Combine
import IOKit

public struct SSDHealthData {
    public var smartctlInstalled = false
    public var modelName: String = "APPLE SSD"
    public var capacity: String = "512 GB"
    public var smartStatus: String = "Verified"
    public var healthPercent: Int = 100
    public var bytesWrittenTB: Double = 0.0
    public var bytesReadTB: Double = 0.0
    public var powerOnHours: Int = 0
    public var unsafeShutdowns: Int = 0
    public var mediaErrors: Int = 0
}

public class TelemetryManager: ObservableObject {
    public static let shared = TelemetryManager()
    
    @Published public var cpuUsage: Double = 0.0
    @Published public var ramUsage: Double = 0.0
    @Published public var ssdUsage: Double = 0.0
    @Published public var gpuUsage: Double = 0.0
    @Published public var upSpeed: Double = 0.0
    @Published public var downSpeed: Double = 0.0
    
    @Published public var cpuTemp: Float = 0.0
    @Published public var gpuTemp: Float = 0.0
    @Published public var ramTemp: Float = 0.0
    @Published public var ssdTemp: Float = 0.0
    
    @Published public var tempCpuPerf: Float = 0.0
    @Published public var tempCpuEff: Float = 0.0
    @Published public var tempSSD: Float = 0.0
    @Published public var tempWiFi: Float = 0.0
    @Published public var tempMemory: Float = 0.0
    @Published public var tempPalmRest: Float = 0.0
    @Published public var tempAirflow: Float = 0.0
    
    @Published public var cpuVoltage: Double = 0.9
    @Published public var gpuVoltage: Double = 0.85
    @Published public var cpuPower: Double = 1.5
    @Published public var gpuPower: Double = 0.5
    @Published public var npuPower: Double = 0.0
    @Published public var npuUsage: Double = 0.0
    @Published public var totalPower: Double = 2.5
    
    @Published public var cpuFreqPerf: Double = 1.5
    @Published public var cpuFreqEff: Double = 1.0
    @Published public var gpuFreq: Double = 0.3
    @Published public var ramFreq: Double = 6400.0
    
    @Published public var fanCount: Int = 0
    @Published public var fanSpeeds: [Float] = []
    @Published public var fanMinSpeeds: [Float] = []
    @Published public var fanMaxSpeeds: [Float] = []
    @Published public var targetFanSpeeds: [Float] = []
    
    @Published public var powerStats = PowerMonitor.PowerStats()
    @Published public var activeProcesses: [MemoryPurger.ProcessInfoItem] = []
    
    @Published public var diskReadSpeed: Double = 0.0
    @Published public var diskWriteSpeed: Double = 0.0
    @Published public var ssdHealth = SSDHealthData()
    @Published public var isWindowResizing = false
    
    // Configurable state settings
    public var isUIActive = false {
        didSet {
            updateInterval()
        }
    }
    public var isMiniWindowActive = false {
        didSet {
            updateInterval()
        }
    }
    public var currentTab = 0 {
        didSet {
            // Trigger rapid update if switching to tab 2 or 0 to populate lists instantly
            if currentTab == 2 {
                lastSSDHealthTime = Date.distantPast
            } else if currentTab == 0 {
                lastProcessScanTime = Date.distantPast
            }
        }
    }
    
    // System Sleep / Lock states
    public var isScreenAsleep = false {
        didSet {
            updateInterval()
        }
    }
    public var isSessionLocked = false {
        didSet {
            updateInterval()
        }
    }
    
    private var timer: Timer?
    private let telemetryQueue = DispatchQueue(label: "com.statusctrl.telemetryQueue", qos: .utility)
    
    private let cpuMonitor = CPUMonitor()
    private let networkMonitor = NetworkMonitor()
    private let smc = SMCController.shared
    
    // Caches and timestamps for sparse polling
    private var lastSSDHealthTime: Date = Date.distantPast
    private var lastSSDUsageTime: Date = Date.distantPast
    private var cachedSSDUsage: Double = 0.0
    private var lastProcessScanTime: Date = Date.distantPast
    
    // Disk I/O static values
    private static var lastReadBytes: UInt64 = 0
    private static var lastWriteBytes: UInt64 = 0
    private static var lastIOTime: Date? = nil
    
    private init() {
        // Setup initial timer
        updateInterval()
        
        // Fetch static hardware configuration in background to avoid blocking main thread at startup
        telemetryQueue.async { [weak self] in
            self?.initializeStaticHardwareConfig()
        }
    }
    
    private func initializeStaticHardwareConfig() {
        smc.doOpen()
        let count = smc.getFanCount()
        var mins: [Float] = []
        var maxs: [Float] = []
        var targets: [Float] = []
        for i in 0..<count {
            mins.append(smc.getFanMinSpeed(i))
            maxs.append(smc.getFanMaxSpeed(i))
            targets.append(smc.getFanTargetSpeed(i))
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.fanCount = count
            self.fanMinSpeeds = mins
            self.fanMaxSpeeds = maxs
            self.targetFanSpeeds = targets
        }
    }
    
    public func updateInterval() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.updateInterval()
            }
            return
        }
        
        timer?.invalidate()
        timer = nil
        
        guard !isScreenAsleep && !isSessionLocked else {
            print("[TelemetryManager] Screen asleep or locked. Telemetry paused completely.")
            return
        }
        
        let enableBar = UserDefaults.standard.object(forKey: "enableStatusBar") as? Bool ?? true
        
        guard enableBar || isUIActive || isMiniWindowActive else {
            print("[TelemetryManager] Status bar disabled and UI inactive. Telemetry paused completely.")
            return
        }
        
        let onBattery = !PowerMonitor.getPowerStats().isConnected
        var interval: TimeInterval = 2.0
        
        if isUIActive {
            interval = onBattery ? 3.0 : 1.5
        } else if isMiniWindowActive {
            interval = onBattery ? 4.0 : 2.0
        } else {
            interval = onBattery ? 6.0 : 3.0
        }
        
        print("[TelemetryManager] Scheduling telemetry timer with interval: \(interval)s (UI Active: \(isUIActive), Mini Active: \(isMiniWindowActive), On Battery: \(onBattery))")
        
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollHardware()
        }
        timer = t
        RunLoop.current.add(t, forMode: .common)
        
        if !isPolling {
            isPolling = true
            telemetryQueue.async { [weak self] in
                self?.pollHardwareSync()
                DispatchQueue.main.async {
                    self?.isPolling = false
                }
            }
        }
    }
    
    private var isPolling = false
    private func pollHardware() {
        guard !isPolling && !isWindowResizing else { return }
        isPolling = true
        
        telemetryQueue.async { [weak self] in
            self?.pollHardwareSync()
            DispatchQueue.main.async {
                self?.isPolling = false
            }
        }
    }
    
    private func pollHardwareSync() {
        // 1. Fetch preferences
        let showCPU = UserDefaults.standard.object(forKey: "showStatusBarCPUUsage") as? Bool ?? true
        let showRAM = UserDefaults.standard.object(forKey: "showStatusBarRAMUsage") as? Bool ?? true
        let showSSD = UserDefaults.standard.object(forKey: "showStatusBarSSDUsage") as? Bool ?? true
        let showCPUTemp = UserDefaults.standard.object(forKey: "showStatusBarCPUTemp") as? Bool ?? true
        let showFan = UserDefaults.standard.object(forKey: "showStatusBarFanSpeed") as? Bool ?? true
        let showNet = UserDefaults.standard.object(forKey: "showStatusBarNetSpeed") as? Bool ?? true
        let showGPU = UserDefaults.standard.object(forKey: "showStatusBarGPUUsage") as? Bool ?? true
        let enableAutoPurge = UserDefaults.standard.bool(forKey: "enableAutoIdlePurge")
        
        let needCPU = isUIActive || isMiniWindowActive || showCPU || showCPUTemp
        let needRAM = isUIActive || isMiniWindowActive || showRAM || enableAutoPurge
        let needSSD = isUIActive || showSSD
        let needGPU = isUIActive || showGPU
        let needNet = isUIActive || isMiniWindowActive || showNet
        let needFan = isUIActive || isMiniWindowActive || showFan
        
        // 2. Perform CPU, GPU, RAM, Net speed polling
        let cpuVal = needCPU ? cpuMonitor.getUsage() : 0.0
        let ramVal = needRAM ? getRAMUsageInternal() : 0.0
        let gpuVal = needGPU ? getGPUUsageInternal() : 0.0
        
        var netUp = 0.0
        var netDown = 0.0
        if needNet {
            let speed = networkMonitor.getSpeed()
            netUp = speed.uploadSpeed
            netDown = speed.downloadSpeed
        }
        
        // Sparse Polling for SSD Usage (every 30 seconds to reduce volume query overhead)
        var ssdVal = cachedSSDUsage
        if needSSD {
            let now = Date()
            if now.timeIntervalSince(lastSSDUsageTime) >= 30.0 || lastSSDUsageTime == Date.distantPast {
                ssdVal = getSSDUsageInternal()
                cachedSSDUsage = ssdVal
                lastSSDUsageTime = now
            }
        }
        
        // SMC basic queries
        let tempCpuVal = needCPU ? smc.getCPUTemperature() : 0.0
        let tempGpuVal = needGPU ? smc.getGPUTemperature() : 0.0
        let tempMemoryVal = needRAM ? smc.getMemoryTemperature() : 0.0
        let tempSSDVal = needSSD ? smc.getSSDTemperature() : 0.0
        
        // Fan queries
        let tempFanCount = smc.getFanCount()
        var actualFanSpeeds = [Float]()
        var actualTargetSpeeds = [Float]()
        if needFan && tempFanCount > 0 {
            for i in 0..<tempFanCount {
                actualFanSpeeds.append(smc.getFanSpeed(i))
                actualTargetSpeeds.append(smc.getFanTargetSpeed(i))
            }
        }
        
        let statsPower = PowerMonitor.getPowerStats()
        
        // 3. UI-only telemetry (detailed sensors & stats)
        var tempCpuPerfVal: Float = 0.0
        var tempCpuEffVal: Float = 0.0
        var tempWiFiVal: Float = 0.0
        var tempPalmRestVal: Float = 0.0
        var tempAirflowVal: Float = 0.0
        
        var voltCpuVal: Double = 0.9
        var voltGpuVal: Double = 0.85
        var powCpuVal: Double = 1.5
        var powGpuVal: Double = 0.5
        var powNpuVal: Double = 0.0
        var usageNpuVal: Double = 0.0
        var totalPowerVal: Double = 2.5
        
        var freqCpuPerfVal: Double = 1.5
        var freqCpuEffVal: Double = 1.0
        var freqGpuVal: Double = 0.3
        var ramFreqVal: Double = 6400.0
        
        var diskReadSpeedVal: Double = 0.0
        var diskWriteSpeedVal: Double = 0.0
        var ssdHealthVal = self.ssdHealth
        
        var processList: [MemoryPurger.ProcessInfoItem] = self.activeProcesses
        
        if isUIActive {
            // Detailed Temperatures (Tab 1 only, when detailed accordion or silicon die is open)
            // If they are collapsed, we skip them completely!
            let detailedTempsEnabled = UserDefaults.standard.bool(forKey: "isTempAccordionExpanded") || UserDefaults.standard.bool(forKey: "showSiliconDieView")
            if currentTab == 1 && detailedTempsEnabled {
                tempCpuPerfVal = smc.getCPUPerfCoresTemperature()
                tempCpuEffVal = smc.getCPUEffCoresTemperature()
                tempWiFiVal = smc.getWiFiTemperature()
                tempPalmRestVal = smc.getPalmRestTemperature()
                tempAirflowVal = smc.getAirflowTemperature()
            }
            
            // Detailed Power/Voltage (Tab 1 only)
            let detailedPowerEnabled = UserDefaults.standard.bool(forKey: "isPowerAccordionExpanded")
            if currentTab == 1 {
                powCpuVal = smc.getCPUPower(load: cpuVal)
                powGpuVal = smc.getGPUPower(load: gpuVal)
                
                if detailedPowerEnabled {
                    voltCpuVal = smc.getCPUVoltage(load: cpuVal)
                    voltGpuVal = smc.getGPUVoltage(load: gpuVal)
                    powNpuVal = smc.getNPUPower(load: cpuVal)
                    usageNpuVal = min(100.0, (powNpuVal / 15.0) * 100.0)
                }
                
                // Total Power
                totalPowerVal = powCpuVal + powGpuVal + 2.5
                if !statsPower.isConnected {
                    let discharge = abs(statsPower.batteryPower)
                    if discharge > 0.1 {
                        totalPowerVal = discharge
                    }
                }
                
                // Frequencies
                let (perfBase, effBase) = getCpuBaseFrequencies()
                
                let cpuLimit = UserDefaults.standard.double(forKey: "CpuFreqLimit")
                let scale = cpuLimit > 0 ? (cpuLimit / 100.0) : 1.0
                
                freqCpuPerfVal = (perfBase + (cpuVal / 100.0) * (perfBase * 0.5)) * scale
                freqCpuEffVal = (effBase + (cpuVal / 100.0) * (effBase * 0.5)) * scale
                freqGpuVal = (0.3 + (gpuVal / 100.0) * 1.0) * scale
                
                // RAM Frequency based on profile
                let ramProfile = UserDefaults.standard.integer(forKey: "RamFreqProfile")
                switch ramProfile {
                case 1: ramFreqVal = 6400.0
                case 2: ramFreqVal = 5500.0
                case 3: ramFreqVal = 4266.0
                case 4: ramFreqVal = 3200.0
                default:
                    // Auto: dynamic frequency based on CPU load to simulate hardware scaling
                    let base = 3200.0
                    let loadFactor = min(1.0, max(0.0, cpuVal / 80.0))
                    ramFreqVal = base + loadFactor * 3200.0
                }
            }
            
            // System Health / Disk I/O & SSD SMART stats (Tab 2 only)
            if currentTab == 2 {
                // Disk I/O speed
                let ioBytes = getSystemDiskIOBytesInternal()
                let now = Date()
                if let lastTime = Self.lastIOTime {
                    let dt = now.timeIntervalSince(lastTime)
                    if dt > 0.1 {
                        let rDiff = ioBytes.read >= Self.lastReadBytes ? ioBytes.read - Self.lastReadBytes : 0
                        let wDiff = ioBytes.write >= Self.lastWriteBytes ? ioBytes.write - Self.lastWriteBytes : 0
                        diskReadSpeedVal = (Double(rDiff) / (1024.0 * 1024.0)) / dt
                        diskWriteSpeedVal = (Double(wDiff) / (1024.0 * 1024.0)) / dt
                    }
                }
                if diskReadSpeedVal > 15000.0 { diskReadSpeedVal = 0.0 }
                if diskWriteSpeedVal > 15000.0 { diskWriteSpeedVal = 0.0 }
                Self.lastReadBytes = ioBytes.read
                Self.lastWriteBytes = ioBytes.write
                Self.lastIOTime = now
                
                // Sparse Polling for SMART Health data (every 60 seconds to completely avoid diskutil process shell overhead)
                if now.timeIntervalSince(lastSSDHealthTime) >= 60.0 || lastSSDHealthTime == Date.distantPast {
                    ssdHealthVal = fetchSSDHealthDataInternal()
                    lastSSDHealthTime = now
                }
            }
            
            // Process Memory Ranking (Tab 0 only, throttled to run every 3 seconds to reduce Darwin PID enumeration overhead)
            if currentTab == 0 {
                let now = Date()
                if now.timeIntervalSince(lastProcessScanTime) >= 3.0 || lastProcessScanTime == Date.distantPast {
                    processList = MemoryPurger.getActiveProcessMemoryList()
                    lastProcessScanTime = now
                }
            }
        }
        
        // 4. Update published states on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.cpuUsage = cpuVal
            self.ramUsage = ramVal
            self.ssdUsage = ssdVal
            self.gpuUsage = gpuVal
            self.upSpeed = netUp
            self.downSpeed = netDown
            
            self.cpuTemp = tempCpuVal
            self.gpuTemp = tempGpuVal
            self.ramTemp = tempMemoryVal
            self.ssdTemp = tempSSDVal
            
            self.tempCpuPerf = tempCpuPerfVal
            self.tempCpuEff = tempCpuEffVal
            self.tempSSD = tempSSDVal
            self.tempWiFi = tempWiFiVal
            self.tempMemory = tempMemoryVal
            self.tempPalmRest = tempPalmRestVal
            self.tempAirflow = tempAirflowVal
            
            self.cpuVoltage = voltCpuVal
            self.gpuVoltage = voltGpuVal
            self.cpuPower = powCpuVal
            self.gpuPower = powGpuVal
            self.npuPower = powNpuVal
            self.npuUsage = usageNpuVal
            self.totalPower = totalPowerVal
            
            self.cpuFreqPerf = freqCpuPerfVal
            self.cpuFreqEff = freqCpuEffVal
            self.gpuFreq = freqGpuVal
            self.ramFreq = ramFreqVal
            
            self.fanCount = tempFanCount
            self.fanSpeeds = actualFanSpeeds
            if needFan && !actualTargetSpeeds.isEmpty {
                self.targetFanSpeeds = actualTargetSpeeds
            }
            
            self.powerStats = statsPower
            self.activeProcesses = processList
            self.diskReadSpeed = diskReadSpeedVal
            self.diskWriteSpeed = diskWriteSpeedVal
            self.ssdHealth = ssdHealthVal
            
            // Broadcast telemetry update event
            NotificationCenter.default.post(name: NSNotification.Name("com.statusctrl.telemetryUpdated"), object: nil)
        }
    }
    
    // Internal helper methods for hardware stats
    private func getRAMUsageInternal() -> Double {
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
    
    private func getSSDUsageInternal() -> Double {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let totalInt = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage, totalInt > 0 {
                let total = Int64(totalInt)
                let used = total - available
                return (Double(used) / Double(total)) * 100.0
            }
        } catch {
            print("[TelemetryManager] Error getting SSD usage at NSHomeDirectory: \(error)")
            // Fallback to root directory standard key
            let rootURL = URL(fileURLWithPath: "/")
            do {
                let values = try rootURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                if let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity, total > 0 {
                    let used = total - available
                    return (Double(used) / Double(total)) * 100.0
                }
            } catch {
                print("[TelemetryManager] Error getting SSD usage fallback: \(error)")
            }
        }
        return 0.0
    }
    
    private func getGPUUsageInternal() -> Double {
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
    
    private func getSystemDiskIOBytesInternal() -> (read: UInt64, write: UInt64) {
        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        
        let matchingDict = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if result == KERN_SUCCESS {
            var drive = IOIteratorNext(iterator)
            while drive != 0 {
                var properties: Unmanaged<CFMutableDictionary>?
                let propResult = IORegistryEntryCreateCFProperties(drive, &properties, kCFAllocatorDefault, 0)
                if propResult == KERN_SUCCESS, let props = properties?.takeRetainedValue() as? [String: Any] {
                    if let statistics = props["Statistics"] as? [String: Any] {
                        let bytesRead = statistics["Bytes (Read)"] as? UInt64 ?? (statistics["Bytes (Read)"] as? Int64).map { UInt64($0) } ?? 0
                        let bytesWritten = statistics["Bytes (Write)"] as? UInt64 ?? (statistics["Bytes (Write)"] as? Int64).map { UInt64($0) } ?? 0
                        totalRead += bytesRead
                        totalWrite += bytesWritten
                    }
                }
                IOObjectRelease(drive)
                drive = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return (totalRead, totalWrite)
    }
    
    private func getCpuBaseFrequencies() -> (perf: Double, eff: Double) {
        var baseCpuPerf = 1.5
        var baseCpuEff = 1.0
        
        var hz0: UInt64 = 0
        var sz0 = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.perflevel0.nominalfrequency", &hz0, &sz0, nil, 0) == 0 && hz0 > 0 {
            baseCpuPerf = Double(hz0) / 1_000_000_000.0
        } else {
            var hzBase: UInt64 = 0
            var szBase = MemoryLayout<UInt64>.size
            if sysctlbyname("hw.cpufrequency", &hzBase, &szBase, nil, 0) == 0 && hzBase > 0 {
                baseCpuPerf = Double(hzBase) / 1_000_000_000.0
            }
        }
        
        var hz1: UInt64 = 0
        var sz1 = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.perflevel1.nominalfrequency", &hz1, &sz1, nil, 0) == 0 && hz1 > 0 {
            baseCpuEff = Double(hz1) / 1_000_000_000.0
        } else {
            baseCpuEff = max(1.0, baseCpuPerf * 0.6)
        }
        
        return (baseCpuPerf, baseCpuEff)
    }
    
    private func fetchSSDHealthDataInternal() -> SSDHealthData {
        var data = SSDHealthData()
        let paths = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/usr/bin/smartctl"]
        var installed = false
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                installed = true
                break
            }
        }
        data.smartctlInstalled = installed
        
        let diskutilTask = Process()
        diskutilTask.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        diskutilTask.arguments = ["info", "-plist", "disk0"]
        let diskutilPipe = Pipe()
        diskutilTask.standardOutput = diskutilPipe
        diskutilTask.standardError = diskutilPipe
        
        do {
            try diskutilTask.run()
            diskutilTask.waitUntilExit()
            let rawData = diskutilPipe.fileHandleForReading.readDataToEndOfFile()
            if let plist = try? PropertyListSerialization.propertyList(from: rawData, options: [], format: nil) as? [String: Any] {
                data.modelName = plist["MediaName"] as? String ?? (plist["DeviceMediaType"] as? String ?? "APPLE SSD")
                data.smartStatus = plist["SMARTStatus"] as? String ?? "Verified"
                if let sizeBytes = plist["Size"] as? Int64 {
                    let gb = Double(sizeBytes) / 1_000_000_000.0
                    data.capacity = String(format: "%.0f GB", gb)
                }
            }
        } catch {}
        
        if installed {
            let smartTask = Process()
            smartTask.executableURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.hl.smchelper")
            smartTask.arguments = ["smart"]
            let smartPipe = Pipe()
            smartTask.standardOutput = smartPipe
            smartTask.standardError = smartPipe
            
            do {
                try smartTask.run()
                smartTask.waitUntilExit()
                let rawData = smartPipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any] {
                    if let device = json["device"] as? [String: Any], let model = device["model_name"] as? String {
                        data.modelName = model
                    }
                    if let capacity = json["user_capacity"] as? [String: Any], let sizeBytes = capacity["bytes"] as? Int64 {
                        let gb = Double(sizeBytes) / 1_000_000_000.0
                        data.capacity = String(format: "%.0f GB", gb)
                    }
                    if let smartStatus = json["smart_status"] as? [String: Any], let passed = smartStatus["passed"] as? Bool {
                        data.smartStatus = passed ? "Passed" : "Failed"
                    }
                    if let log = json["nvme_smart_health_information_log"] as? [String: Any] {
                        if let percentNum = log["percentage_used"] as? NSNumber {
                            data.healthPercent = 100 - percentNum.intValue
                        }
                        if let writtenNum = log["data_units_written"] as? NSNumber {
                            data.bytesWrittenTB = (writtenNum.doubleValue * 512000.0) / 1_000_000_000_000.0
                        }
                        if let readNum = log["data_units_read"] as? NSNumber {
                            data.bytesReadTB = (readNum.doubleValue * 512000.0) / 1_000_000_000_000.0
                        }
                        if let hoursNum = log["power_on_hours"] as? NSNumber {
                            data.powerOnHours = hoursNum.intValue
                        }
                        if let unsafeNum = log["unsafe_shutdowns"] as? NSNumber {
                            data.unsafeShutdowns = unsafeNum.intValue
                        }
                        if let errorsNum = log["media_errors"] as? NSNumber {
                            data.mediaErrors = errorsNum.intValue
                        }
                    }
                }
            } catch {}
        } else {
            let stats = SSDMonitor.shared.getSSDStats()
            data.modelName = stats.modelName
            data.healthPercent = stats.healthPercent
            data.bytesWrittenTB = Double(stats.bytesWritten) / 1_000_000_000_000.0
            data.bytesReadTB = Double(stats.bytesRead) / 1_000_000_000_000.0
            data.smartStatus = stats.healthPercent > 10 ? "Passed" : "Failing"
        }
        
        return data
    }
}
