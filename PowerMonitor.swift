import Foundation
import IOKit

public class PowerMonitor {
    
    public struct PowerStats {
        public var isConnected: Bool = false
        public var adapterVoltage: Double = 0.0 // Volts (V)
        public var adapterCurrent: Double = 0.0 // Amperes (A)
        public var adapterPower: Double = 0.0   // Watts (W) (Negotiated Charger Power)
        
        public var batteryVoltage: Double = 0.0 // Volts (V)
        public var batteryCurrent: Double = 0.0 // Amperes (A) (positive = charging, negative = discharging)
        public var batteryPower: Double = 0.0   // Watts (W) (Current Charge or Load Power)
        public var isCharging: Bool = false
        public var stateOfCharge: Int = 0       // Percentage (%)
        public var batteryCycleCount: Int = 0
        public var batteryHealthPercent: Int = 100
        public var adapterName: String = "Unknown"
        
        // Expanded Battery telemetry
        public var batteryTemperature: Double = 0.0 // Celsius (°C)
        public var timeRemaining: Int = 0           // Minutes
        public var avgTimeToEmpty: Int = 0          // Minutes
        public var avgTimeToFull: Int = 0           // Minutes
        public var hasBattery: Bool = false
        
        // Dynamic port diagnostic fields
        public var activePortIndex: Int = -1     // -1 = disconnected, 0 = L1, 1 = L2, 2 = R1, 3 = R2
        public var hasRightPorts: Bool = false
        public var rightPortCount: Int = 2       // 0, 1, or 2 ports on the right
        public var hardwareModel: String = ""
        public var friendlyModelName: String = ""
        public var currentCapacity: Double = 0.0 // mAh
        public var maxCapacity: Double = 0.0     // mAh
        public var designCapacity: Double = 0.0  // mAh
        public var usbStorageDevices: [USBStorageInfo] = []
    }
    
    private static var cachedUSBDevices: [USBStorageInfo] = []
    private static var lastUSBCacheTime: Date = Date.distantPast
    
    private static func doubleValue(for key: String, in dict: [String: Any]) -> Double? {
        if let val = dict[key] as? Double {
            return val
        }
        if let val = dict[key] as? Int {
            return Double(val)
        }
        if let val = dict[key] as? Int64 {
            return Double(val)
        }
        if let nsNum = dict[key] as? NSNumber {
            return nsNum.doubleValue
        }
        return nil
    }
    
    private static func intValue(for key: String, in dict: [String: Any]) -> Int? {
        if let val = dict[key] as? Int {
            return val
        }
        if let val = dict[key] as? Double {
            return Int(val)
        }
        if let val = dict[key] as? Int64 {
            return Int(val)
        }
        if let nsNum = dict[key] as? NSNumber {
            return nsNum.intValue
        }
        return nil
    }

    public static func getPowerStats() -> PowerStats {
        var stats = PowerStats()
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            // Safe fallbacks for Desktop Macs or VMs with no internal battery
            stats.isConnected = true
            stats.adapterPower = 0.0
            stats.hasBattery = false
            stats.usbStorageDevices = getUSBDevicesCached()
            return stats
        }
        
        stats.hasBattery = true
        
        defer {
            IOObjectRelease(service)
        }
        
