import Foundation
import Darwin
import CryptoKit

public class MemoryPurger {
    
    /// Purge memory asynchronously on a background thread.
    /// - Parameters:
    ///   - progressHandler: Called on main thread with progress from 0.0 to 1.0.
    ///   - completion: Called on main thread with the reclaimed memory in Megabytes.
    /// Safely terminates non-essential high-memory system helper / daemon / updater processes owned by the user.
    private static func getProcessName(pid: Int32, bsdName: String) -> String {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &pathBuffer, 4096)
        if length > 0 {
            let path = String(cString: pathBuffer)
            let lastComponent = URL(fileURLWithPath: path).lastPathComponent
            if !lastComponent.isEmpty {
                return lastComponent
            }
        }
        return bsdName
    }

    /// Purge memory asynchronously on a background thread.
    /// - Parameters:
    ///   - progressHandler: Called on main thread with progress from 0.0 to 1.0.
    ///   - completion: Called on main thread with the reclaimed memory in Megabytes.
    /// Safely terminates non-essential high-memory system helper / daemon / updater processes owned by the user.
    private static func terminateSystemProcesses() {
        print("[MemoryPurger] Initiating deep process cleanup using native Darwin APIs...")
        
        let safeToKillSystemProcesses: Set<String> = [
            "suggestd", "siriknowledged", "AssistantSiri", "Siri",
            "quicklookd", "QuickLookUIService", "cloudphotosd", "photoanalysisd",
            "photolibraryd", "reversetemplated", "newsd", "mapspushd",
            "GoogleSoftwareUpdateAgent", "Microsoft Update Assistant", "Adobe IPC Broker", "Creative Cloud Helper"
        ]
        
        let numPids = proc_listallpids(nil, 0)
        guard numPids > 0 else { return }
        
        var pids = [Int32](repeating: 0, count: Int(numPids) + 10)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return }
        
        let selfPid = getpid()
        
        for i in 0..<Int(count) {
            let pid = pids[i]
            guard pid > 0 && pid != selfPid else { continue }
            
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            let bytesRead = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size)
            guard bytesRead == size else { continue }
            
            let bsdName = withUnsafePointer(to: &info.pbsd.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 16) { src in
                    var buffer = [CChar](repeating: 0, count: 17)
                    for idx in 0..<16 {
                        buffer[idx] = src[idx]
                    }
                    return String(cString: buffer)
                }
            }
            
            let name = getProcessName(pid: pid, bsdName: bsdName)
            let rssKB = Double(info.ptinfo.pti_resident_size) / 1024.0
            let memoryMB = rssKB / 1024.0
            
            if safeToKillSystemProcesses.contains(name) && memoryMB >= 5.0 {
                // Ensure we don't kill our own app or its status bar helper
                if name.contains("HelperStatusBar") || name.contains("Antigravity") {
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
                // Check if remaining free memory is too low (< 500 MB)
                let freeBytes = getFreeMemoryBytes()
                if freeBytes < 500 * 1024 * 1024 {
                    print("[MemoryPurger] Free memory is critically low (\(freeBytes / 1024 / 1024) MB < 500 MB). Stopping balloon expansion to prevent system freeze.")
                    break
                }
                
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
    
    // Cache dictionary for computing process CPU usage differentials
    private static var lastProcessCPUTimes: [Int32: (date: Date, cpuTimeNs: UInt64)] = [:]
    private static var pidNameCache: [String: String] = [:] // Key: "\(pid)_\(bsdName)"
    
    /// Retrieve the currently active user application processes and their aggregated memory usage (RSS) & CPU usage.
    public static func getActiveProcessMemoryList() -> [ProcessInfoItem] {
        let numPids = proc_listallpids(nil, 0)
        guard numPids > 0 else { return [] }
        
        var pids = [Int32](repeating: 0, count: Int(numPids) + 10)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count > 0 else { return [] }
        
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
        
        let now = Date()
        var newProcessCPUTimes: [Int32: (date: Date, cpuTimeNs: UInt64)] = [:]
        
        let limit = min(Int(count), pids.count)
        for i in 0..<limit {
            let pid = pids[i]
            guard pid > 0 else { continue }
            
            var info = proc_taskallinfo()
            let size = Int32(MemoryLayout<proc_taskallinfo>.size)
            let bytesRead = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, size)
            guard bytesRead == size else { continue }
            
            // 1. Get BSD Name for fast filter (no syscall overhead)
            let bsdName = withUnsafePointer(to: &info.pbsd.pbi_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 16) { src in
                    var buffer = [CChar](repeating: 0, count: 17)
                    for idx in 0..<16 {
                        buffer[idx] = src[idx]
                    }
                    return String(cString: buffer)
                }
            }
            
            if blacklist.contains(bsdName) {
                continue
            }
            
            if bsdName.count > 1 && bsdName.last == "d" && bsdName.allSatisfy({ !$0.isUppercase }) {
                continue
            }
            
            // 2. Fetch name using cache to bypass proc_pidpath calls
            let cacheKey = "\(pid)_\(bsdName)"
            var name: String
            if let cached = pidNameCache[cacheKey] {
                name = cached
            } else {
                name = getProcessName(pid: pid, bsdName: bsdName)
                if blacklist.contains(name) || (name.count > 1 && name.last == "d" && name.allSatisfy({ !$0.isUppercase })) {
                    continue
                }
                pidNameCache[cacheKey] = name
            }
            
            let rssKB = Double(info.ptinfo.pti_resident_size) / 1024.0
            
            // Calculate real-time CPU percentage differential
            let totalCpuTimeNs = info.ptinfo.pti_total_user + info.ptinfo.pti_total_system
            var cpuPercent = 0.0
            if let last = lastProcessCPUTimes[pid] {
                let dt = now.timeIntervalSince(last.date)
                if dt > 0.1 {
                    let cpuDiffNs = totalCpuTimeNs >= last.cpuTimeNs ? totalCpuTimeNs - last.cpuTimeNs : 0
                    cpuPercent = (Double(cpuDiffNs) / 1_000_000_000.0) / dt * 100.0
                }
            }
            newProcessCPUTimes[pid] = (now, totalCpuTimeNs)
            
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
        
        // Save current PIDs' CPU times for next tick
        lastProcessCPUTimes = newProcessCPUTimes
        
        // Clean up dead processes from the PID cache to prevent memory growth
        let activePidsSet = Set(pids.prefix(Int(count)))
        pidNameCache = pidNameCache.filter { key, _ in
            if let firstPart = key.split(separator: "_").first,
               let pid = Int32(firstPart) {
                return activePidsSet.contains(pid)
            }
            return false
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
                var hasMore = true
                while hasMore {
                    autoreleasepool {
                        let data = handle.readData(ofLength: chunkSize)
                        if data.isEmpty {
                            hasMore = false
                        } else {
                            hasher.update(data: data)
                        }
                    }
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
        
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsHiddenFiles]) else {
            return []
        }
        
        var totalScanned = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)) {
                if let isSymlink = resourceValues.isSymbolicLink, isSymlink {
                    enumerator.skipDescendants()
                    continue
                }
                if let isRegular = resourceValues.isRegularFile, isRegular,
                   let size = resourceValues.fileSize, size > 0 {
                    allFiles.append(fileURL)
                    totalScanned += 1
                    if totalScanned % 100 == 0 {
                        progressHandler(0.1, "已发现 \(totalScanned) 个文件...")
                    }
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
        let candidateFilesList = candidateGroups.values.flatMap { $0 }
        let totalCandidates = candidateFilesList.count
        
        if totalCandidates == 0 {
            progressHandler(1.0, "扫描完成，未发现重复文件。")
            return []
        }
        
        progressHandler(0.4, "大小相同的文件共计 \(totalCandidates) 个，正在并发特征校验...")
        
        let groupLock = NSLock()
        var partialHashMap: [String: [URL]] = [:]
        
        var completedCount = 0
        let counterLock = NSLock()
        
        DispatchQueue.concurrentPerform(iterations: totalCandidates) { idx in
            let file = candidateFilesList[idx]
            guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ Int64($0) }) else { return }
            
            if let partialHash = getFileMD5(url: file, partial: true) {
                let key = "\(size)_\(partialHash)"
                groupLock.lock()
                partialHashMap[key, default: []].append(file)
                groupLock.unlock()
            }
            
            counterLock.lock()
            completedCount += 1
            let currentCompleted = completedCount
            counterLock.unlock()
            
            if currentCompleted % 20 == 0 || currentCompleted == totalCandidates {
                let pct = 0.4 + (Double(currentCompleted) / Double(totalCandidates)) * 0.3
                DispatchQueue.main.async {
                    progressHandler(pct, "正在提取特征哈希 (\(currentCompleted)/\(totalCandidates))...")
                }
            }
        }
        
        let secondCandidates = partialHashMap.filter { $0.value.count >= 2 }
        let secondCandidatesList = Array(secondCandidates.values)
        let totalSecondGroups = secondCandidatesList.count
        let totalSecondFilesCount = secondCandidatesList.reduce(0, { $0 + $1.count })
        
        if totalSecondGroups == 0 {
            progressHandler(1.0, "扫描完成，未发现重复文件。")
            return []
        }
        
        progressHandler(0.7, "发现疑似重复组，正在并发全文件哈希精细校验...")
        
        var finalGroups: [DuplicateFileGroup] = []
        let secondLock = NSLock()
        
        var finalCompletedCount = 0
        let finalCounterLock = NSLock()
        
        DispatchQueue.concurrentPerform(iterations: totalSecondGroups) { groupIdx in
            let files = secondCandidatesList[groupIdx]
            guard let size = (try? files[0].resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ Int64($0) }) else { return }
            
            var fullHashMap: [String: [URL]] = [:]
            for file in files {
                if let fullHash = getFileMD5(url: file, partial: false) {
                    fullHashMap[fullHash, default: []].append(file)
                }
                
                finalCounterLock.lock()
                finalCompletedCount += 1
                let currentFinalCompleted = finalCompletedCount
                finalCounterLock.unlock()
                
                if currentFinalCompleted % 10 == 0 || currentFinalCompleted == totalSecondFilesCount {
                    let pct = 0.7 + (Double(currentFinalCompleted) / Double(totalSecondFilesCount)) * 0.25
                    DispatchQueue.main.async {
                        progressHandler(pct, "深度核对中 (\(currentFinalCompleted)/\(totalSecondFilesCount))...")
                    }
                }
            }
            
            for (hash, matchedFiles) in fullHashMap {
                if matchedFiles.count >= 2 {
                    let sizeStr = formatBytesCompact(size)
                    secondLock.lock()
                    finalGroups.append(DuplicateFileGroup(size: size, sizeString: sizeStr, hash: hash, files: matchedFiles))
                    secondLock.unlock()
                }
            }
        }
        
        progressHandler(1.0, "重复文件扫描完成！共发现 \(finalGroups.count) 组重复文件。")
        return finalGroups
    }
    
    public enum DuplicateSelectionRule: Int {
        case oldest = 0
        case newest = 1
        case shortestPath = 2
    }
    
    public static func autoSelectDuplicates(groups: [DuplicateFileGroup], rule: DuplicateSelectionRule) -> Set<URL> {
        var selected = Set<URL>()
        for group in groups {
            guard group.files.count >= 2 else { continue }
            var sortedFiles = group.files
            
            switch rule {
            case .oldest:
                sortedFiles.sort { urlA, urlB in
                    let dateA = (try? urlA.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let dateB = (try? urlB.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return dateA < dateB
                }
            case .newest:
                sortedFiles.sort { urlA, urlB in
                    let dateA = (try? urlA.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let dateB = (try? urlB.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return dateA > dateB
                }
            case .shortestPath:
                sortedFiles.sort { urlA, urlB in
                    return urlA.path.count < urlB.path.count
                }
            }
            
            // Select all duplicates except the first one to delete
            for i in 1..<sortedFiles.count {
                selected.insert(sortedFiles[i])
            }
        }
        return selected
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
        progressHandler(0.05, "正在扫描 Xcode DerivedData 缓存...")
        let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        if fileManager.fileExists(atPath: derivedDataPath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: derivedDataPath))
            if size > 0 {
                items.append(TrashItem(name: "Xcode DerivedData 编译缓存", path: derivedDataPath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "Xcode缓存"))
            }
        }
        
        // 2. Xcode Archives
        progressHandler(0.10, "正在扫描 Xcode Archives 历史归档...")
        let archivesPath = NSHomeDirectory() + "/Library/Developer/Xcode/Archives"
        if fileManager.fileExists(atPath: archivesPath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: archivesPath))
            if size > 0 {
                items.append(TrashItem(name: "Xcode Archives 历史归档", path: archivesPath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "Xcode缓存"))
            }
        }
        
        // 3. Xcode iOS DeviceSupport
        progressHandler(0.15, "正在扫描 iOS DeviceSupport 调试符号...")
        let deviceSupportPath = NSHomeDirectory() + "/Library/Developer/Xcode/iOS DeviceSupport"
        if fileManager.fileExists(atPath: deviceSupportPath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: deviceSupportPath))
            if size > 0 {
                items.append(TrashItem(name: "Xcode iOS DeviceSupport 调试符号", path: deviceSupportPath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "Xcode缓存"))
            }
        }
        
        // 4. CocoaPods Cache
        progressHandler(0.20, "正在扫描 CocoaPods 依赖包缓存...")
        let podsCachePath = NSHomeDirectory() + "/Library/Caches/CocoaPods"
        var podsCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: podsCachePath) {
            podsCacheSize = getDirectorySize(url: URL(fileURLWithPath: podsCachePath))
            if podsCacheSize > 0 {
                items.append(TrashItem(name: "CocoaPods 依赖包缓存", path: podsCachePath, sizeBytes: podsCacheSize, sizeString: formatBytes(podsCacheSize), typeLabel: "Xcode缓存"))
            }
        }
        
        // 5. SPM Cache
        progressHandler(0.25, "正在扫描 Swift Package Manager 缓存...")
        let spmCachePath = NSHomeDirectory() + "/Library/Caches/org.swift.swiftpm"
        var spmCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: spmCachePath) {
            spmCacheSize = getDirectorySize(url: URL(fileURLWithPath: spmCachePath))
            if spmCacheSize > 0 {
                items.append(TrashItem(name: "Swift Package Manager 缓存", path: spmCachePath, sizeBytes: spmCacheSize, sizeString: formatBytes(spmCacheSize), typeLabel: "Xcode缓存"))
            }
        }
        
        // 6. Homebrew Cache
        progressHandler(0.30, "正在扫描 Homebrew 缓存...")
        let brewCachePath = NSHomeDirectory() + "/Library/Caches/Homebrew"
        var brewCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: brewCachePath) {
            brewCacheSize = getDirectorySize(url: URL(fileURLWithPath: brewCachePath))
            if brewCacheSize > 0 {
                items.append(TrashItem(name: "Homebrew 缓存", path: brewCachePath, sizeBytes: brewCacheSize, sizeString: formatBytes(brewCacheSize), typeLabel: "包管理器缓存"))
            }
        }
        
        // 7. npm Cache
        progressHandler(0.35, "正在扫描 npm 全局缓存...")
        let npmCachePath = NSHomeDirectory() + "/.npm"
        if fileManager.fileExists(atPath: npmCachePath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: npmCachePath))
            if size > 0 {
                items.append(TrashItem(name: "npm 全局缓存", path: npmCachePath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "包管理器缓存"))
            }
        }
        
        // 8. pnpm Cache
        progressHandler(0.40, "正在扫描 pnpm 缓存...")
        let pnpmCachePath = NSHomeDirectory() + "/Library/Caches/pnpm"
        var pnpmCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: pnpmCachePath) {
            pnpmCacheSize = getDirectorySize(url: URL(fileURLWithPath: pnpmCachePath))
            if pnpmCacheSize > 0 {
                items.append(TrashItem(name: "pnpm 缓存", path: pnpmCachePath, sizeBytes: pnpmCacheSize, sizeString: formatBytes(pnpmCacheSize), typeLabel: "包管理器缓存"))
            }
        }
        
        // 9. Gradle Cache
        progressHandler(0.45, "正在扫描 Gradle 构建缓存...")
        let gradleCachePath = NSHomeDirectory() + "/.gradle/caches"
        if fileManager.fileExists(atPath: gradleCachePath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: gradleCachePath))
            if size > 0 {
                items.append(TrashItem(name: "Gradle 构建缓存", path: gradleCachePath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "包管理器缓存"))
            }
        }
        
        // 10. Google Chrome Cache
        progressHandler(0.50, "正在扫描 Chrome 浏览器缓存...")
        let chromeCachePath = NSHomeDirectory() + "/Library/Caches/Google/Chrome"
        var chromeCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: chromeCachePath) {
            chromeCacheSize = getDirectorySize(url: URL(fileURLWithPath: chromeCachePath))
            if chromeCacheSize > 0 {
                items.append(TrashItem(name: "Google Chrome 浏览器缓存", path: chromeCachePath, sizeBytes: chromeCacheSize, sizeString: formatBytes(chromeCacheSize), typeLabel: "应用缓存"))
            }
        }
        
        // 11. Safari Cache
        progressHandler(0.55, "正在扫描 Safari 浏览器缓存...")
        let safariCachePath = NSHomeDirectory() + "/Library/Caches/com.apple.Safari"
        var safariCacheSize: Int64 = 0
        if fileManager.fileExists(atPath: safariCachePath) {
            safariCacheSize = getDirectorySize(url: URL(fileURLWithPath: safariCachePath))
            if safariCacheSize > 0 {
                items.append(TrashItem(name: "Safari 浏览器缓存", path: safariCachePath, sizeBytes: safariCacheSize, sizeString: formatBytes(safariCacheSize), typeLabel: "应用缓存"))
            }
        }
        
        // 12. User Global Caches
        progressHandler(0.60, "正在扫描应用全局缓存...")
        let cachesPath = NSHomeDirectory() + "/Library/Caches"
        if fileManager.fileExists(atPath: cachesPath) {
            let rawCachesSize = getDirectorySize(url: URL(fileURLWithPath: cachesPath))
            let accountedCachesSize = podsCacheSize + spmCacheSize + brewCacheSize + pnpmCacheSize + chromeCacheSize + safariCacheSize
            let remainingCachesSize = max(0, rawCachesSize - accountedCachesSize)
            if remainingCachesSize > 1024 * 1024 {
                items.append(TrashItem(name: "其他应用全局缓存", path: cachesPath, sizeBytes: remainingCachesSize, sizeString: formatBytes(remainingCachesSize), typeLabel: "应用缓存"))
            }
        }
        
        // 13. System Logs & Diagnostics
        progressHandler(0.65, "正在扫描系统日志与诊断报告...")
        let logsPath = NSHomeDirectory() + "/Library/Logs"
        if fileManager.fileExists(atPath: logsPath) {
            let size = getDirectorySize(url: URL(fileURLWithPath: logsPath))
            if size > 0 {
                items.append(TrashItem(name: "系统日志与诊断报告", path: logsPath, sizeBytes: size, sizeString: formatBytes(size), typeLabel: "系统日志"))
            }
        }
        
        // 14. App Leftovers (Application Support)
        progressHandler(0.70, "正在深度扫描卸载残留文件...")
        let (installedNames, installedBundles) = getInstalledAppsInfo()
        let appSupportPath = NSHomeDirectory() + "/Library/Application Support"
        let appSupportURL = URL(fileURLWithPath: appSupportPath)
        
        if let subdirs = try? fileManager.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) {
            let totalSub = subdirs.count
            for (idx, subdir) in subdirs.enumerated() {
                let pct = 0.70 + (Double(idx) / Double(totalSub)) * 0.25
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
    
    public struct LargeFileItem: Identifiable, Hashable {
        public var id: String { path }
        public let name: String
        public let path: String
        public let sizeBytes: Int64
        public let sizeString: String
        public let typeLabel: String // "视频", "音频", "压缩包", "程序/镜像", "文档", "图片/设计", "其他"
        
        public init(name: String, path: String, sizeBytes: Int64, sizeString: String, typeLabel: String) {
            self.name = name
            self.path = path
            self.sizeBytes = sizeBytes
            self.sizeString = sizeString
            self.typeLabel = typeLabel
        }
    }
    
    private static func getLargeFileTypeLabel(ext: String) -> String {
        let lower = ext.lowercased()
        switch lower {
        case "mp4", "mkv", "mov", "avi", "flv", "wmv", "m4v", "webm":
            return "视频"
        case "mp3", "wav", "m4a", "flac", "aac", "ogg":
            return "音频"
        case "zip", "tar", "gz", "7z", "rar", "bz2", "xz":
            return "压缩包"
        case "dmg", "pkg", "iso", "app", "ipa":
            return "程序/镜像"
        case "pdf", "docx", "xlsx", "pptx", "pages", "numbers", "key", "txt", "md", "csv", "doc", "xls", "ppt":
            return "文档"
        case "psd", "ai", "sketch", "fig", "png", "jpg", "jpeg", "gif", "webp", "tiff", "heic":
            return "图片/设计"
        default:
            return "其他"
        }
    }
    
    public static func scanLargeFiles(in folder: URL, minSizeBytes: Int64, progressHandler: @escaping (Double, String) -> Void) -> [LargeFileItem] {
        var items: [LargeFileItem] = []
        let fileManager = FileManager.default
        
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isPackageKey, .isRegularFileKey, .isSymbolicLinkKey]
        
        guard let enumerator = fileManager.enumerator(at: folder,
                                                     includingPropertiesForKeys: keys,
                                                     options: [.skipsPackageDescendants, .skipsHiddenFiles],
                                                     errorHandler: { (url, error) -> Bool in
            print("[MemoryPurger] Error enumerating \(url): \(error)")
            return true
        }) else {
            return []
        }
        
        var count = 0
        let formatBytes: (Int64) -> String = { bytes in
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }
        
        let libraryPath = NSHomeDirectory() + "/Library"
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Prevent infinite loop on symbolic links
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               let isSymlink = resourceValues.isSymbolicLink, isSymlink {
                enumerator.skipDescendants()
                continue
            }
            
            // Check if we should skip Library to avoid scanning massive system/caches/app support directories
            if fileURL.path.hasPrefix(libraryPath) {
                enumerator.skipDescendants()
                continue
            }
            
            // Skip common dependency and version control folders to prevent CPU/IO spikes
            let lastComponent = fileURL.lastPathComponent
            if lastComponent == "node_modules" || lastComponent == ".git" || lastComponent == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            
            count += 1
            if count % 1000 == 0 {
                let displayPath = fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
                progressHandler(0.5, "已扫描 \(count) 个文件...\n当前: \(displayPath)")
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                
                // If it is a directory and not a package, we continue
                if let isDirectory = resourceValues.isDirectory, isDirectory {
                    if let isPackage = resourceValues.isPackage, isPackage {
                        // Package, get size
                        let size = getDirectorySize(url: fileURL)
                        if size >= minSizeBytes {
                            let sizeStr = formatBytes(size)
                            let label = getLargeFileTypeLabel(ext: fileURL.pathExtension)
                            items.append(LargeFileItem(name: fileURL.lastPathComponent, path: fileURL.path, sizeBytes: size, sizeString: sizeStr, typeLabel: label))
                        }
                        enumerator.skipDescendants()
                    }
                    continue
                }
                
                // Regular file
                if let isRegularFile = resourceValues.isRegularFile, isRegularFile {
                    if let fileSize = resourceValues.fileSize {
                        let sizeBytes = Int64(fileSize)
                        if sizeBytes >= minSizeBytes {
                            let sizeStr = formatBytes(sizeBytes)
                            let label = getLargeFileTypeLabel(ext: fileURL.pathExtension)
                            items.append(LargeFileItem(name: fileURL.lastPathComponent, path: fileURL.path, sizeBytes: sizeBytes, sizeString: sizeStr, typeLabel: label))
                        }
                    }
                }
            } catch {
                // Ignore errors
            }
        }
        
        items.sort { $0.sizeBytes > $1.sizeBytes }
        progressHandler(1.0, "扫描完成！共找到 \(items.count) 个大文件。")
        return items
    }
}

