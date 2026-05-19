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
        let rawActive = Int(args[2]) ?? 0
        let rawBitmask = Int(args[3]) ?? 3
        
        // Strict boundary validation
        let active = min(max(rawActive, 0), 1)
        let bitmask = UInt16(min(max(rawBitmask, 0), 7))
        
        let ok = smc.setFanManual(active != 0, fanBitmask: bitmask)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "speed" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for speed. Usage: smchelper speed <fanIndex> <speed>")
            exit(1)
        }
        let rawFanIndex = Int(args[2]) ?? 0
        let rawSpeed = Float(args[3]) ?? 0
        
        // Strict boundary validation
        let fanIndex = min(max(rawFanIndex, 0), 3)
        // Accept 0 (turn off / silent idle on M1) or standard hardware range 1000...7200 RPM
        let speed: Float
        if rawSpeed <= 0.1 {
            speed = 0.0
        } else {
            speed = min(max(rawSpeed, 1000.0), 7200.0)
        }
        
        let ok = smc.setFanSpeed(fanIndex, speed: speed)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "charge" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for charge. Usage: smchelper charge <limit> <0|1>")
            exit(1)
        }
        let rawLimit = Int(args[2]) ?? 80
        let rawActive = Int(args[3]) ?? 0
        
        // Strict boundary validation: SMC BCLM threshold accepts 50% to 100%
        let limit = min(max(rawLimit, 50), 100)
        let active = min(max(rawActive, 0), 1)
        
        let ok = smc.setBatteryChargeLimit(limit, active: active != 0)
        print(ok ? "OK" : "ERROR")
        
    } else if command == "power" {
        guard args.count >= 3 else {
            print("ERROR: Missing arguments for power. Usage: smchelper power <0|1>")
            exit(1)
        }
        let rawActive = Int(args[2]) ?? 0
        
        // Strict boundary validation
        let active = min(max(rawActive, 0), 1)
        
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
        let rawMinutes = Int(args[2]) ?? 10
        
        // Strict boundary validation: 0 (never sleep) or 1...180 minutes
        let minutes = min(max(rawMinutes, 0), 180)
        
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