        var props: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        
        if result == kIOReturnSuccess, let dict = props?.takeRetainedValue() as? [String: Any] {
            // 1. Basic battery voltage & current
            if let voltage = doubleValue(for: "Voltage", in: dict) {
                stats.batteryVoltage = voltage / 1000.0 // mV to V
            }
            if let amperage = doubleValue(for: "Amperage", in: dict) {
                stats.batteryCurrent = amperage / 1000.0 // mA to A
                stats.batteryPower = abs(stats.batteryVoltage * stats.batteryCurrent)
            }
            if let isCharging = dict["IsCharging"] as? Bool {
                stats.isCharging = isCharging
            }
            
            // State of Charge: Precise Calculation
            let charge = doubleValue(for: "CurrentCapacity", in: dict) ?? 0.0
            let maxCap = doubleValue(for: "MaxCapacity", in: dict) ?? 0.0
            if maxCap > 0 {
                if maxCap <= 100.0 {
                    stats.stateOfCharge = Int(charge)
                } else {
                    stats.stateOfCharge = Int(round((charge / maxCap) * 100.0))
                }
            }
            
            if let cycles = dict["CycleCount"] as? Int {
                stats.batteryCycleCount = cycles
            }
            
            // 2. TRUE Battery Health Calculation (Current Actual Capacity vs Design Capacity)
            let rawMax = doubleValue(for: "AppleRawMaxCapacity", in: dict) 
                       ?? doubleValue(for: "NominalChargeCapacity", in: dict) 
                       ?? 0.0
            let designCap = doubleValue(for: "DesignCapacity", in: dict) ?? 0.0
            
            if rawMax > 0 && designCap > 0 {
                stats.batteryHealthPercent = Int(round((rawMax / designCap) * 100.0))
                stats.batteryHealthPercent = max(0, min(100, stats.batteryHealthPercent))
            } else {
                if let maxCapPercent = dict["MaxCapacityPercent"] as? Int {
                    stats.batteryHealthPercent = maxCapPercent
                } else if let maxCapPercent = dict["MaximumCapacityPercent"] as? Int {
                    stats.batteryHealthPercent = maxCapPercent
                } else {
                    stats.batteryHealthPercent = 100
                }
            }
            
            let rawCharge = doubleValue(for: "AppleRawCurrentCapacity", in: dict)
                       ?? (maxCap <= 100.0 ? (charge / 100.0) * rawMax : charge)
            stats.currentCapacity = rawCharge
            stats.maxCapacity = rawMax
            stats.designCapacity = designCap
            
            // 3. External Charger Connection
            if let extConnected = dict["ExternalConnected"] as? Bool {
                stats.isConnected = extConnected
            }
            
            // Expanded Battery stats (Temperature, Runtimes)
            if let temp = doubleValue(for: "Temperature", in: dict) {
                stats.batteryTemperature = temp / 100.0
            }
            if let timeRem = dict["TimeRemaining"] as? Int {
                stats.timeRemaining = timeRem
            }
            if let timeEmpty = dict["AvgTimeToEmpty"] as? Int {
                stats.avgTimeToEmpty = timeEmpty
            }
            if let timeFull = dict["AvgTimeToFull"] as? Int {
                stats.avgTimeToFull = timeFull
            }
            
            // 4. Charger adapter details (Voltage, Amperage, Watts)
            if let adapterDetails = dict["AdapterDetails"] as? [String: Any] {
                parseAdapterDict(adapterDetails, stats: &stats)
            } else if let rawDetailsList = dict["AppleRawAdapterDetails"] as? [[String: Any]], !rawDetailsList.isEmpty {
                parseAdapterDict(rawDetailsList[0], stats: &stats)
            }
            
            // 5. Dynamic active USB-C port detection from registry (Factual Real-Time Power Evaluation)
            let rawModel = getHardwareModel()
            stats.hardwareModel = rawModel
            stats.friendlyModelName = getFriendlyModelName(model: rawModel)
            
            if let portInfo = dict["PortControllerInfo"] as? [[String: Any]] {
                stats.rightPortCount = max(0, portInfo.count - 2)
                stats.hasRightPorts = stats.rightPortCount > 0
                
                if stats.isConnected {
                    for (index, port) in portInfo.enumerated() {
                        let maxPower = intValue(for: "PortControllerMaxPower", in: port)
                                    ?? intValue(for: "PortMaxPower", in: port)
                                    ?? intValue(for: "MaxPower", in: port)
                                    ?? 0
                        let dnSt = intValue(for: "PortControllerDnSt", in: port)
                                ?? intValue(for: "PortDnSt", in: port)
                                ?? intValue(for: "DnSt", in: port)
                                ?? 0
                        
                        // Detect port actively negotiating power or hosting downstream delivery
                        if maxPower > 0 || dnSt > 0 {
                            stats.activePortIndex = index
                            break
                        }
                    }
                }
            } else {
                // Fallback using hardware model
                let model = stats.hardwareModel
                if model.contains("MacBookAir") || model == "MacBookPro17,1" {
                    stats.rightPortCount = 0
                } else if model.contains("MacBookPro") {
                    let components = model.replacingOccurrences(of: "MacBookPro", with: "")
                                          .split(separator: ",")
                    if let first = components.first, let major = Int(first), major >= 18 {
                        stats.rightPortCount = 1
                    } else {
                        stats.rightPortCount = 2
                    }
                } else {
                    stats.rightPortCount = 0
                }
                stats.hasRightPorts = stats.rightPortCount > 0
            }
            
            if stats.isConnected {
                // Smart MagSafe detection
                let adapterNameLower = stats.adapterName.lowercased()
                let isMagSafe = adapterNameLower.contains("magsafe")
                
                if isMagSafe {
                    stats.activePortIndex = 99 // 99 represents MagSafe!
                } else if stats.activePortIndex == -1 {
                    stats.activePortIndex = 0 // Fallback to USB-C Port L1 (index 0)
                }
            }
        }
        
