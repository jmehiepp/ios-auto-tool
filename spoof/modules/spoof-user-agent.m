#import "../spoof-config.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static char OriginalUserAgentKey;
static void ApplyUserAgent(WKWebView *view) {
    NSString *configured = spoof_str(@"user_agent");
    NSDictionary *saved = objc_getAssociatedObject(view, &OriginalUserAgentKey);
    if (configured) {
        if (!saved) {
            saved = @{@"value": view.customUserAgent ?: NSNull.null};
            objc_setAssociatedObject(view, &OriginalUserAgentKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (![view.customUserAgent isEqualToString:configured]) view.customUserAgent = configured;
    } else if (saved) {
        id original = saved[@"value"];
        view.customUserAgent = original == NSNull.null ? nil : original;
        objc_setAssociatedObject(view, &OriginalUserAgentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
%group IOSATUserAgent
%hook WKWebView
- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration {
    WKWebView *view = %orig(frame, configuration);
    if (view) ApplyUserAgent(view);
    return view;
}
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    ApplyUserAgent(self);
    return %orig(request);
}
- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL {
    ApplyUserAgent(self);
    return %orig(string, baseURL);
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATUserAgent); } } }
