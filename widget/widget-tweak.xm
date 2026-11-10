#import "floating-widget.h"
#import <UIKit/UIKit.h>
#include <notify.h>

// Controls visibility only. No notification may submit code or start a macro.
%ctor {
    if ([NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) {
        int token = 0;
        notify_register_dispatch("com.iosautotool.widget.show", &token, dispatch_get_main_queue(), ^(int ignored) {
            [[FloatingWidget sharedInstance] show];
        });
        notify_register_dispatch("com.iosautotool.widget.hide", &token, dispatch_get_main_queue(), ^(int ignored) {
            [[FloatingWidget sharedInstance] hide];
        });
    }
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[FloatingWidget sharedInstance] show];
    });
}
%end
