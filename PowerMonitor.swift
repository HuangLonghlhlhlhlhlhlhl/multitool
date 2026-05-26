import Foundation
import IOKit

class PowerMonitor {
    
    struct PowerStats {
        var isConnected: Bool = false
        var adapterVoltage: Double = 0.0 // Volts (V)
        var adapterCurrent: Double = 0.0 // Amperes (A)
        var adapterPower: Double = 0.0   // Watts (W) (Negotiated Charger Power)
        
        var batteryVoltage: Double = 0.0 // Volts (V)
        var batteryCurrent: Double = 0.0 // Amperes (A) (positive = charging, negative = discharging)
        var batteryPower: Double = 0.0   // Watts (W) (Current Charge or Load Power)
        var isCharging: Bool = false
        var stateOfCharge: Int = 0       // Percentage (%)
        var batteryCycleCount: Int = 0
        var batteryHealthPercent: Int = 100
        var adapterName: String = "Unknown"
        
        // Expanded Battery telemetry
        var batteryTemperature: Double = 0.0 // Celsius (°C)
        var timeRemaining: Int = 0           // Minutes
        var avgTimeToEmpty: Int = 0          // Minutes
        var avgTimeToFull: Int = 0           // Minutes
        var hasBattery: Bool = false
        
        // Dynamic port diagnostic fields
        var activePortIndex: Int = -1     // -1 = disconnected, 0 = L1, 1 = L2, 2 = R1, 3 = R2
        var hasRightPorts: Bool = false
        var rightPortCount: Int = 2       // 0, 1, or 2 ports on the right
        var hardwareModel: String = ""
        var friendlyModelName: String = ""
        var currentCapacity: Double = 0.0 // mAh
        var maxCapacity: Double = 0.0     // mAh
        var designCapacity: Double = 0.0  // mAh
    }
    
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

    static func getPowerStats() -> PowerStats {
        var stats = PowerStats()
        
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            // Safe fallbacks for Desktop Macs or VMs with no internal battery
            stats.isConnected = true
            stats.adapterPower = 0.0
            stats.hasBattery = false
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
            
            stats.currentCapacity = charge
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
                        let maxPower = port["PortControllerMaxPower"] as? Int ?? 0
                        let dnSt = port["PortControllerDnSt"] as? Int ?? 0
                        
                        // Detect port actively negotiating power or hosting downstream delivery
                        if maxPower > 0 || dnSt > 0 {
                            stats.activePortIndex = index
                            break
                        }
                    }
                    
                    // Fallback to L1 if no port reported power contract but adapter is connected
                    if stats.activePortIndex == -1 && !portInfo.isEmpty {
                        stats.activePortIndex = 0
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
                
                if stats.isConnected {
                    stats.activePortIndex = 0
                }
            }
        }
        
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
}
