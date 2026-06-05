import Foundation
import Darwin
import CryptoKit

public class MemoryPurger {
    
    /// Purge memory asynchronously on a background thread.
    /// - Parameters:
    ///   - progressHandler: Called on main thread with progress from 0.0 to 1.0.
    ///   - completion: Called on main thread with the reclaimed memory in Megabytes.
    /// Safely terminates non-essential high-memory system helper / daemon / updater processes owned by the user.
    private static func terminateSystemProcesses() {
        print("[MemoryPurger] Initiating deep process cleanup...")
        
        let safeToKillSystemProcesses: Set<String> = [
            "suggestd", "siriknowledged", "AssistantSiri", "Siri",
            "quicklookd", "QuickLookUIService", "cloudphotosd", "photoanalysisd",
            "photolibraryd", "reversetemplated", "newsd", "mapspushd",
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
            
            // 3. Perform balloon allocation to trigger VM compression/cleanup safely
            let totalPhysicalMemory = ProcessInfo.processInfo.physicalMemory
            let blockSize = 512 * 1024 * 1024 // 512 MB
            // Target 25% of total memory or maximum 4GB (8 blocks) to avoid locking up system
            let targetAllocation = totalPhysicalMemory / 4
            let numBlocks = Int(targetAllocation / UInt64(blockSize))
            let safeNumBlocks = max(2, min(numBlocks, 8)) // minimum 1GB, maximum 4GB
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
    
    public static func terminateProcess(pids: [Int32]) {
        print("[MemoryPurger] Request to terminate PIDs: \(pids)")
        let selfPid = getpid()
        for pid in pids {
            guard pid > 0 else {
                print("[MemoryPurger] Bypassing unsafe or invalid PID: \(pid)")
                continue
            }
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
    
    // ── 磁盘清理与重复文件识别 (v1.9.0) ──
    
    public struct TrashItem: Identifiable, Hashable {
        public var id = UUID()
        public let name: String
        public let path: String
        public let sizeBytes: Int64
        public let sizeString: String
        public let typeLabel: String // "应用缓存", "系统日志", "Xcode缓存", "卸载残留"
        
        public init(name: String, path: String, sizeBytes: Int64, sizeString: String, typeLabel: String) {
            self.name = name
            self.path = path
            self.sizeBytes = sizeBytes
            self.sizeString = sizeString
            self.typeLabel = typeLabel
        }
    }
    
    public struct DuplicateFileGroup: Identifiable, Hashable {
        public var id = UUID()
        public let size: Int64
        public let sizeString: String
        public let hash: String
        public var files: [URL]
        
        public init(size: Int64, sizeString: String, hash: String, files: [URL]) {
            self.size = size
            self.sizeString = sizeString
            self.hash = hash
            self.files = files
        }
    }
    
    private static func getDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                if let attr = try? fileManager.attributesOfItem(atPath: url.path),
                   let size = attr[.size] as? NSNumber {
                    return size.int64Value
                }
                return 0
            }
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    private static func formatBytesCompact(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private static func getFileMD5(url: URL, partial: Bool = false) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            
            var hasher = Insecure.MD5.init()
            
            if partial {
                let data = handle.readData(ofLength: 10 * 1024)
                hasher.update(data: data)
            } else {
                let chunkSize = 64 * 1024
                while true {
                    let data = handle.readData(ofLength: chunkSize)
                    if data.isEmpty { break }
                    hasher.update(data: data)
                }
            }
            
            let digest = hasher.finalize()
            return digest.map { String(format: "%02hhx", $0) }.joined()
        } catch {
            return nil
        }
    }
    
    public static func scanForDuplicateFiles(in folder: URL, progressHandler: @escaping (Double, String) -> Void) -> [DuplicateFileGroup] {
        print("[MemoryPurger] Scanning for duplicates in: \(folder.path)")
        
        let fileManager = FileManager.default
        var allFiles: [URL] = []
        
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return []
        }
        
        var totalScanned = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
               let isRegular = resourceValues.isRegularFile, isRegular,
               let size = resourceValues.fileSize, size > 0 {
                allFiles.append(fileURL)
                totalScanned += 1
                if totalScanned % 100 == 0 {
                    progressHandler(0.1, "已发现 \(totalScanned) 个文件...")
                }
            }
        }
        
        progressHandler(0.2, "已收集到 \(allFiles.count) 个文件，正在进行大小初筛...")
        
        var sizeMap: [Int64: [URL]] = [:]
        for file in allFiles {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                sizeMap[Int64(size), default: []].append(file)
            }
        }
        
