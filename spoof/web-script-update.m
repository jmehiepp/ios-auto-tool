#import "web-script-update.h"
#import <objc/runtime.h>

NSString *const IOSATDeviceWebScriptMarker = @"/* IOSAutoTool.Device.Web */";
static char ScriptSignatureKey;

BOOL IOSATUpdateDeviceWebScript(WKUserContentController *controller, NSString *source) {
    if (!controller) return NO;
    NSString *previous = objc_getAssociatedObject(controller, &ScriptSignatureKey);
    if ((!source && !previous) || [source isEqualToString:previous]) return NO;
    // Both userScripts and its copy can be live WKNSArray views on iOS 15.
    NSMutableArray<WKUserScript *> *snapshot = [NSMutableArray array];
    for (WKUserScript *script in controller.userScripts) [snapshot addObject:script];
    [controller removeAllUserScripts];
    for (WKUserScript *script in snapshot)
        if (![script.source hasPrefix:IOSATDeviceWebScriptMarker]) [controller addUserScript:script];
    if (source) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:source
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
        [controller addUserScript:script];
    }
    objc_setAssociatedObject(controller, &ScriptSignatureKey, source, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return YES;
}
