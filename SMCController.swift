import Foundation
import IOKit

class SMCController {
    
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
    
    init() {
        doOpen()
    }
    
    deinit {
        doClose()
    }
    
    func doOpen() {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
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
    
    private func callDriver(_ input: inout SMCParamStruct, selector: UInt8 = 2) -> Bool {
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
        let key = stringToFourCharCode(keyStr)
        
        // 1. Get Key Info (size and type)
        var inputInfo = SMCParamStruct()
        inputInfo.key = key
        inputInfo.data8 = 9 // kSMCGetKeyInfo
        
        guard callDriver(&inputInfo) else { return nil }
        
        // 2. Read the Key Value
        var inputRead = SMCParamStruct()
        inputRead.key = key
        inputRead.keyInfo = inputInfo.keyInfo
        inputRead.data8 = 5 // kSMCReadKey
        
        guard callDriver(&inputRead) else { return nil }
        return inputRead.bytes
    }
    
    // Write Key Data
    func writeKey(_ keyStr: String, bytes: SMCBytes, size: UInt32) -> Bool {
        let key = stringToFourCharCode(keyStr)
        
        // 1. Get Key Info
        var inputInfo = SMCParamStruct()
        inputInfo.key = key
        inputInfo.data8 = 9 // kSMCGetKeyInfo
        
        guard callDriver(&inputInfo) else { return false }
        
        // 2. Write the Key Value
        var inputWrite = SMCParamStruct()
        inputWrite.key = key
        inputWrite.bytes = bytes
        inputWrite.keyInfo = inputInfo.keyInfo
        inputWrite.keyInfo.dataSize = size
        inputWrite.data8 = 6 // kSMCWriteKey
        
        return callDriver(&inputWrite)
    }
    
    // Fan speed conversions
    // fpe2 type: big-endian unsigned 16-bit, 2 fraction bits
    // Correct: (byte0 << 8 | byte1) >> 2
    private func fromFPE2(_ bytes: (UInt8, UInt8)) -> Float {
        let raw = (Int(bytes.0) << 8 | Int(bytes.1)) >> 2
        return Float(raw)
    }
    
    private func toFPE2(_ speed: Float) -> (UInt8, UInt8) {
        let raw = Int(speed) << 2  // shift up by 2 fraction bits
        let byte0 = UInt8((raw >> 8) & 0xFF)
        let byte1 = UInt8(raw & 0xFF)
        return (byte0, byte1)
    }
    
    // Auto-detect and decode a fan speed key (handles both fpe2 and float32)
    private func readFanFloat(_ keyStr: String, defaultVal: Float = 0.0) -> Float {
        let key = stringToFourCharCode(keyStr)
        
        var inputInfo = SMCParamStruct()
        inputInfo.key = key
        inputInfo.data8 = 9 // kSMCGetKeyInfo
        guard callDriver(&inputInfo) else { return defaultVal }
        
        var inputRead = SMCParamStruct()
        inputRead.key = key
        inputRead.keyInfo = inputInfo.keyInfo
        inputRead.data8 = 5 // kSMCReadKey
        guard callDriver(&inputRead) else { return defaultVal }
        
        let b = inputRead.bytes
        let dataSize = inputInfo.keyInfo.dataSize
        
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
        let sign: Float = (bytes.0 & 0x80 == 0) ? 1.0 : -1.0
        let intVal = Float(bytes.0 & 0x7F)
        let fracVal = Float(bytes.1) / 256.0
        return sign * (intVal + fracVal)
    }
    
    // PUBLIC API
    
    // Get CPU Temperature
    // Key priority on Apple Silicon MacBook Pro 18,1:
    //   Tp0b = CPU cluster die temp (~45-75°C normal)  ← preferred
    //   Tp09 = CPU cluster                             ← fallback
    //   Tp0j = another cluster sensor
    //   Tp05, Tp01 = VR hotspot (can be 90-100°C even idle) ← avoid as primary
    //   TC0F/TC0D = Intel Macs
    func getCPUTemperature() -> Float {
        // Sensors ordered from most representative → least (VR hotspot last)
        let preferredKeys = ["Tp0b", "Tp09", "Tp0j", "Tp0f", "Tp0D", "TC0F", "TC0D", "TC0P"]
        var validReadings: [Float] = []

        for key in preferredKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                // Accept only physically plausible CPU die temps
                if temp >= 20.0 && temp <= 95.0 {
                    validReadings.append(temp)
                    if validReadings.count >= 2 { break }   // average up to 2 sensors
                }
            }
        }

        if !validReadings.isEmpty {
            return validReadings.reduce(0, +) / Float(validReadings.count)
        }

        // Wider fallback range — still exclude VR hotspot outliers > 115°C
        let fallbackKeys = ["Tp05", "Tp01", "Tpb0", "Tpb1", "TB0T", "TB1T"]
        for key in fallbackKeys {
            if let bytes = readKey(key) {
                let temp = fromSP78((bytes.0, bytes.1))
                if temp >= 15.0 && temp <= 95.0 {
                    return temp
                }
            }
        }

