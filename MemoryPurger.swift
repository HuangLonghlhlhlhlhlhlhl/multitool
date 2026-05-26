import Foundation
import Darwin

public class MemoryPurger {
    
    /// Purge memory asynchronously on a background thread.
    /// - Parameters:
    ///   - progressHandler: Called on main thread with progress from 0.0 to 1.0.
    ///   - completion: Called on main thread with the reclaimed memory in Megabytes.
    /// Safely terminates non-essential high-memory system helper / daemon / updater processes owned by the user.
    private static func terminateSystemProcesses() {
        print("[MemoryPurger] Initiating deep process cleanup...")
        
        let safeToKillSystemProcesses: Set<String> = [
            "mdworker", "mdworker_shared", "mds", "mds_stores", "mds_helper", "mdworker_shared_sentry",
            "com.apple.WebKit.WebContent", "com.apple.WebKit.Networking", "com.apple.WebKit.GPU",
            "suggestd", "siriknowledged", "AssistantSiri", "Siri",
            "quicklookd", "QuickLookUIService", "cloudphotosd", "photoanalysisd",
            "photolibraryd", "reversetemplated", "newsd", "mapspushd",
            "fmfd", "findmydeviced", "sharedfilelistd", "cloudd",
            "com.apple.appkit.xpc.openAndSavePanelService", "WiFiAgent",
            "UsageTrackingAgent", "UniversalReceiver", "sharingd", "rapportd",
            "homed", "remotepairingdeviced", "corespeechd", "spindump",
            "AppleIDAuthAgent", "BiomeAgent", "SafariCloudHistoryPushAgent",
            "SafariHistoryService", "com.apple.Safari.History",
            "GoogleSoftwareUpdateAgent", "Microsoft Update Assistant", "Adobe IPC Broker", "Creative Cloud Helper"
        ]
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ps -cax -o pid,comm,rss"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[MemoryPurger] Failed to run ps -cax for process cleanup: \(error)")
            return
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") { continue }
            
            let components = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard components.count >= 3 else { continue }
            
            let pidString = components[0]
            let rssString = components[components.count - 1]
            let name = components[1..<(components.count - 1)].joined(separator: " ")
            
            guard let pid = Int32(pidString), let rssKB = Double(rssString) else { continue }
            
