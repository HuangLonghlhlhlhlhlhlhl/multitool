import Foundation
import IOKit

class SSDMonitor {
    static let shared = SSDMonitor()
    
    struct SSDStats {
        var percentageUsed: Int = 0 // Wear level % (100 - Health)
        var healthPercent: Int = 100 // 100 - wear level
        var bytesWritten: UInt64 = 0 // Bytes written
        var bytesRead: UInt64 = 0 // Bytes read
        var temperature: Int = 0 // Temperature in C
        var modelName: String = "Apple NVMe SSD"
    }
    
    func getSSDStats() -> SSDStats {
        var stats = SSDStats()
        
        // Match AppleANS3NVMeController or fallback generic IOBlockStorageDevice
        let matchingDict = IOServiceMatching("AppleANS3NVMeController")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        
        guard service != 0 else {
            // Try fallback block storage
            let fallbackDict = IOServiceMatching("IOBlockStorageDevice")
            let fallbackService = IOServiceGetMatchingService(kIOMainPortDefault, fallbackDict)
            guard fallbackService != 0 else {
                // Try direct nvme controller fallback
                let genericDict = IOServiceMatching("IONVMeController")
                let genericService = IOServiceGetMatchingService(kIOMainPortDefault, genericDict)
                if genericService != 0 {
                    parseProperties(service: genericService, stats: &stats)
                    IOObjectRelease(genericService)
                }
                return stats
            }
            parseProperties(service: fallbackService, stats: &stats)
            IOObjectRelease(fallbackService)
            return stats
        }
        
        parseProperties(service: service, stats: &stats)
        IOObjectRelease(service)
        return stats
    }
    
    private func parseProperties(service: io_service_t, stats: inout SSDStats) {
        var props: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
        
        guard result == kIOReturnSuccess, let dict = props?.takeRetainedValue() as? [String: Any] else {
            return
        }
        
        // Decode wear level %
        if let percentageUsed = dict["PercentageUsed"] as? Int {
            stats.percentageUsed = percentageUsed
            stats.healthPercent = max(0, min(100, 100 - percentageUsed))
        } else if let percentageUsed = dict["PercentageUsed"] as? NSNumber {
            let val = percentageUsed.intValue
            stats.percentageUsed = val
            stats.healthPercent = max(0, min(100, 100 - val))
        } else if let smartDict = dict["SMART Data"] as? [String: Any], let percentageUsed = smartDict["PercentageUsed"] as? Int {
            stats.percentageUsed = percentageUsed
            stats.healthPercent = max(0, min(100, 100 - percentageUsed))
        } else {
            // Default estimation if missing
            stats.percentageUsed = 1 // 99% health
            stats.healthPercent = 99
        }
        
        // Data units written / read are usually in "DataUnitsWritten" or "DataUnitsRead". Each unit is 512,000 bytes (1000 sectors of 512 bytes).
        // Wait, standard NVMe spec says: Data Units Written: Contains the number of 512,000 byte data units written. (i.e. 1000 sectors of 512 bytes = 512,000 bytes? No, 1000 * 512 = 512,000 bytes)
        // Let's decode:
        if let written = dict["DataUnitsWritten"] as? UInt64 {
            stats.bytesWritten = written * 512000
        } else if let written = dict["DataUnitsWritten"] as? NSNumber {
            stats.bytesWritten = written.uint64Value * 512000
        } else if let smartDict = dict["SMART Data"] as? [String: Any], let written = smartDict["DataUnitsWritten"] as? UInt64 {
            stats.bytesWritten = written * 512000
        }
        
        if let read = dict["DataUnitsRead"] as? UInt64 {
            stats.bytesRead = read * 512000
        } else if let read = dict["DataUnitsRead"] as? NSNumber {
            stats.bytesRead = read.uint64Value * 512000
        } else if let smartDict = dict["SMART Data"] as? [String: Any], let read = smartDict["DataUnitsRead"] as? UInt64 {
            stats.bytesRead = read * 512000
        }
        
        // Temperature sanitization: support Kelvin, Celsius, and fallback to SMC
        var parsedTemp: Int? = nil
        if let tempRaw = dict["Temperature"] as? Int {
            parsedTemp = tempRaw
        } else if let tempRaw = dict["Temperature"] as? NSNumber {
            parsedTemp = tempRaw.intValue
        }
        
        if let temp = parsedTemp {
            if temp >= 250 && temp <= 373 {
                // Kelvin -> Celsius conversion
                stats.temperature = temp - 273
            } else if temp > 0 && temp < 150 {
                // Already in Celsius
                stats.temperature = temp
            } else {
                // Invalid reading, fallback to SMC
                stats.temperature = Int(SMCController.shared.getSSDTemperature())
            }
        } else {
            // Missing key, fallback to SMC
            stats.temperature = Int(SMCController.shared.getSSDTemperature())
        }
        
        if let model = dict["Product Name"] as? String {
            stats.modelName = model
        } else if let model = dict["ModelName"] as? String {
            stats.modelName = model
        } else if let model = dict["Model"] as? String {
            stats.modelName = model
        }
    }
}