        return 38.0   // safe fallback for virtual machines / unknown hardware
    }

    // Get GPU Temperature
    // Tg05 = GPU die temp on Apple Silicon (~40-80°C normal)
    // Tg0D = GPU hotspot (higher, avoid as primary display value)
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
            return validReadings.reduce(0, +) / Float(validReadings.count)
        }
        // Final fallback: derived from CPU
        return max(getCPUTemperature() - 3.0, 20.0)
    }

    
    // Get Fan Count
    func getFanCount() -> Int {
        if let bytes = readKey("FNum") {
            return Int(bytes.0)
        }
        return 0
    }
    
    // Get Fan Actual Speed (RPM) — auto-detects fpe2 vs float32
    func getFanSpeed(_ fanIndex: Int) -> Float {
        return readFanFloat("F\(fanIndex)Ac", defaultVal: 0.0)
    }
    
    // Get Fan Target Speed — auto-detects fpe2 vs float32
    func getFanTargetSpeed(_ fanIndex: Int) -> Float {
        return readFanFloat("F\(fanIndex)Tg", defaultVal: 0.0)
    }
    
    // Get Fan Minimum Speed — auto-detects fpe2 vs float32
    func getFanMinSpeed(_ fanIndex: Int) -> Float {
        let v = readFanFloat("F\(fanIndex)Mn", defaultVal: 1200.0)
        return v > 0 ? v : 1200.0
    }
    
    // Get Fan Maximum Speed — auto-detects fpe2 vs float32
    func getFanMaxSpeed(_ fanIndex: Int) -> Float {
        let v = readFanFloat("F\(fanIndex)Mx", defaultVal: 6000.0)
        return v > 0 ? v : 6000.0
    }
    
    // Enable manual fan speed control (Force Bitmask)
    // fanBitmask: 1 = fan 0 manual, 3 = fan 0 & fan 1 manual
    func setFanManual(_ manual: Bool, fanBitmask: UInt16 = 3) -> Bool {
        // Apple Silicon uses F0Md, F1Md (1 byte, ui8)
        let isAppleSilicon = readKey("FS! ") == nil
        
        if isAppleSilicon {
            let numFans = getFanCount()
            var success = true
            for i in 0..<numFans {
                // Check if this fan is included in the bitmask
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
            // Intel Macs use FS! (2 bytes)
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
        
        // Find expected data size
        var inputInfo = SMCParamStruct()
        inputInfo.key = key
        inputInfo.data8 = 9 // kSMCGetKeyInfo
        guard callDriver(&inputInfo) else { return false }
        
        let dataSize = inputInfo.keyInfo.dataSize
        var smcBytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        
        if dataSize == 4 {
            // Probably Apple Silicon `flt `
            // Apple SMC `flt ` format is usually standard IEEE 754 float
            var f = speed
            withUnsafeBytes(of: &f) { buffer in
                smcBytes.0 = buffer[0]
                smcBytes.1 = buffer[1]
                smcBytes.2 = buffer[2]
                smcBytes.3 = buffer[3]
            }
        } else {
            // Intel `fpe2` format (2 bytes)
            let fpe2Bytes = toFPE2(speed)
            smcBytes.0 = fpe2Bytes.0
            smcBytes.1 = fpe2Bytes.1
        }
        
        // Write the Key Value
        var inputWrite = SMCParamStruct()
        inputWrite.key = key
        inputWrite.bytes = smcBytes
        inputWrite.keyInfo = inputInfo.keyInfo
        inputWrite.keyInfo.dataSize = dataSize
        inputWrite.data8 = 6 // kSMCWriteKey
        
        return callDriver(&inputWrite)
    }
    
    // Enable/Disable battery charging or set charging limit
    func setBatteryChargeLimit(_ limit: Int, active: Bool) -> Bool {
        let isAppleSilicon = readKey("FS! ") == nil
        
        if isAppleSilicon {
            // Apple Silicon (M1/M2/M3) uses CHWA key (1 byte)
            // 01 = Enable 80% charge limit
            // 00 = Disable limit (charge to 100%)
            let key = "CHWA"
            var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            bytes.0 = active ? 1 : 0
            return writeKey(key, bytes: bytes, size: 1)
        } else {
            // Intel Macs use BCLM key (1 byte) representing percentage
            let key = "BCLM"
            var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                   0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            bytes.0 = active ? UInt8(limit) : 100
            return writeKey(key, bytes: bytes, size: 1)
        }
    }
    
    // Read current battery charge limit setting
    func getBatteryChargeLimit() -> (limit: Int, active: Bool) {
        let isAppleSilicon = readKey("FS! ") == nil
        
        if isAppleSilicon {
            if let bytes = readKey("CHWA") {
                let enabled = bytes.0 != 0
                return (limit: 80, active: enabled)
            }
            return (limit: 80, active: false)
        } else {
            if let bytes = readKey("BCLM") {
                let val = Int(bytes.0)
                let active = val < 100
                return (limit: val, active: active)
            }
            return (limit: 80, active: false)
        }
    }
}
