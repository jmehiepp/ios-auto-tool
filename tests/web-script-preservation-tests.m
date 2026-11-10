#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "../spoof/web-script-update.h"
#include <assert.h>

static WKUserScript *AppScript(NSString *source) {
    return [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
}
static BOOL Contains(WKUserContentController *controller, WKUserScript *expected) {
    for (WKUserScript *script in controller.userScripts) if (script == expected) return YES;
    return NO;
}
int main(void) {
    @autoreleasepool {
        WKUserContentController *controller = [WKUserContentController new];
        WKUserScript *app = AppScript(@"window.appFixture = 1");
        WKUserScript *other = AppScript(@"window.otherFixture = 1");
        [controller addUserScript:app]; [controller addUserScript:other];
        assert(!IOSATUpdateDeviceWebScript(controller, nil));
        NSString *first = [IOSATDeviceWebScriptMarker stringByAppendingString:@"\nwindow.deviceFixture=1;"];
        assert(IOSATUpdateDeviceWebScript(controller, first));
        assert(controller.userScripts.count == 3 && Contains(controller, app) && Contains(controller, other));
        assert(app.injectionTime == WKUserScriptInjectionTimeAtDocumentEnd && app.forMainFrameOnly);
        assert(!IOSATUpdateDeviceWebScript(controller, first));
        assert(controller.userScripts.count == 3);
        NSString *second = [IOSATDeviceWebScriptMarker stringByAppendingString:@"\nwindow.deviceFixture=2;"];
        assert(IOSATUpdateDeviceWebScript(controller, second));
        assert(controller.userScripts.count == 3 && Contains(controller, app) && Contains(controller, other));
        NSUInteger owned = 0;
        for (WKUserScript *script in controller.userScripts) if ([script.source hasPrefix:IOSATDeviceWebScriptMarker]) {
            owned++; assert([script.source isEqual:second]);
            assert(script.injectionTime == WKUserScriptInjectionTimeAtDocumentStart && !script.forMainFrameOnly);
        }
        assert(owned == 1);
        assert(IOSATUpdateDeviceWebScript(controller, nil));
        assert(controller.userScripts.count == 2 && Contains(controller, app) && Contains(controller, other));
        assert(!IOSATUpdateDeviceWebScript(controller, nil));
        puts("Device WebKit script preservation tests passed");
    }
    return 0;
}
