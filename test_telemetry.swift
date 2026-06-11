import Foundation
import CoreGraphics
import IOKit

func getRAMUsage() -> Double {
    var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    var stats = vm_statistics64()
    let hostPort = mach_host_self()
    
    let result = withUnsafeMutablePointer(to: &stats) { statsPtr in
        statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
            host_statistics64(hostPort, HOST_VM_INFO64, reboundPtr, &size)
        }
    }
    
    guard result == KERN_SUCCESS else { return 0.0 }
    
    var pageSize: vm_size_t = 4096
    host_page_size(hostPort, &pageSize)
    
    let active = Double(stats.active_count) * Double(pageSize)
    let wire = Double(stats.wire_count) * Double(pageSize)
    let inactive = Double(stats.inactive_count) * Double(pageSize)
    let free = Double(stats.free_count) * Double(pageSize)
    
    let used = active + wire
    let total = used + inactive + free
    
    if total > 0 {
        return (used / total) * 100.0
    }
    return 0.0
}

func getSSDUsage() -> Double {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory())
    do {
        let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        if let totalInt = values.volumeTotalCapacity, let available = values.volumeAvailableCapacityForImportantUsage, totalInt > 0 {
            let total = Int64(totalInt)
            let used = total - available
            return (Double(used) / Double(total)) * 100.0
        }
    } catch {}
    return 0.0
}

print("RAM Usage: \(getRAMUsage())%")
print("SSD Usage (Finder Volume Capacity): \(getSSDUsage())%")