        let candidateGroups = sizeMap.filter { $0.value.count >= 2 }
        let totalCandidates = candidateGroups.values.reduce(0, { $0 + $1.count })
        
        if totalCandidates == 0 {
            progressHandler(1.0, "扫描完成，未发现重复文件。")
            return []
        }
        
        progressHandler(0.4, "大小相同的文件共计 \(totalCandidates) 个，正在进行首部 10KB 校验...")
        
        var partialHashMap: [String: [URL]] = [:]
        var index = 0
        for (size, files) in candidateGroups {
            for file in files {
                index += 1
                let progress = 0.4 + (Double(index) / Double(totalCandidates)) * 0.3
                if index % 20 == 0 {
                    progressHandler(progress, "正在提取特征哈希 (\(index)/\(totalCandidates))...")
                }
                
                if let partialHash = getFileMD5(url: file, partial: true) {
                    let key = "\(size)_\(partialHash)"
                    partialHashMap[key, default: []].append(file)
                }
            }
        }
        
        let secondCandidates = partialHashMap.filter { $0.value.count >= 2 }
        let totalSecond = secondCandidates.values.reduce(0, { $0 + $1.count })
        
        if totalSecond == 0 {
            progressHandler(1.0, "扫描完成，未发现重复文件。")
            return []
        }
        
        progressHandler(0.7, "发现疑似重复组，正在进行全文件哈希精细校验...")
        
        var finalGroups: [DuplicateFileGroup] = []
        var finalIndex = 0
        
        for (key, files) in secondCandidates {
            let parts = key.components(separatedBy: "_")
            guard let size = Int64(parts[0]) else { continue }
            
            var fullHashMap: [String: [URL]] = [:]
            
            for file in files {
                finalIndex += 1
                let progress = 0.7 + (Double(finalIndex) / Double(totalSecond)) * 0.25
                if finalIndex % 10 == 0 {
                    progressHandler(progress, "深度核对中 (\(finalIndex)/\(totalSecond))...")
                }
                
                if let fullHash = getFileMD5(url: file, partial: false) {
                    fullHashMap[fullHash, default: []].append(file)
                }
            }
            
            for (hash, matchedFiles) in fullHashMap {
                if matchedFiles.count >= 2 {
                    let sizeStr = formatBytesCompact(size)
                    finalGroups.append(DuplicateFileGroup(size: size, sizeString: sizeStr, hash: hash, files: matchedFiles))
                }
            }
        }
        
