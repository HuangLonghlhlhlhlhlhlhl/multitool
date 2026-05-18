#import "KeyboardBacklightPrivate.h"
#import <dlfcn.h>

@interface NSObject (KeyboardBrightnessClientPrivate)
- (float)brightnessForKeyboard:(unsigned long long)keyboard;
- (BOOL)setBrightness:(float)brightness forKeyboard:(unsigned long long)keyboard;
@end

@implementation KeyboardBacklightPrivate

static id client = nil;

+ (id)sharedClient {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        if (handle) {
            Class clientClass = NSClassFromString(@"KeyboardBrightnessClient");
            if (clientClass) {
                client = [[clientClass alloc] init];
                NSLog(@"[KeyboardBacklightPrivate] Successfully loaded KeyboardBrightnessClient.");
            } else {
                NSLog(@"[KeyboardBacklightPrivate] Failed to find KeyboardBrightnessClient class.");
            }
        } else {
            NSLog(@"[KeyboardBacklightPrivate] Failed to load CoreBrightness framework dynamically.");
        }
    });
    return client;
}

+ (BOOL)setBrightness:(float)brightness {
    id c = [self sharedClient];
    if (c) {
        if ([c respondsToSelector:@selector(setBrightness:forKeyboard:)]) {
            // macOS keyboards are typically identified by keyboard ID 1 (built-in) or 0
            BOOL result = [c setBrightness:brightness forKeyboard:1];
            [c setBrightness:brightness forKeyboard:0]; // fallback to ID 0
            return result;
        }
    }
    return NO;
}

+ (float)getBrightness {
    id c = [self sharedClient];
    if (c) {
        if ([c respondsToSelector:@selector(brightnessForKeyboard:)]) {
            float b1 = [c brightnessForKeyboard:1];
            if (b1 >= 0.0) return b1;
            float b0 = [c brightnessForKeyboard:0];
            if (b0 >= 0.0) return b0;
        }
    }
    return 0.0;
}

@end
