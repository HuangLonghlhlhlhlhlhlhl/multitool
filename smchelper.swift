import Foundation

func main() {
    let args = CommandLine.arguments
    guard args.count >= 4 else {
        print("Usage: smchelper <manual|speed|charge> <param1> <param2>")
        exit(1)
    }
    
    let command = args[1]
    let smc = SMCController()
    smc.doOpen()
    
    if command == "manual" {
        let active  = Int(args[2]) ?? 0
        let bitmask = UInt16(args[3]) ?? 3
        let ok = smc.setFanManual(active != 0, fanBitmask: bitmask)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "speed" {
        let fanIndex = Int(args[2]) ?? 0
        let speed    = Float(args[3]) ?? 0
        let ok = smc.setFanSpeed(fanIndex, speed: speed)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "charge" {
        let limit  = Int(args[2]) ?? 80
        let active = (Int(args[3]) ?? 0) != 0
        let ok = smc.setBatteryChargeLimit(limit, active: active)
        print(ok ? "OK" : "ERROR")
    }
    
    smc.doClose()
}

main()