        progressHandler(1.0, "重复文件扫描完成！共发现 \(finalGroups.count) 组重复文件。")
        return finalGroups
    }
    
    public static func scanAppLeftoversAndCaches(progressHandler: @escaping (Double, String) -> Void) -> [TrashItem] {
        var items: [TrashItem] = []
        let fileManager = FileManager.default
        
        let formatBytes: (Int64) -> String = { bytes in
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }
        
        // 1. Xcode DerivedData
        progressHandler(0.1, "正在扫描 Xcode DerivedData 缓存...")
        let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        let derivedDataURL = URL(fileURLWithPath: derivedDataPath)
        if fileManager.fileExists(atPath: derivedDataPath) {
            let size = getDirectorySize(url: derivedDataURL)
            if size > 0 {
                items.append(TrashItem(
                    name: "Xcode DerivedData 编译缓存",
                    path: derivedDataPath,
                    sizeBytes: size,
                    sizeString: formatBytes(size),
                    typeLabel: "Xcode缓存"
                ))
            }
        }
        
        // 2. System Logs
        progressHandler(0.3, "正在扫描系统日志缓存...")
        let logsPath = NSHomeDirectory() + "/Library/Logs"
        let logsURL = URL(fileURLWithPath: logsPath)
        if fileManager.fileExists(atPath: logsPath) {
            let size = getDirectorySize(url: logsURL)
            if size > 0 {
                items.append(TrashItem(
                    name: "用户系统日志文件",
                    path: logsPath,
                    sizeBytes: size,
                    sizeString: formatBytes(size),
                    typeLabel: "系统日志"
                ))
            }
        }
        
        // 3. User Caches
        progressHandler(0.5, "正在扫描应用缓存目录...")
        let cachesPath = NSHomeDirectory() + "/Library/Caches"
        let cachesURL = URL(fileURLWithPath: cachesPath)
        if fileManager.fileExists(atPath: cachesPath) {
            let size = getDirectorySize(url: cachesURL)
            if size > 0 {
                items.append(TrashItem(
                    name: "应用全局缓存数据 (Caches)",
                    path: cachesPath,
                    sizeBytes: size,
                    sizeString: formatBytes(size),
                    typeLabel: "应用缓存"
                ))
            }
        }
        
        // 4. App Leftovers (Application Support)
        progressHandler(0.7, "正在深度扫描卸载残留文件...")
        let (installedNames, installedBundles) = getInstalledAppsInfo()
        let appSupportPath = NSHomeDirectory() + "/Library/Application Support"
        let appSupportURL = URL(fileURLWithPath: appSupportPath)
        
        if let subdirs = try? fileManager.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) {
            let totalSub = subdirs.count
            for (idx, subdir) in subdirs.enumerated() {
                let pct = 0.7 + (Double(idx) / Double(totalSub)) * 0.25
                if idx % 5 == 0 {
                    progressHandler(pct, "分析卸载残留: \(subdir.lastPathComponent)...")
                }
                
                let name = subdir.lastPathComponent
                let lowerName = name.lowercased()
                
                let systemFolders: Set<String> = ["apple", "microsoft", "google", "adobe", "oracle", "mobile sync", "steam", "icloud", "quick look", "syncservices", "addressbook", "callhistorydb", "com.apple.tcc", "helperstatusbar", "antigravity"]
                if systemFolders.contains(lowerName) || lowerName.hasPrefix("apple") {
                    continue
                }
                
                var isResidual = false
                if lowerName.contains(".") {
                    if !installedBundles.contains(lowerName) {
                        let components = lowerName.components(separatedBy: ".")
                        if let lastComponent = components.last, !installedNames.contains(lastComponent) {
                            isResidual = true
                        }
                    }
                } else {
                    if !installedNames.contains(lowerName) {
                        isResidual = true
                    }
                }
                
                if isResidual {
                    let size = getDirectorySize(url: subdir)
                    if size >= 1024 * 1024 {
                        items.append(TrashItem(
                            name: "卸载残留: \(name)",
                            path: subdir.path,
                            sizeBytes: size,
                            sizeString: formatBytes(size),
                            typeLabel: "卸载残留"
                        ))
                    }
                }
            }
        }
        
        progressHandler(1.0, "磁盘深度垃圾扫描完成！")
        return items
    }
    
    private static func getInstalledAppsInfo() -> (names: Set<String>, bundles: Set<String>) {
        var names = Set<String>()
        var bundles = Set<String>()
        
        let fileManager = FileManager.default
        let appDirs = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        
        for dirPath in appDirs {
            let dirURL = URL(fileURLWithPath: dirPath)
            if let contents = try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) {
                for item in contents {
                    if item.pathExtension.lowercased() == "app" {
                        let name = item.deletingPathExtension().lastPathComponent
                        names.insert(name.lowercased())
                        
                        let plistURL = item.appendingPathComponent("Contents/Info.plist")
                        if fileManager.fileExists(atPath: plistURL.path),
                           let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
                           let bundleID = plist["CFBundleIdentifier"] as? String {
                            bundles.insert(bundleID.lowercased())
                        }
                    }
                }
            }
        }
        return (names, bundles)
    }
}
