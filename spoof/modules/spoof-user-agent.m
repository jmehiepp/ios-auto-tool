#import "../spoof-config.h"
#import <WebKit/WebKit.h>

%hook WKWebView
- (WKNavigation *)loadRequest:(NSURLRequest *)request {
    NSString *ua = spoof_str(@"user_agent");
    if (!ua) return %orig;
    NSMutableURLRequest *mut = [request mutableCopy];
    [mut setValue:ua forHTTPHeaderField:@"User-Agent"];
    return %orig(mut);
}
%end

%hook WKWebViewConfiguration
- (NSString *)applicationNameForUserAgent {
    NSString *ua = spoof_str(@"user_agent");
    return ua ?: %orig;
}
%end
