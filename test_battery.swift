import Foundation

@main
struct App {
    static func main() {
        let smc = SMCController()
        smc.doOpen()
        defer { smc.doClose() }

        let keys = ["BCLM", "CHWA", "CH0B", "CH0C", "CH1C", "CH0A", "CH0b", "CH0c"]
        print("SMC Battery Keys Diagnostics:")
        for key in keys {
            if let bytes = smc.readKey(key) {
                print("  \(key): [\(bytes.0), \(bytes.1), \(bytes.2), \(bytes.3)]")
            } else {
                print("  \(key): NOT SUPPORTED or READ FAILED")
            }
        }
        
        let limit = smc.getBatteryChargeLimit()
        print("Fallback charge limit reading: \(limit.limit)%, active: \(limit.active)")
    }
}
