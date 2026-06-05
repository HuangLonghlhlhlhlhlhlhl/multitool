import Foundation
import IOKit
import CoreGraphics

class DDCCIController {
    static let shared = DDCCIController()
    
    // Private DisplayServices symbols for Apple/Internal displays
    private typealias GetBrightnessType = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessType = @convention(c) (CGDirectDisplayID, Float) -> Int32
    
    // IOAVService symbols for Apple Silicon DDC/CI control
    private typealias IOAVServiceCreateWithDisplayIDType = @convention(c) (CGDirectDisplayID) -> Unmanaged<AnyObject>?
    private typealias IOAVServiceWriteI2CType = @convention(c) (AnyObject, UInt32, UInt32, UnsafePointer<UInt8>, UInt32) -> Int32
    
    private var getBrightnessSym: GetBrightnessType?
    private var setBrightnessSym: SetBrightnessType?
    private var ioavServiceCreateSym: IOAVServiceCreateWithDisplayIDType?
    private var ioavServiceWriteI2CSym: IOAVServiceWriteI2CType?
    
    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        if let handle = handle {
            if let getSym = dlsym(handle, "DisplayServicesGetLinearBrightness") {
                getBrightnessSym = unsafeBitCast(getSym, to: GetBrightnessType.self)
            }
            if let setSym = dlsym(handle, "DisplayServicesSetLinearBrightness") {
                setBrightnessSym = unsafeBitCast(setSym, to: SetBrightnessType.self)
            }
            
            // Apple Silicon DDC/CI support via IOAVService private APIs
            if let createSym = dlsym(handle, "IOAVServiceCreateWithDisplayID") {
                ioavServiceCreateSym = unsafeBitCast(createSym, to: IOAVServiceCreateWithDisplayIDType.self)
            }
            if let writeSym = dlsym(handle, "IOAVServiceWriteI2C") {
                ioavServiceWriteI2CSym = unsafeBitCast(writeSym, to: IOAVServiceWriteI2CType.self)
            }
        }
    }
    
    // Struct representing an active display
    struct DisplayInfo: Identifiable {
        var id: CGDirectDisplayID
        var name: String
        var isBuiltin: Bool
    }
    
    // Get all active screens
    func getScreens() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var activeDisplays = Array(repeating: CGDirectDisplayID(0), count: Int(maxDisplays))
        
        let result = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard result == .success else { return [] }
        
        var list: [DisplayInfo] = []
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            
            var name = isBuiltin ? "内置视网膜显示器" : "外接 DDC 显示器"
            if let info = getDisplayName(displayID) {
                name = info
            }
            list.append(DisplayInfo(id: displayID, name: name, isBuiltin: isBuiltin))
        }
        return list
    }
    
    private func getDisplayServicePort(displayID: CGDirectDisplayID) -> io_service_t {
        var service: io_service_t = 0
        let matchingDict = IOServiceMatching("IODisplayConnect")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if kr == KERN_SUCCESS {
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                var info: Unmanaged<CFMutableDictionary>?
                let entryKr = IORegistryEntryCreateCFProperties(entry, &info, kCFAllocatorDefault, 0)
                if entryKr == KERN_SUCCESS, let dict = info?.takeRetainedValue() as? [String: Any] {
                    let vendor = CGDisplayVendorNumber(displayID)
                    let product = CGDisplayModelNumber(displayID)
                    
                    if let regVendor = dict["DisplayVendorID"] as? UInt32,
                       let regProduct = dict["DisplayProductID"] as? UInt32 {
                        if regVendor == vendor && regProduct == product {
                            service = entry
                            break
                        }
                    }
                }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        // Apple Silicon matching fallback: AppleCLCD2
        if service == 0 {
            let armMatching = IOServiceMatching("AppleCLCD2")
            var armIterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, armMatching, &armIterator) == KERN_SUCCESS {
                var entry = IOIteratorNext(armIterator)
                while entry != 0 {
                    var info: Unmanaged<CFMutableDictionary>?
                    let entryKr = IORegistryEntryCreateCFProperties(entry, &info, kCFAllocatorDefault, 0)
                    if entryKr == KERN_SUCCESS, let dict = info?.takeRetainedValue() as? [String: Any] {
                        let vendor = CGDisplayVendorNumber(displayID)
                        let product = CGDisplayModelNumber(displayID)
                        
                        if let regVendor = dict["DisplayVendorID"] as? UInt32,
                           let regProduct = dict["DisplayProductID"] as? UInt32 {
                            if regVendor == vendor && regProduct == product {
                                service = entry
                                break
                            }
                        }
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(armIterator)
                }
                IOObjectRelease(armIterator)
            }
        }
        
        return service
    }
    
    private func getDisplayName(_ displayID: CGDirectDisplayID) -> String? {
        let service = getDisplayServicePort(displayID: displayID)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        
        var info: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &info, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = info?.takeRetainedValue() as? [String: Any] else { return nil }
        
        if let displayAttrs = dict["DisplayAttributes"] as? [String: Any],
           let productNames = displayAttrs["DisplayProductName"] as? [String: Any],
           let name = productNames.values.first as? String {
            return name
        }
        return nil
    }
    
    // Read brightness for a display (built-in or Apple-made display)
    func getBrightness(for displayID: CGDirectDisplayID) -> Float {
        if CGDisplayIsBuiltin(displayID) != 0, let getVal = getBrightnessSym {
            var val: Float = 0.5
            let res = getVal(displayID, &val)
            if res == 0 { return val }
        }
        return 0.5
    }
    
    // Set brightness (DDC/CI VCP 0x10 or DisplayServices)
    func setBrightness(for displayID: CGDirectDisplayID, value: Float) {
        if CGDisplayIsBuiltin(displayID) != 0 {
            if let setVal = setBrightnessSym {
                let _ = setVal(displayID, value)
            }
        } else {
            // Send DDC/CI brightness packet (VCP code 0x10)
            let vcpCode: UInt8 = 0x10
            let targetVal = UInt16(min(100.0, max(0.0, value * 100.0)))
            sendDDCCIPacket(displayID: displayID, vcp: vcpCode, value: targetVal)
        }
    }
    
    // Set volume (DDC/CI VCP 0x62)
    func setVolume(for displayID: CGDirectDisplayID, value: Float) {
        if CGDisplayIsBuiltin(displayID) == 0 {
            let vcpCode: UInt8 = 0x62
            let targetVal = UInt16(min(100.0, max(0.0, value * 100.0)))
            sendDDCCIPacket(displayID: displayID, vcp: vcpCode, value: targetVal)
        }
    }
    
    // Core DDC/CI frame transmission over I2C
    private func sendDDCCIPacket(displayID: CGDirectDisplayID, vcp: UInt8, value: UInt16) {
        // 1. Try Apple Silicon IOAVService path first
        if sendAppleSiliconDDCCIPacket(displayID: displayID, vcp: vcp, value: value) {
            return
        }
        
        // 2. Fallback to Intel I2C path
        let service = getDisplayServicePort(displayID: displayID)
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        
        var bus: IOOptionBits = 0
        while bus < 10 {
            var interfaceService: io_service_t = 0
            let i2cResult = IOFBCopyI2CInterfaceForBus(service, bus, &interfaceService)
            if i2cResult == KERN_SUCCESS && interfaceService != 0 {
                performI2CRequest(interfaceService: interfaceService, vcp: vcp, value: value)
                IOObjectRelease(interfaceService)
            }
            bus += 1
        }
    }
    
    private func sendAppleSiliconDDCCIPacket(displayID: CGDirectDisplayID, vcp: UInt8, value: UInt16) -> Bool {
        guard let createService = ioavServiceCreateSym, let writeI2C = ioavServiceWriteI2CSym else {
            return false
        }
        guard let serviceObj = createService(displayID) else {
            return false
        }
        let service = serviceObj.takeRetainedValue()
        
        var data = [UInt8](repeating: 0, count: 7)
        data[0] = 0x51 // Source address
        data[1] = 0x84 // Length of payload (4 bytes) | 0x80
        data[2] = 0x03 // Set Parameter command
        data[3] = vcp  // VCP Code
        data[4] = UInt8((value >> 8) & 0xFF) // High value byte
        data[5] = UInt8(value & 0xFF)        // Low value byte
        
        var checksum: UInt8 = 0x6E // Destination address (write address)
        for i in 0..<6 {
            checksum ^= data[i]
        }
        data[6] = checksum
        
        let res = writeI2C(service, 0x37, 0, &data, UInt32(data.count))
        return res == 0
    }
    
    private func performI2CRequest(interfaceService: io_service_t, vcp: UInt8, value: UInt16) {
        var request = IOI2CRequest()
        
        request.sendAddress = UInt32(0x37 << 1)
        request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        request.replyAddress = UInt32((0x37 << 1) | 1)
        request.replyTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        request.minReplyDelay = 10000 // 10ms
        
        var data = [UInt8](repeating: 0, count: 7)
        data[0] = 0x51 // Source address
        data[1] = 0x84 // Length of payload (4 bytes) | 0x80
        data[2] = 0x03 // Set Parameter command
        data[3] = vcp  // VCP Code
        data[4] = UInt8((value >> 8) & 0xFF) // High value byte
        data[5] = UInt8(value & 0xFF)        // Low value byte
        
        var checksum: UInt8 = 0x6E // Destination address (write address)
        for i in 0..<6 {
            checksum ^= data[i]
        }
        data[6] = checksum
        
        data.withUnsafeMutableBufferPointer { buffer in
            request.sendBuffer = vm_address_t(bitPattern: buffer.baseAddress)
            request.sendBytes = UInt32(buffer.count)
            request.replyBuffer = 0
            request.replyBytes = 0
            
            var connect: IOI2CConnectRef? = nil
            let openResult = IOI2CInterfaceOpen(interfaceService, 0, &connect)
            if openResult == KERN_SUCCESS, let connect = connect {
                let _ = IOI2CSendRequest(connect, 0, &request)
                IOI2CInterfaceClose(connect, 0)
            }
        }
    }
}
