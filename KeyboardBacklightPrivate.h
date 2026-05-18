#import <Foundation/Foundation.h>

@interface KeyboardBacklightPrivate : NSObject

// Sets the keyboard brightness between 0.0 (off) and 1.0 (maximum)
+ (BOOL)setBrightness:(float)brightness;

// Gets the current keyboard brightness
+ (float)getBrightness;

@end