        stats.usbStorageDevices = getUSBDevicesCached()
        return stats
    }
    
    private static func parseAdapterDict(_ dict: [String: Any], stats: inout PowerStats) {
        if let adv = doubleValue(for: "AdapterVoltage", in: dict) {
            stats.adapterVoltage = adv / 1000.0 // mV to V
        } else if let adv = doubleValue(for: "Voltage", in: dict) {
            stats.adapterVoltage = adv / 1000.0
        }
        
        if let adc = doubleValue(for: "Current", in: dict) {
            stats.adapterCurrent = adc / 1000.0 // mA to A
        } else if let adc = doubleValue(for: "Amperage", in: dict) {
            stats.adapterCurrent = adc / 1000.0
        }
        
        if let adw = doubleValue(for: "Watts", in: dict) {
            stats.adapterPower = adw // in Watts
        }
        
        if let name = dict["Name"] as? String {
            stats.adapterName = name
        } else if let model = dict["Model"] as? String {
            stats.adapterName = model
        } else {
            stats.adapterName = stats.adapterPower > 0 ? "\(Int(stats.adapterPower))W USB-C Charger" : "USB-C Power"
        }
        
        if stats.adapterPower > 0 && stats.adapterVoltage == 0 {
            stats.adapterVoltage = 20.0
            stats.adapterCurrent = stats.adapterPower / stats.adapterVoltage
        }
    }
    
    static func getHardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    static func getFriendlyModelName(model: String) -> String {
        let models: [String: String] = [
            "MacBookPro18,1": "MacBook Pro (16\", 2021, M1 Pro)",
            "MacBookPro18,2": "MacBook Pro (16\", 2021, M1 Max)",
            "MacBookPro18,3": "MacBook Pro (14\", 2021, M1 Pro)",
            "MacBookPro18,4": "MacBook Pro (14\", 2021, M1 Max)",
            "MacBookPro18,9": "MacBook Pro (14\", 2023, M2 Pro)",
            "MacBookPro18,10": "MacBook Pro (14\", 2023, M2 Max)",
            "MacBookPro18,11": "MacBook Pro (16\", 2023, M2 Pro)",
            "MacBookPro18,12": "MacBook Pro (16\", 2023, M2 Max)",
            "MacBookPro17,1": "MacBook Pro (13\", M1, 2020)",
            "MacBookAir10,1": "MacBook Air (M1, 2020)",
            "MacBookAir14,2": "MacBook Air (13\", M2, 2022)"
        ]
        
        if let friendly = models[model] {
            return friendly
        }
        
        if model.contains("MacBookPro") {
            return "MacBook Pro (\(model))"
        } else if model.contains("MacBookAir") {
            return "MacBook Air (\(model))"
        } else if model.contains("Macmini") {
            return "Mac mini (\(model))"
        } else if model.contains("MacStudio") {
            return "Mac Studio (\(model))"
        }
        return model
    }
    
    public struct USBStorageInfo: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let speed: String       // e.g. "USB 3.0 (SuperSpeed 5Gbps)"
        public let voltage: Double     // 5.0 V
        public let current: Double     // mA
        public let isStorage: Bool
        
        public init(id: UUID = UUID(), name: String, speed: String, voltage: Double, current: Double, isStorage: Bool) {
            self.id = id
            self.name = name
            self.speed = speed
            self.voltage = voltage
            self.current = current
            self.isStorage = isStorage
        }
    }
    
    private static func getUSBDevicesCached() -> [USBStorageInfo] {
        let now = Date()
        if now.timeIntervalSince(lastUSBCacheTime) >= 10.0 || lastUSBCacheTime == Date.distantPast {
            cachedUSBDevices = getConnectedUSBDevices()
            lastUSBCacheTime = now
        }
        return cachedUSBDevices
    }
    
    static func getConnectedUSBDevices() -> [USBStorageInfo] {
        var list: [USBStorageInfo] = []
        
        let matchingDict = IOServiceMatching("IOUSBHostDevice")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if kr == KERN_SUCCESS {
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                var info: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &info, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = info?.takeRetainedValue() as? [String: Any] {
                    
                    let name = dict["USB Product Name"] as? String 
                            ?? dict["productName"] as? String 
                            ?? dict["kUSBProductString"] as? String
                            ?? "Generic USB Device"
                    
                    let vendorID = dict["idVendor"] as? Int ?? dict["vendorID"] as? Int ?? 0
                    let lowerName = name.lowercased()
                    // Filter out internal Apple devices and generic hubs
                    if vendorID == 0x05ac || lowerName.contains("hub") || lowerName.contains("controller") || lowerName.contains("root") {
                        IOObjectRelease(entry)
                        entry = IOIteratorNext(iterator)
                        continue
                    }
                    
                    var isStorage = false
                    if let devClass = dict["bDeviceClass"] as? Int, devClass == 8 {
                        isStorage = true
                    }
                    
                    if !isStorage {
                        var childIterator: io_iterator_t = 0
                        if IORegistryEntryGetChildIterator(entry, kIOServicePlane, &childIterator) == KERN_SUCCESS {
                            var child = IOIteratorNext(childIterator)
                            while child != 0 {
                                var childInfo: Unmanaged<CFMutableDictionary>?
                                if IORegistryEntryCreateCFProperties(child, &childInfo, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                                   let childDict = childInfo?.takeRetainedValue() as? [String: Any] {
                                    if let intfClass = childDict["bInterfaceClass"] as? Int, intfClass == 8 {
                                        isStorage = true
                                        IOObjectRelease(child)
                                        break
                                    }
                                }
                                IOObjectRelease(child)
                                child = IOIteratorNext(childIterator)
                            }
                            IOObjectRelease(childIterator)
                        }
                    }
                    
                    if !isStorage {
                        let keywords = ["storage", "disk", "drive", "flash", "sandisk", "samsung", "crucial", "kingston", "wd", "seagate", "toshiba", "lexar", "card reader", "nvme"]
                        for kw in keywords {
                            if lowerName.contains(kw) {
                                isStorage = true
                                break
                            }
                        }
                    }
                    
                    var speedStr = "USB 2.0"
                    let speedVal = dict["Device Speed"] as? Int ?? dict["speed"] as? Int ?? 2
                    switch speedVal {
                    case 0: speedStr = "USB 1.1 (Low Speed 1.5Mbps)"
                    case 1: speedStr = "USB 1.1 (Full Speed 12Mbps)"
                    case 2: speedStr = "USB 2.0 (High Speed 480Mbps)"
                    case 3: speedStr = "USB 3.0 (SuperSpeed 5Gbps)"
                    case 4: speedStr = "USB 3.1/3.2 (SuperSpeed+ 10Gbps)"
                    default:
                        if speedVal > 4 {
                            speedStr = "USB4/TB (SuperSpeed+ \(speedVal)0Gbps)"
                        } else {
                            speedStr = "USB 2.0"
                        }
                    }
                    
                    var currentmA = 500.0
                    if let powerRequested = dict["Requested Power"] as? Int {
                        currentmA = Double(powerRequested)
                    } else if let powerRequested = dict["Requested Power"] as? NSNumber {
                        currentmA = powerRequested.doubleValue
                    } else if let bMaxPower = dict["bMaxPower"] as? Int {
                        currentmA = Double(bMaxPower * 2)
                    }
                    
                    let voltage = 5.0
                    
                    list.append(USBStorageInfo(name: name, speed: speedStr, voltage: voltage, current: currentmA, isStorage: isStorage))
                }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        return list
    }
}
