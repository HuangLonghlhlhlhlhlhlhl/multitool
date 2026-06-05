import Foundation
import CoreGraphics

typealias GetBrightnessType = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias SetBrightnessType = @convention(c) (CGDirectDisplayID, Float) -> Int32

let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
if let handle = handle {
    let getSymbol = dlsym(handle, "DisplayServicesGetLinearBrightness")
    let setSymbol = dlsym(handle, "DisplayServicesSetLinearBrightness")
    
    if let getSymbol = getSymbol, let setSymbol = setSymbol {
        let getBrightness = unsafeBitCast(getSymbol, to: GetBrightnessType.self)
        let setBrightness = unsafeBitCast(setSymbol, to: SetBrightnessType.self)
        
        var val: Float = 0.0
        let r1 = getBrightness(CGMainDisplayID(), &val)
        print("Get brightness result: \(r1), brightness: \(val)")
        
        let target: Float = 0.5
        let r2 = setBrightness(CGMainDisplayID(), target)
        print("Set brightness to \(target) result: \(r2)")
    } else {
        print("Failed to find symbols in DisplayServices")
    }
} else {
    print("Failed to dlopen DisplayServices.framework")
}
