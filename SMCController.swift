import Foundation
import IOKit

class SMCController {
    
    static let shared = SMCController()
    
    // Type Aliases matching SMCKit
    typealias FPE2 = (UInt8, UInt8)
    typealias SP78 = (UInt8, UInt8)
    typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                          UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    
    struct SMCVersion {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    
    struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    // Apple's predefined struct which must be exactly 80 bytes
    struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0,
                               0, 0, 0, 0, 0, 0, 0, 0)
    }
    
    private var connection: io_connect_t = 0
    private var isOpen = false
    private let lock = NSLock()
    private let cacheLock = NSLock()
    
    // Local memory caches for all metrics (second-level caching)
    private var _cachedCpuTemp: Float = 38.0
    private var _cachedGpuTemp: Float = 35.0
    private var _cachedCpuPerfCoresTemp: Float = 38.0
    private var _cachedCpuEffCoresTemp: Float = 36.0
    private var _cachedSsdTemp: Float = 32.0
    private var _cachedWifiTemp: Float = 38.0
    private var _cachedMemoryTemp: Float = 36.0
    private var _cachedPalmRestTemp: Float = 30.5
    private var _cachedAirflowTemp: Float = 28.0
    
    private var _cachedCpuVoltage: Double = 0.9
    private var _cachedGpuVoltage: Double = 0.85
    private var _cachedCpuPower: Double = 1.5
    private var _cachedGpuPower: Double = 0.5
    private var _cachedNpuPower: Double = 0.0
    private var _cachedSystemPower: Double = 5.0
    
    private var _cachedFanCount: Int = 0
    private var _cachedFanSpeeds: [Float] = Array(repeating: 0.0, count: 4)
    private var _cachedFanTargets: [Float] = Array(repeating: 0.0, count: 4)
    private var _cachedFanMins: [Float] = Array(repeating: 1200.0, count: 4)
    private var _cachedFanMaxs: [Float] = Array(repeating: 6000.0, count: 4)
    private var _cachedBatteryLimit: (limit: Int, active: Bool) = (80, false)
    private var _isFetchingBatteryLimit = false
    private let fetchLimitLock = NSLock()
    
    // Dynamic Blacklist for missing keys to reduce hardware IO errors
    private var unsupportedKeys = Set<String>()
    private var keyFailCount = [String: Int]()
    private var keyInfoCache = [String: SMCKeyInfoData]()
    
    init() {
        if let savedBlacklist = UserDefaults.standard.stringArray(forKey: "SMCUnsupportedKeys") {
            unsupportedKeys = Set(savedBlacklist)
        }
        doOpen()
    }
    
    deinit {
        doClose()
    }
    
    func doOpen() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 {
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            if result == kIOReturnSuccess {
                isOpen = true
            } else {
                print("[SMC] Failed to open SMC connection: \(result)")
                connection = 0
            }
            IOObjectRelease(service)
        } else {
            print("[SMC] AppleSMC service not found")
        }
    }
    
    func doClose() {
        if isOpen && connection != 0 {
            IOServiceClose(connection)
            connection = 0
            isOpen = false
        }
    }
    
    private func runDriverCall(_ input: inout SMCParamStruct, selector: UInt8 = 2) -> Bool {
        guard isOpen && connection != 0 else { return false }
        assert(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct stride must be exactly 80 bytes")
        
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        var output = SMCParamStruct()
        
        let result = IOConnectCallStructMethod(
            connection,
            UInt32(selector),
            &input,
            inputSize,
            &output,
            &outputSize
        )
        
        if result == kIOReturnSuccess && output.result == 0 {
            input = output
            return true
        }
        return false
    }
    
    private func callDriver(_ input: inout SMCParamStruct, selector: UInt8 = 2, forceSync: Bool = false) -> (success: Bool, lockContention: Bool) {
        if Thread.isMainThread && !forceSync {
            // Main UI thread: non-blocking try-lock to protect UI responsiveness for reads
            guard lock.try() else {
                return (false, true) // Lock is held by background thread, instantly bail to fallback cache
            }
            defer { lock.unlock() }
            let ok = runDriverCall(&input, selector: selector)
            return (ok, false)
        } else {
            // Background thread OR forced write operation: synchronous lock, perfectly safe to wait here
            lock.lock()
            defer { lock.unlock() }
            let ok = runDriverCall(&input, selector: selector)
            return (ok, false)
        }
    }
    
    // Dynamic key support checking
    private func isKeyUnsupported(_ keyStr: String) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return unsupportedKeys.contains(keyStr)
    }
    
    private func markKeyFailed(_ keyStr: String) {
        cacheLock.lock()
        guard !unsupportedKeys.contains(keyStr) else {
            cacheLock.unlock()
            return
        }
        let current = keyFailCount[keyStr] ?? 0
        let next = current + 1
        keyFailCount[keyStr] = next
        if next >= 3 {
            unsupportedKeys.insert(keyStr)
            let list = Array(unsupportedKeys)
            cacheLock.unlock()
            DispatchQueue.global(qos: .background).async {
                UserDefaults.standard.set(list, forKey: "SMCUnsupportedKeys")
            }
            print("[SMC] Key '\(keyStr)' failed \(next) times. Blacklisting it to eliminate hardware delays.")
        } else {
            cacheLock.unlock()
        }
    }
    
    // Conversions
    private func stringToFourCharCode(_ str: String) -> UInt32 {
        var result: UInt32 = 0
        let chars = Array(str.utf8)
        for i in 0..<min(4, chars.count) {
            result = (result << 8) + UInt32(chars[i])
        }
        return result
    }
    
    private func fourCharCodeToString(_ code: UInt32) -> String {
        let c1 = UnicodeScalar((code >> 24) & 0xff).map(Character.init) ?? " "
        let c2 = UnicodeScalar((code >> 16) & 0xff).map(Character.init) ?? " "
        let c3 = UnicodeScalar((code >> 8) & 0xff).map(Character.init) ?? " "
        let c4 = UnicodeScalar(code & 0xff).map(Character.init) ?? " "
        return String([c1, c2, c3, c4]).trimmingCharacters(in: .whitespaces)
    }
    
    // Read Key Data
    func readKey(_ keyStr: String) -> SMCBytes? {
        if isKeyUnsupported(keyStr) { return nil }
        
        let key = stringToFourCharCode(keyStr)
        
        var keyInfo: SMCKeyInfoData
        cacheLock.lock()
        if let cachedInfo = keyInfoCache[keyStr] {
            keyInfo = cachedInfo
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            // 1. Get Key Info (size and type)
            var inputInfo = SMCParamStruct()
            inputInfo.key = key
            inputInfo.data8 = 9 // kSMCGetKeyInfo
            
            let resInfo = callDriver(&inputInfo)
            guard resInfo.success else {
                if !resInfo.lockContention {
                    markKeyFailed(keyStr)
                }
                return nil
            }
            keyInfo = inputInfo.keyInfo
            
            cacheLock.lock()
            keyInfoCache[keyStr] = keyInfo
            cacheLock.unlock()
        }
        
        // 2. Read the Key Value
        var inputRead = SMCParamStruct()
        inputRead.key = key
        inputRead.keyInfo = keyInfo
        inputRead.data8 = 5 // kSMCReadKey
        
        let resRead = callDriver(&inputRead)
        guard resRead.success else {
            if !resRead.lockContention {
                markKeyFailed(keyStr)
            }
            return nil
        }
        return inputRead.bytes
    }
    
    // Write Key Data
    func writeKey(_ keyStr: String, bytes: SMCBytes, size: UInt32) -> Bool {
        let key = stringToFourCharCode(keyStr)
        
        var keyInfo: SMCKeyInfoData
        cacheLock.lock()
        if let cachedInfo = keyInfoCache[keyStr] {
            keyInfo = cachedInfo
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            // 1. Get Key Info
            var inputInfo = SMCParamStruct()
            inputInfo.key = key
            inputInfo.data8 = 9 // kSMCGetKeyInfo
            
            let resInfo = callDriver(&inputInfo, forceSync: true)
            guard resInfo.success else { return false }
            keyInfo = inputInfo.keyInfo
            
            cacheLock.lock()
            keyInfoCache[keyStr] = keyInfo
            cacheLock.unlock()
        }
        
        // 2. Write the Key Value
        var inputWrite = SMCParamStruct()
        inputWrite.key = key
        inputWrite.bytes = bytes
        inputWrite.keyInfo = keyInfo
        inputWrite.keyInfo.dataSize = size
        inputWrite.data8 = 6 // kSMCWriteKey
        
        let resWrite = callDriver(&inputWrite, forceSync: true)
        return resWrite.success
    }
    
    // Fan speed conversions
    // fpe2 type: big-endian unsigned 16-bit, 2 fraction bits
    // Correct: (byte0 << 8 | byte1) >> 2
    private func fromFPE2(_ bytes: (UInt8, UInt8)) -> Float {
        let raw = Int(bytes.0) << 8 | Int(bytes.1)
        return Float(raw) / 4.0
    }
    
    private func toFPE2(_ speed: Float) -> (UInt8, UInt8) {
        let raw = min(65535, max(0, Int(round(speed * 4.0))))
        let byte0 = UInt8((raw >> 8) & 0xFF)
        let byte1 = UInt8(raw & 0xFF)
        return (byte0, byte1)
    }
    
    // Auto-detect and decode a fan speed key (handles both fpe2 and float32)
    private func readFanFloat(_ keyStr: String, defaultVal: Float = 0.0) -> Float {
        if isKeyUnsupported(keyStr) { return defaultVal }
        
        let key = stringToFourCharCode(keyStr)
        
        var keyInfo: SMCKeyInfoData
        cacheLock.lock()
        if let cachedInfo = keyInfoCache[keyStr] {
            keyInfo = cachedInfo
            cacheLock.unlock()
        } else {
            cacheLock.unlock()
            var inputInfo = SMCParamStruct()
            inputInfo.key = key
            inputInfo.data8 = 9 // kSMCGetKeyInfo
            let resInfo = callDriver(&inputInfo)
            guard resInfo.success else {
                if !resInfo.lockContention {
                    markKeyFailed(keyStr)
                }
                return defaultVal
            }
            keyInfo = inputInfo.keyInfo
            
            cacheLock.lock()
            keyInfoCache[keyStr] = keyInfo
            cacheLock.unlock()
        }
        
        var inputRead = SMCParamStruct()
        inputRead.key = key
        inputRead.keyInfo = keyInfo
        inputRead.data8 = 5 // kSMCReadKey
        let resRead = callDriver(&inputRead)
        guard resRead.success else {
            if !resRead.lockContention {
                markKeyFailed(keyStr)
            }
            return defaultVal
        }
        
        let b = inputRead.bytes
        let dataSize = keyInfo.dataSize
        
        if dataSize == 4 {
            // IEEE 754 float32 (little-endian)
            var f: Float = 0
            withUnsafeMutableBytes(of: &f) { ptr in
                ptr[0] = b.0; ptr[1] = b.1; ptr[2] = b.2; ptr[3] = b.3
            }
            return f
        } else {
            // fpe2 2-byte big-endian fixed point
            return fromFPE2((b.0, b.1))
        }
    }
    
    // Temperature conversion
    // sp78 type: signed 7.8 fixed point (1 bit sign, 7 bit integer, 8 bit fraction)
    private func fromSP78(_ bytes: (UInt8, UInt8)) -> Float {
        let rawVal = Int16(bitPattern: (UInt16(bytes.0) << 8) | UInt16(bytes.1))
        return Float(rawVal) / 256.0
    }
    
    // PUBLIC API WITH SOLID CACHING INTEGRATION
    
    // Get CPU Temperature
    func getCPUTemperature() -> Float {
        let preferredKeys = ["Tp0b", "Tp09", "Tp0j", "Tp0f", "Tp0D", "TC0F", "TC0D", "TC0P"]
        var validReadings: [Float] = []

        for key in preferredKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 20.0 && temp <= 95.0 {
                    validReadings.append(temp)
                    if validReadings.count >= 2 { break }
                }
            }
        }

        if !validReadings.isEmpty {
            let avg = validReadings.reduce(0, +) / Float(validReadings.count)
            cacheLock.lock()
            _cachedCpuTemp = avg
            cacheLock.unlock()
            return avg
        }

        let fallbackKeys = ["Tp05", "Tp01", "Tpb0", "Tpb1", "TB0T", "TB1T"]
        for key in fallbackKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 95.0 {
                    cacheLock.lock()
                    _cachedCpuTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }

        cacheLock.lock()
        let fallbackVal = _cachedCpuTemp
        cacheLock.unlock()
        return fallbackVal
    }

    // Get GPU Temperature
    func getGPUTemperature() -> Float {
        let gpuKeys = ["Tg05", "Tg09", "TG0D", "TG0P", "Tg0D"]
        var validReadings: [Float] = []

        for key in gpuKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 20.0 && temp <= 100.0 {
                    validReadings.append(temp)
                    if validReadings.count >= 2 { break }
                }
            }
        }

        if !validReadings.isEmpty {
            let avg = validReadings.reduce(0, +) / Float(validReadings.count)
            cacheLock.lock()
            _cachedGpuTemp = avg
            cacheLock.unlock()
            return avg
        }
        
        // Final fallback: derived from CPU, or the cached value
        cacheLock.lock()
        let cpuT = _cachedCpuTemp
        let cachedG = _cachedGpuTemp
        cacheLock.unlock()
        
        let derived = max(cpuT - 3.0, 20.0)
        return cachedG > 20.0 ? cachedG : derived
    }

    // Get CPU Performance Cores Temperature
    func getCPUPerfCoresTemperature() -> Float {
        if let bytes = readKey("Tp0b") {
            let temp = fromSP78((bytes.0, bytes.1))
            if temp >= 20.0 && temp <= 105.0 {
                cacheLock.lock()
                _cachedCpuPerfCoresTemp = temp
                cacheLock.unlock()
                return temp
            }
        }
        if let bytes = readKey("Tp09") {
            let temp = fromSP78((bytes.0, bytes.1))
            if temp >= 20.0 && temp <= 105.0 {
                cacheLock.lock()
                _cachedCpuPerfCoresTemp = temp
                cacheLock.unlock()
                return temp
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedCpuPerfCoresTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get CPU Efficiency Cores Temperature
    func getCPUEffCoresTemperature() -> Float {
        if let bytes = readKey("Tp0c") {
            let temp = fromSP78((bytes.0, bytes.1))
            if temp >= 20.0 && temp <= 105.0 {
                cacheLock.lock()
                _cachedCpuEffCoresTemp = temp
                cacheLock.unlock()
                return temp
            }
        }
        if let bytes = readKey("Tp0j") {
            let temp = fromSP78((bytes.0, bytes.1))
            if temp >= 20.0 && temp <= 105.0 {
                cacheLock.lock()
                _cachedCpuEffCoresTemp = temp
                cacheLock.unlock()
                return temp
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedCpuEffCoresTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get SSD Temperature
    func getSSDTemperature() -> Float {
        let ssdKeys = ["Ts00", "Ts01", "Ts02", "Ts05"]
        for key in ssdKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 80.0 {
                    cacheLock.lock()
                    _cachedSsdTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedSsdTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get Wi-Fi Module Temperature
    func getWiFiTemperature() -> Float {
        let wifiKeys = ["Tw00", "Tw01", "Tw0f"]
        for key in wifiKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 85.0 {
                    cacheLock.lock()
                    _cachedWifiTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedWifiTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get Memory (RAM) Temperature
    func getMemoryTemperature() -> Float {
        let ramKeys = ["Tm00", "Tm01", "Tm05", "Tm0p"]
        for key in ramKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 85.0 {
                    cacheLock.lock()
                    _cachedMemoryTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedMemoryTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get Palm Rest Temperature
    func getPalmRestTemperature() -> Float {
        let palmKeys = ["Th00", "Th01", "Th02", "Th0f"]
        for key in palmKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 50.0 {
                    cacheLock.lock()
                    _cachedPalmRestTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedPalmRestTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get Internal Airflow / Ambient Temperature
    func getAirflowTemperature() -> Float {
        let ambientKeys = ["Ta00", "Ta01", "Ta02"]
        for key in ambientKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 10.0 && temp <= 65.0 {
                    cacheLock.lock()
                    _cachedAirflowTemp = temp
                    cacheLock.unlock()
                    return temp
                }
            }
        }
        
        cacheLock.lock()
        let fallback = _cachedAirflowTemp
        cacheLock.unlock()
        return fallback
    }
    
    // Get CPU Core Voltage
    func getCPUVoltage(load: Double) -> Double {
        if let bytes = readKey("VC0C") {
            let rawVal = Double(Int(bytes.0) << 8 | Int(bytes.1))
            if rawVal > 100 && rawVal < 2000 {
                let volt = rawVal / 1000.0
                cacheLock.lock()
                _cachedCpuVoltage = volt
                cacheLock.unlock()
                return volt
            }
        }
        
        // DVFS estimation based on load if hardware fails or main thread returns cached
        cacheLock.lock()
        let cached = _cachedCpuVoltage
        cacheLock.unlock()
        
        if cached > 0.1 && Thread.isMainThread { return cached }
        
        let baseVolts = 0.72
        let scale = 0.43
        let est = baseVolts + (load / 100.0) * scale
        
        cacheLock.lock()
        _cachedCpuVoltage = est
        cacheLock.unlock()
        return est
    }
    
    // Get GPU Core Voltage
    func getGPUVoltage(load: Double) -> Double {
        if let bytes = readKey("VG0C") {
            let rawVal = Double(Int(bytes.0) << 8 | Int(bytes.1))
            if rawVal > 100 && rawVal < 2000 {
                let volt = rawVal / 1000.0
                cacheLock.lock()
                _cachedGpuVoltage = volt
                cacheLock.unlock()
                return volt
            }
        }
        
        cacheLock.lock()
        let cached = _cachedGpuVoltage
        cacheLock.unlock()
        
        if cached > 0.1 && Thread.isMainThread { return cached }
        
        let baseVolts = 0.75
        let scale = 0.30
        let est = baseVolts + (load / 100.0) * scale
        
        cacheLock.lock()
        _cachedGpuVoltage = est
        cacheLock.unlock()
        return est
    }
    
    // Get CPU Power (Watts)
    func getCPUPower(load: Double) -> Double {
        if let bytes = readKey("PCPU") {
            let sign: Double = (bytes.0 & 0x80 == 0) ? 1.0 : -1.0
            let intVal = Double(bytes.0 & 0x7F)
            let fracVal = Double(bytes.1) / 256.0
            let watts = sign * (intVal + fracVal)
            if watts >= 0.1 && watts <= 120.0 {
                cacheLock.lock()
                _cachedCpuPower = watts
                cacheLock.unlock()
                return watts
            }
        }
        
        cacheLock.lock()
        let cached = _cachedCpuPower
        cacheLock.unlock()
        
        if cached > 0.1 && Thread.isMainThread { return cached }
        
        let idlePower = 1.2
        let peakPower = 28.8
        let est = idlePower + (load / 100.0) * peakPower
        
        cacheLock.lock()
        _cachedCpuPower = est
        cacheLock.unlock()
        return est
    }
    
    // Get GPU Power (Watts)
    func getGPUPower(load: Double) -> Double {
        if let bytes = readKey("PGPU") {
            let sign: Double = (bytes.0 & 0x80 == 0) ? 1.0 : -1.0
            let intVal = Double(bytes.0 & 0x7F)
            let fracVal = Double(bytes.1) / 256.0
            let watts = sign * (intVal + fracVal)
            if watts >= 0.1 && watts <= 120.0 {
                cacheLock.lock()
                _cachedGpuPower = watts
                cacheLock.unlock()
                return watts
            }
        }
        
        cacheLock.lock()
        let cached = _cachedGpuPower
        cacheLock.unlock()
        
        if cached > 0.1 && Thread.isMainThread { return cached }
        
        let idlePower = 0.5
        let peakPower = 14.5
        let est = idlePower + (load / 100.0) * peakPower
        
        cacheLock.lock()
        _cachedGpuPower = est
        cacheLock.unlock()
        return est
    }
    
    // Get NPU Power (Watts)
    func getNPUPower(load: Double) -> Double {
        if let bytes = readKey("PANE") {
            let sign: Double = (bytes.0 & 0x80 == 0) ? 1.0 : -1.0
            let intVal = Double(bytes.0 & 0x7F)
            let fracVal = Double(bytes.1) / 256.0
            let watts = sign * (intVal + fracVal)
            if watts >= 0.0 && watts <= 120.0 {
                cacheLock.lock()
                _cachedNpuPower = watts
                cacheLock.unlock()
                return watts
            }
        }
        
        cacheLock.lock()
        let cached = _cachedNpuPower
        cacheLock.unlock()
        
        if cached > 0.0 && Thread.isMainThread { return cached }
        
        // Estimation if hardware key doesn't exist
        let est = (load / 100.0) * 15.0 // ANE peak is around 15W
        
        cacheLock.lock()
        _cachedNpuPower = est
        cacheLock.unlock()
        return est
    }
    
    // Get System Total Power (Watts)
    func getSystemPower() -> Double {
        if let bytes = readKey("PSTR") {
            let sign: Double = (bytes.0 & 0x80 == 0) ? 1.0 : -1.0
            let intVal = Double(bytes.0 & 0x7F)
            let fracVal = Double(bytes.1) / 256.0
            let watts = sign * (intVal + fracVal)
            if watts >= 0.1 && watts <= 250.0 {
                cacheLock.lock()
                _cachedSystemPower = watts
                cacheLock.unlock()
                return watts
            }
        }
        
        cacheLock.lock()
        let cached = _cachedSystemPower
        cacheLock.unlock()
        
        if cached > 0.1 && Thread.isMainThread { return cached }
        
        // Sum up parts plus basic idle base
        let cpu = _cachedCpuPower
        let gpu = _cachedGpuPower
        let npu = _cachedNpuPower
        let est = cpu + gpu + npu + 3.5 // 3.5W base for screen/board
        
        cacheLock.lock()
        _cachedSystemPower = est
        cacheLock.unlock()
        return est
    }

    // Get Fan Count
    func getFanCount() -> Int {
        if let bytes = readKey("FNum") {
            let count = Int(bytes.0)
            cacheLock.lock()
            _cachedFanCount = count
            cacheLock.unlock()
            return count
        }
        
        cacheLock.lock()
        let fallback = _cachedFanCount
        cacheLock.unlock()
        return fallback > 0 ? fallback : 0
    }
    
    // Get Fan Actual Speed (RPM)
    func getFanSpeed(_ fanIndex: Int) -> Float {
        let key = "F\(fanIndex)Ac"
        let speed = readFanFloat(key, defaultVal: -1.0)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if speed >= 0.0 {
            if fanIndex >= _cachedFanSpeeds.count {
                _cachedFanSpeeds.append(speed)
            } else {
                _cachedFanSpeeds[fanIndex] = speed
            }
            return speed
        }
        
        return fanIndex < _cachedFanSpeeds.count ? _cachedFanSpeeds[fanIndex] : 0.0
    }
    
    // Get Fan Target Speed
    func getFanTargetSpeed(_ fanIndex: Int) -> Float {
        let key = "F\(fanIndex)Tg"
        let speed = readFanFloat(key, defaultVal: -1.0)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if speed >= 0.0 {
            if fanIndex >= _cachedFanTargets.count {
                _cachedFanTargets.append(speed)
            } else {
                _cachedFanTargets[fanIndex] = speed
            }
            return speed
        }
        
        return fanIndex < _cachedFanTargets.count ? _cachedFanTargets[fanIndex] : 1200.0
    }
    
    // Get Fan Minimum Speed
    func getFanMinSpeed(_ fanIndex: Int) -> Float {
        let key = "F\(fanIndex)Mn"
        let speed = readFanFloat(key, defaultVal: -1.0)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if speed > 0.0 {
            if fanIndex >= _cachedFanMins.count {
                _cachedFanMins.append(speed)
            } else {
                _cachedFanMins[fanIndex] = speed
            }
            return speed
        }
        
        let fallback = fanIndex < _cachedFanMins.count ? _cachedFanMins[fanIndex] : 1200.0
        return fallback > 0 ? fallback : 1200.0
    }
    
    // Get Fan Maximum Speed
    func getFanMaxSpeed(_ fanIndex: Int) -> Float {
        let key = "F\(fanIndex)Mx"
        let speed = readFanFloat(key, defaultVal: -1.0)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        if speed > 0.0 {
            if fanIndex >= _cachedFanMaxs.count {
                _cachedFanMaxs.append(speed)
            } else {
                _cachedFanMaxs[fanIndex] = speed
            }
            return speed
        }
        
        let fallback = fanIndex < _cachedFanMaxs.count ? _cachedFanMaxs[fanIndex] : 6000.0
        return fallback > 0 ? fallback : 6000.0
    }
    
    // Enable manual fan speed control (Force Bitmask)
    func setFanManual(_ manual: Bool, fanBitmask: UInt16 = 3) -> Bool {
        let isAppleSilicon = readKey("FS! ") == nil
        
        if isAppleSilicon {
            let numFans = getFanCount()
            var success = true
            for i in 0..<numFans {
                if (fanBitmask & (1 << i)) != 0 {
                    let key = "F\(i)Md"
                    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    bytes.0 = manual ? 1 : 0
                    if !writeKey(key, bytes: bytes, size: 1) {
                        success = false
                    }
                }
            }
            return success
        } else {
            let key = "FS! "
            let mask: UInt16 = manual ? fanBitmask : 0
            
            var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            bytes.0 = UInt8(mask >> 8)
            bytes.1 = UInt8(mask & 0xff)
            
            return writeKey(key, bytes: bytes, size: 2)
        }
    }
    
    // Set Target Fan Speed (RPM)
    func setFanSpeed(_ fanIndex: Int, speed: Float) -> Bool {
        let keyStr = "F\(fanIndex)Tg"
        let key = stringToFourCharCode(keyStr)
        
        var inputInfo = SMCParamStruct()
        inputInfo.key = key
        inputInfo.data8 = 9 // kSMCGetKeyInfo
        let resInfo = callDriver(&inputInfo, forceSync: true)
        guard resInfo.success else { return false }
        
        let dataSize = inputInfo.keyInfo.dataSize
        var smcBytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        
        if dataSize == 4 {
            var f = speed
            withUnsafeBytes(of: &f) { buffer in
                smcBytes.0 = buffer[0]
                smcBytes.1 = buffer[1]
                smcBytes.2 = buffer[2]
                smcBytes.3 = buffer[3]
            }
        } else {
            let fpe2Bytes = toFPE2(speed)
            smcBytes.0 = fpe2Bytes.0
            smcBytes.1 = fpe2Bytes.1
        }
        
        var inputWrite = SMCParamStruct()
        inputWrite.key = key
        inputWrite.bytes = smcBytes
        inputWrite.keyInfo = inputInfo.keyInfo
        inputWrite.keyInfo.dataSize = dataSize
        inputWrite.data8 = 6 // kSMCWriteKey
        
        let resWrite = callDriver(&inputWrite, forceSync: true)
        let success = resWrite.success
        if success {
            cacheLock.lock()
            if fanIndex < _cachedFanTargets.count {
                _cachedFanTargets[fanIndex] = speed
            }
            cacheLock.unlock()
        }
        return success
    }
    
    // Enable/Disable battery charging limit
    func setBatteryChargeLimit(_ limit: Int, active: Bool) -> Bool {
        var success = false
        
        // 1. Try BCLM (standard on Intel and supported on M1 Macbooks)
        let bclmKey = "BCLM"
        var bclmBytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        bclmBytes.0 = active ? UInt8(limit) : 100
        if writeKey(bclmKey, bytes: bclmBytes, size: 1) {
            success = true
        }
        
        // 2. Try CHWA (supported on newer M-series Macbooks)
        let chwaKey = "CHWA"
        var chwaBytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        chwaBytes.0 = active ? 1 : 0
        if writeKey(chwaKey, bytes: chwaBytes, size: 1) {
            success = true
        }
        
        // 3. Try CH0B (supported on M1/M2/M3 newer hardware)
        let ch0bKey = "CH0B"
        var ch0bBytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        ch0bBytes.0 = active ? 1 : 0
        if writeKey(ch0bKey, bytes: ch0bBytes, size: 1) {
            success = true
        }
        
        if success {
            cacheLock.lock()
            _cachedBatteryLimit = (limit: limit, active: active)
            cacheLock.unlock()
        }
        return success
    }
    
    // Read current battery charge limit setting
    func getBatteryChargeLimit() -> (limit: Int, active: Bool) {
        if Thread.isMainThread {
            cacheLock.lock()
            let val = _cachedBatteryLimit
            cacheLock.unlock()
            
            fetchLimitLock.lock()
            let alreadyFetching = _isFetchingBatteryLimit
            if !alreadyFetching {
                _isFetchingBatteryLimit = true
                fetchLimitLock.unlock()
                
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let self = self else { return }
                    _ = self.getBatteryChargeLimitInternal()
                    self.fetchLimitLock.lock()
                    self._isFetchingBatteryLimit = false
                    self.fetchLimitLock.unlock()
                }
            } else {
                fetchLimitLock.unlock()
            }
            
            return val
        } else {
            return getBatteryChargeLimitInternal()
        }
    }
    
    private func getBatteryChargeLimitInternal() -> (limit: Int, active: Bool) {
        // 1. Try BCLM
        if let bytes = readKey("BCLM") {
            let val = Int(bytes.0)
            if val > 0 && val <= 100 {
                let active = val < 100
                let limitVal = (limit: val, active: active)
                cacheLock.lock()
                _cachedBatteryLimit = limitVal
                cacheLock.unlock()
                return limitVal
            }
        }
        
        // 2. Try CHWA
        if let bytes = readKey("CHWA") {
            let enabled = bytes.0 != 0
            let limitVal = (limit: 80, active: enabled)
            cacheLock.lock()
            _cachedBatteryLimit = limitVal
            cacheLock.unlock()
            return limitVal
        }
        
        // 3. Try CH0B
        if let bytes = readKey("CH0B") {
            let enabled = bytes.0 != 0
            let limitVal = (limit: 80, active: enabled)
            cacheLock.lock()
            _cachedBatteryLimit = limitVal
            cacheLock.unlock()
            return limitVal
        }
        
        // 4. Fallback: Try reading via authorized smchelper readcharge to bypass sandbox limits
        let helperPath = "/Library/PrivilegedHelperTools/com.hl.smchelper"
        if FileManager.default.fileExists(atPath: helperPath) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            proc.arguments = ["-n", helperPath, "readcharge"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            do {
                try proc.run()
                proc.waitUntilExit()
                if proc.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        let parts = output.components(separatedBy: " ")
                        if parts.count >= 2, let limit = Int(parts[0]), let activeInt = Int(parts[1]) {
                            let limitVal = (limit: limit, active: activeInt != 0)
                            cacheLock.lock()
                            _cachedBatteryLimit = limitVal
                            cacheLock.unlock()
                            return limitVal
                        }
                    }
                }
            } catch {}
        }
        
        cacheLock.lock()
        let fallback = _cachedBatteryLimit
        cacheLock.unlock()
        return fallback
    }
}
