import Foundation

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        print("Usage: smchelper <manual|speed|charge|power|sleep> <params...>")
        exit(1)
    }
    
    let command = args[1]
    let smc = SMCController()
    smc.doOpen()
    
    if command == "manual" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for manual. Usage: smchelper manual <0|1> <bitmask>")
            exit(1)
        }
        let active  = Int(args[2]) ?? 0
        let bitmask = UInt16(args[3]) ?? 3
        let ok = smc.setFanManual(active != 0, fanBitmask: bitmask)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "speed" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for speed. Usage: smchelper speed <fanIndex> <speed>")
            exit(1)
        }
        let fanIndex = Int(args[2]) ?? 0
        let speed    = Float(args[3]) ?? 0
        let ok = smc.setFanSpeed(fanIndex, speed: speed)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "charge" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for charge. Usage: smchelper charge <limit> <0|1>")
            exit(1)
        }
        let limit  = Int(args[2]) ?? 80
        let active = (Int(args[3]) ?? 0) != 0
        let ok = smc.setBatteryChargeLimit(limit, active: active)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "power" {
        guard args.count >= 3 else {
            print("ERROR: Missing arguments for power. Usage: smchelper power <0|1>")
            exit(1)
        }
        let active = Int(args[2]) ?? 0
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-a", "lowpowermode", String(active)]
        do {
            try task.run()
            task.waitUntilExit()
            print("OK")
        } catch {
            print("ERROR")
        }
        
    } else if command == "sleep" {
        guard args.count >= 3 else {
            print("ERROR: Missing arguments for sleep. Usage: smchelper sleep <minutes>")
            exit(1)
        }
        let minutes = Int(args[2]) ?? 10
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-b", "displaysleep", String(minutes)]
        do {
            try task.run()
            task.waitUntilExit()
            print("OK")
        } catch {
            print("ERROR")
        }
    } else {
        print("ERROR: Unknown command \(command)")
        exit(1)
    }
    
    smc.doClose()
}

main()

