import Foundation
import Darwin

public class MemoryPurger {
    
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
            
            // 2. Perform balloon allocation to trigger VM compression/cleanup
            // We allocate in 256MB blocks up to 1.5GB (6 blocks) or until memory limits are reached.
            let blockSize = 256 * 1024 * 1024 // 256 MB
            let numBlocks = 6
            var allocatedBlocks: [UnsafeMutableRawPointer] = []
            
            for i in 0..<numBlocks {
                let progress = Double(i) / Double(numBlocks) * 0.8
                DispatchQueue.main.async {
                    progressHandler(progress)
                }
                
                // Allocate block
                if let ptr = malloc(blockSize) {
                    // Touch each page (every 4096 bytes) to force physical allocation
                    let pageSize = 4096
                    for offset in stride(from: 0, to: blockSize, by: pageSize) {
                        let pagePtr = ptr.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                        pagePtr.pointee = 0
                    }
                    allocatedBlocks.append(ptr)
                    print("[MemoryPurger] Allocated block \(i + 1) of \(numBlocks) (total physical: \((i + 1) * 256) MB)")
                } else {
                    print("[MemoryPurger] Allocation failed on block \(i + 1) (oom/limits)")
                    break
                }
                
                // Allow VM system to process pages
                Thread.sleep(forTimeInterval: 0.15)
            }
            
            DispatchQueue.main.async {
                progressHandler(0.85)
            }
            
            // 3. Trigger /usr/sbin/purge to sweep all caches as fallback
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
                progressHandler(0.95)
            }
            
            // 4. Release all physical balloon blocks to give memory back to OS
            print("[MemoryPurger] Releasing allocated balloon blocks...")
            for ptr in allocatedBlocks {
                free(ptr)
            }
            allocatedBlocks.removeAll()
            
            // Short rest to let macOS stabilize stats
            Thread.sleep(forTimeInterval: 0.3)
            
            // 5. Calculate reclaimed memory
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
        public let name: String
        public let memoryMB: Double
        public let unit: String
        
        public init(id: UUID = UUID(), name: String, memoryMB: Double, unit: String) {
            self.id = id
            self.name = name
            self.memoryMB = memoryMB
            self.unit = unit
        }
    }
    
    /// Retrieve the currently active user application processes and their aggregated memory usage (RSS).
    public static func getActiveProcessMemoryList() -> [ProcessInfoItem] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ps -cax -o comm,rss"]
        
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
            if trimmed.isEmpty || trimmed == "COMM                RSS" || trimmed.hasPrefix("COMM") {
                continue
            }
            
            // The last component is RSS (in KB)
            guard let lastSpaceIndex = trimmed.range(of: " ", options: .backwards) else {
                continue
            }
            
            let namePart = trimmed[..<lastSpaceIndex.lowerBound].trimmingCharacters(in: .whitespaces)
            let rssPart = trimmed[lastSpaceIndex.upperBound...].trimmingCharacters(in: .whitespaces)
            
            guard let rssKB = Double(rssPart) else {
                continue
            }
            
            let name = namePart
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
            }
            
            processMemoryMap[normalizedName, default: 0.0] += rssKB
        }
        
        var result: [ProcessInfoItem] = []
        for (name, rssKB) in processMemoryMap {
            let memoryMB = rssKB / 1024.0
            if memoryMB >= 5.0 { // only show apps using >= 5MB
                let unit = memoryMB >= 1024.0 ? "GB" : "MB"
                let displayVal = memoryMB >= 1024.0 ? memoryMB / 1024.0 : memoryMB
                result.append(ProcessInfoItem(name: name, memoryMB: displayVal, unit: unit))
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
