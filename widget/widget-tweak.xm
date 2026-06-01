#import "floating-widget.h"
#import <UIKit/UIKit.h>

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[FloatingWidget sharedInstance] show];
    });
}
%end
