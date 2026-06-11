import Foundation

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        print("Usage: smchelper <manual|speed|charge|readcharge|power|sleep|smart|optimize> <params...>")
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
        
    } else if command == "readcharge" {
        let current = smc.getBatteryChargeLimit()
        print("\(current.limit) \(current.active ? 1 : 0)")
        
    } else if command == "power" {
        guard args.count >= 4 else {
            print("ERROR: Missing arguments for power. Usage: smchelper power <b|c|a> <0|1|2>")
            exit(1)
        }
        let mode = args[2] // "b", "c" or "a"
        let policy = Int(args[3]) ?? 1
        
        let flag: String
        if mode == "b" {
            flag = "-b"
        } else if mode == "c" {
            flag = "-c"
        } else {
            flag = "-a"
        }
        
        // policy: 
        // 0: Eco (lowpowermode = 1, highpower = 0)
        // 1: Balanced (lowpowermode = 0, highpower = 0)
        // 2: Turbo (lowpowermode = 0, highpower = 1)
        let lpm = (policy == 0) ? 1 : 0
        let hp = (policy == 2) ? 1 : 0
        
        // 1. 设置 lowpowermode
        let task1 = Process()
        task1.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task1.arguments = [flag, "lowpowermode", String(lpm)]
        
        // 2. 设置 highpower (用 try? 运行，以兼容不支持 high功率模式的机型)
        let task2 = Process()
        task2.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task2.arguments = [flag, "highpower", String(hp)]
        
        do {
            try task1.run()
            task1.waitUntilExit()
            let status1 = task1.terminationStatus
            
            try? task2.run()
            task2.waitUntilExit()
            
            if status1 == 0 {
                print("OK")
            } else {
                print("ERROR")
            }
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
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-b", "displaysleep", String(minutes)]
        do {
            try task.run()
            task.waitUntilExit()
            print("OK")
        } catch {
            print("ERROR")
        }
    } else if command == "smart" {
        let paths = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/usr/bin/smartctl"]
        var smartctlPath = ""
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                smartctlPath = path
                break
            }
        }
        
        if smartctlPath.isEmpty {
            print("ERROR: smartctl not installed")
            exit(1)
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: smartctlPath)
        task.arguments = ["-a", "-j", "/dev/disk0"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print(output)
            } else {
                print("ERROR: Failed to read smartctl output")
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
    } else if command == "optimize" {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["apfs", "updatePreboot", "/"]
        
        do {
            try task.run()
            task.waitUntilExit()
            let status = task.terminationStatus
            if status == 0 {
                print("OPTIMIZE_OK")
            } else {
                print("ERROR: diskutil exit code \(status)")
            }
        } catch {
            print("ERROR: \(error.localizedDescription)")
        }
    } else if command == "speedlimit" {
        guard args.count >= 3 else {
            print("ERROR: Missing arguments for speedlimit. Usage: smchelper speedlimit <percent>")
            exit(1)
        }
        let rawPercent = Int(args[2]) ?? 100
        let percent = min(max(rawPercent, 10), 100)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-a", "speedlimit", String(percent)]
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