            // Only target listed safe system processes with memory usage above 5MB
            let memoryMB = rssKB / 1024.0
            if safeToKillSystemProcesses.contains(name) && memoryMB >= 5.0 {
                // Ensure we don't kill our own app or its status bar helper
                if name.contains("HelperStatusBar") || name.contains("Antigravity") || pid == getpid() {
                    continue
                }
                
                print("[MemoryPurger] Deep Cleaning Process: \(name) (PID: \(pid), Memory: \(String(format: "%.1f", memoryMB)) MB)")
                kill(pid, SIGKILL)
            }
        }
        print("[MemoryPurger] Deep process cleanup finished.")
    }

    /// Purge memory asynchronously on a background thread.
    /// - Parameters:
    ///   - progressHandler: Called on main thread with progress from 0.0 to 1.0.
    ///   - completion: Called on main thread with the reclaimed memory in Megabytes.
    public static func purge(progressHandler: @escaping (Double) -> Void, completion: @escaping (Double) -> Void) {
        print("[MemoryPurger] Starting memory purge sequence...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Get initial free memory
            let beforeFree = getFreeMemoryBytes()
            print("[MemoryPurger] Free memory before purge: \(beforeFree / 1024 / 1024) MB")
            
            DispatchQueue.main.async {
                progressHandler(0.05)
            }
            
            // 2. Perform deep process cleanup
            terminateSystemProcesses()
            
            DispatchQueue.main.async {
                progressHandler(0.2)
            }
            
            // 3. Perform balloon allocation to trigger VM compression/cleanup
            let totalPhysicalMemory = ProcessInfo.processInfo.physicalMemory
            let blockSize = 512 * 1024 * 1024 // 512 MB
            let numBlocks = Int((totalPhysicalMemory / 2) / UInt64(blockSize))
            let safeNumBlocks = max(4, min(numBlocks, 32)) // minimum 2GB, maximum 16GB
            var allocatedBlocks: [UnsafeMutableRawPointer] = []
            
            print("[MemoryPurger] Total physical RAM: \(totalPhysicalMemory / 1024 / 1024) MB. Target balloon size: \(safeNumBlocks * 512) MB (\(safeNumBlocks) blocks)")
            
            for i in 0..<safeNumBlocks {
                let progress = 0.2 + (Double(i) / Double(safeNumBlocks)) * 0.6
                DispatchQueue.main.async {
                    progressHandler(progress)
                }
                
                if let ptr = malloc(blockSize) {
                    let pageSize = 4096
                    for offset in stride(from: 0, to: blockSize, by: pageSize) {
                        let pagePtr = ptr.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                        pagePtr.pointee = 0
                    }
                    allocatedBlocks.append(ptr)
                    print("[MemoryPurger] Allocated block \(i + 1) of \(safeNumBlocks) (total physical: \((i + 1) * 512) MB)")
                } else {
                    print("[MemoryPurger] Allocation failed on block \(i + 1) (oom/limits)")
                    break
                }
                
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            DispatchQueue.main.async {
                progressHandler(0.85)
            }
            
            // 4. Trigger /usr/sbin/purge to sweep all caches as fallback
            print("[MemoryPurger] Executing /usr/sbin/purge...")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
            do {
                try process.run()
                process.waitUntilExit()
                print("[MemoryPurger] /usr/sbin/purge completed successfully.")
            } catch {
                print("[MemoryPurger] /usr/sbin/purge call skipped/failed: \(error)")
            }
            
            DispatchQueue.main.async {
                progressHandler(0.92)
            }
            
            // 5. Release all physical balloon blocks to give memory back to OS
            print("[MemoryPurger] Releasing allocated balloon blocks...")
            for ptr in allocatedBlocks {
                free(ptr)
            }
            allocatedBlocks.removeAll()
            
            // Short rest to let macOS stabilize stats
            Thread.sleep(forTimeInterval: 0.3)
            
            DispatchQueue.main.async {
                progressHandler(0.98)
            }
            
            // 6. Calculate reclaimed memory
            let afterFree = getFreeMemoryBytes()
            print("[MemoryPurger] Free memory after purge: \(afterFree / 1024 / 1024) MB")
            
            let freedBytes = afterFree > beforeFree ? (afterFree - beforeFree) : 0
            let freedMB = Double(freedBytes) / (1024.0 * 1024.0)
            print("[MemoryPurger] Reclaimed \(freedMB) MB of memory successfully.")
            
            DispatchQueue.main.async {
                progressHandler(1.0)
                completion(freedMB)
            }
        }
    }
    
    /// Calculate current free + inactive memory bytes.
    private static func getFreeMemoryBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        
        let freePages = UInt64(stats.free_count)
        let inactivePages = UInt64(stats.inactive_count)
        
        return (freePages + inactivePages) * UInt64(pageSize)
    }
    
    public struct ProcessInfoItem: Identifiable, Hashable {
        public let id: UUID
        public let pids: [Int32]
        public let name: String
        public let memoryMB: Double
        public let unit: String
        public let cpuPercent: Double
        
        public init(id: UUID = UUID(), pids: [Int32], name: String, memoryMB: Double, unit: String, cpuPercent: Double) {
            self.id = id
            self.pids = pids
            self.name = name
            self.memoryMB = memoryMB
            self.unit = unit
            self.cpuPercent = cpuPercent
        }
    }
    
    /// Safely terminates the specified process PIDs.
    public static func terminateProcess(pids: [Int32]) {
        print("[MemoryPurger] Request to terminate PIDs: \(pids)")
        let selfPid = getpid()
        for pid in pids {
            if pid != selfPid {
                print("[MemoryPurger] Terminating PID \(pid)...")
                kill(pid, SIGKILL)
            }
        }
    }
    
    /// Retrieve the currently active user application processes and their aggregated memory usage (RSS) & CPU usage.
    public static func getActiveProcessMemoryList() -> [ProcessInfoItem] {
        // Secure subprocess execution: execute /bin/ps directly with arguments, avoiding shell injection risks
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-cax", "-o", "pid,comm,rss,%cpu"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[MemoryPurger] Failed to run ps command: \(error)")
            return []
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }
        
        let lines = output.components(separatedBy: .newlines)
        var processMemoryMap: [String: Double] = [:]
        var processCpuMap: [String: Double] = [:]
        var processPidsMap: [String: [Int32]] = [:]
        
        let blacklist: Set<String> = [
            "kernel_task", "launchd", "trustd", "syslogd", "logd", "kextd", "configd", "powerd", 
            "opendirectoryd", "UserEventAgent", "nsurlsessiond", "distnoted", "cfprefsd", "tccd", 
            "amfid", "secinitd", "syspolicyd", "runningboardd", "coreservicesd", "fseventsd", 
            "mds", "spindump", "diagnosticd", "pkd", "sharingd", "cloudd", "sandboxd", "sysmond", 
            "logind", "coreauthd", "identityservicesd", "lsd", "rapportd", "airportd", "biometrid", 
            "remotepairingdeviced", "secd", "accountsd", "containermanager", "BiomeAgent", 
            "AXVisualSupportA", "usernoted", "usernotification", "lockoutagent", "migrationhelper", 
            "sharedfilelistd", "imagent", "familycircled", "WiFiAgent", "UsageTrackingAge", 
            "CMFSyncAgent", "passd", "WindowServer", "hidd", "loginwindow", "bluetoothd", 
            "coreaudiod", "coremedia", "mediaremoted", "systemstats", "watchdogd", 
            "thermalmonitord", "contextstored", "xprotectd", "timed", "usbmuxd", "securityd", 
            "locationd", "autofsd", "dasd", "corerepaird", "syspolicyd", "swcd", "nfcd", 
            "nehelper", "networkd", "symptomsd", "rtcreportingd", "AppleIDAuthAgent", 
            "avconferenced", "backboardd", "commcenter", "findmydeviced", "mDNSResponder", 
            "securityd_service", "coreduetd", "com.apple.WebKit.WebContent", "com.apple.WebKit.Networking",
            "com.apple.WebKit.GPU", "storedownloadd", "storeassetd", "storelegacyd", "sysmond",
            "webbookmarksd", "mobileassetd", "softwareupdated", "signpost_notificationd",
            "analyticsd", "diagnosticextensionsd", "powerloggertryingd", "osanalyticshelper",
            "com.apple.appkit.xpc.openAndSavePanelService", "HelperStatusBar", "ps", "sh", "sort",
            "head", "grep"
        ]
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("PID") {
                continue
            }
            
            let components = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard components.count >= 4 else {
                continue
            }
            
            let pidString = components[0]
            let cpuString = components[components.count - 1]
            let rssString = components[components.count - 2]
            let name = components[1..<(components.count - 2)].joined(separator: " ")
            
            guard let pid = Int32(pidString), let rssKB = Double(rssString), let cpuPercent = Double(cpuString) else {
                continue
            }
            
            if blacklist.contains(name) {
                continue
            }
            
            // Skip lowercase processes ending with 'd' (system daemons)
            if name.count > 1 && name.last == "d" && name.allSatisfy({ !$0.isUppercase }) {
                continue
            }
            
            // Normalize app names (group helper processes)
            var normalizedName = name
            if name.contains("Google Chrome") || name.contains("Chrome") {
                normalizedName = "Google Chrome"
            } else if name.contains("WeChat") {
                normalizedName = "WeChat"
            } else if name.contains("Antigravity") {
                normalizedName = "Antigravity IDE"
            } else if name.contains("iTerm") {
                normalizedName = "iTerm2"
            } else if name.contains("VSCode") || name.contains("Visual Studio Code") || name.contains("Electron") {
                normalizedName = "VS Code"
            } else if name.contains("Xcode") {
                normalizedName = "Xcode"
            } else if name.contains("Safari") {
                normalizedName = "Safari"
            } else if name.contains("Finder") {
                normalizedName = "Finder"
            } else if name.contains("Lemon") {
                normalizedName = "Tencent Lemon"
            } else if name.contains("Trae") {
                normalizedName = "Trae"
            } else if name.contains("WorkBuddy") {
                normalizedName = "WorkBuddy"
            }
            
            processMemoryMap[normalizedName, default: 0.0] += rssKB
            processCpuMap[normalizedName, default: 0.0] += cpuPercent
            processPidsMap[normalizedName, default: []].append(pid)
        }
        
        var result: [ProcessInfoItem] = []
        for (name, rssKB) in processMemoryMap {
            let memoryMB = rssKB / 1024.0
            let cpuPercent = processCpuMap[name] ?? 0.0
            let pids = processPidsMap[name] ?? []
            
            if memoryMB >= 5.0 { // only show apps using >= 5MB
                let unit = memoryMB >= 1024.0 ? "GB" : "MB"
                let displayVal = memoryMB >= 1024.0 ? memoryMB / 1024.0 : memoryMB
                result.append(ProcessInfoItem(pids: pids, name: name, memoryMB: displayVal, unit: unit, cpuPercent: cpuPercent))
            }
        }
        
        // Sort descending by MB
        result.sort { a, b in
            let aVal = a.unit == "GB" ? a.memoryMB * 1024.0 : a.memoryMB
            let bVal = b.unit == "GB" ? b.memoryMB * 1024.0 : b.memoryMB
            return aVal > bVal
        }
        
        return Array(result.prefix(7))
    }
}
