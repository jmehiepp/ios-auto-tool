#import "../spoof-config.h"
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSString *const Marker = @"/* IOSAutoTool.Device.Web */";
static char ScriptSignatureKey;
static NSString *DeviceWebScript(void) {
    BOOL canvas = spoof_on(@"canvas");
    NSNumber *canvasValue = spoof_num(@"canvas");
    if (canvasValue) canvas = canvasValue.boolValue;
    NSString *vendor = spoof_str(@"webgl_vendor");
    NSString *renderer = spoof_str(@"webgl_renderer");
    if (!canvas && !vendor && !renderer) return nil;
    static uint32_t seed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seed = arc4random(); });
    NSDictionary *settings = @{@"canvas": @(canvas), @"seed": @(seed),
        @"vendor": vendor ?: NSNull.null, @"renderer": renderer ?: NSNull.null};
    NSData *json = [NSJSONSerialization dataWithJSONObject:settings options:0 error:NULL];
    if (!json) return nil;
    NSString *literal = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return [NSString stringWithFormat:
        @"%@\n(function(){'use strict';window.__IOSATDeviceSettings=%@;"
         "var g=window.__IOSATDeviceSettings;"
         "if(typeof CanvasRenderingContext2D!=='undefined'){var c=CanvasRenderingContext2D.prototype;"
         "if(!c.__iosatImageData){Object.defineProperty(c,'__iosatImageData',{value:c.getImageData});"
         "c.getImageData=function(){var d=c.__iosatImageData.apply(this,arguments),s=window.__IOSATDeviceSettings;"
         "if(s&&s.canvas){for(var i=0;i<d.data.length;i+=4){var n=((Math.imul(i+1,2654435761)^s.seed)&1)?1:-1;"
         "d.data[i]=Math.max(0,Math.min(255,d.data[i]+n));}}return d;};}}"
         "[window.WebGLRenderingContext,window.WebGL2RenderingContext].forEach(function(K){if(!K)return;"
         "var p=K.prototype;if(Object.prototype.hasOwnProperty.call(p,'__iosatParameter'))return;"
         "var original=p.getParameter;Object.defineProperty(p,'__iosatParameter',{value:original});"
         "p.getParameter=function(n){var s=window.__IOSATDeviceSettings;if(s){"
         "if(n===0x9245&&s.vendor!==null)return s.vendor;"
         "if(n===0x9246&&s.renderer!==null)return s.renderer;}return original.call(this,n);};});"
         "})();", Marker, literal];
}

%group IOSATWebGraphics
%hook WKWebViewConfiguration
- (WKUserContentController *)userContentController {
    WKUserContentController *controller = %orig;
    if (!controller) return controller;
    NSString *source = DeviceWebScript();
    NSString *previous = objc_getAssociatedObject(controller, &ScriptSignatureKey);
    if ((!source && !previous) || [source isEqualToString:previous]) return controller;
    // Replace only scripts owned by this addon and preserve the app's scripts.
    // On iOS 15 both userScripts and its copy can be live WKNSArray views.
    // Retain each script in independent Foundation storage before clearing it.
    NSMutableArray<WKUserScript *> *oldScripts = [NSMutableArray array];
    for (WKUserScript *script in controller.userScripts) [oldScripts addObject:script];
    [controller removeAllUserScripts];
    for (WKUserScript *script in oldScripts)
        if (![script.source hasPrefix:Marker]) [controller addUserScript:script];
    if (source) {
        WKUserScript *script = [[WKUserScript alloc] initWithSource:source
            injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
        [controller addUserScript:script];
    }
    objc_setAssociatedObject(controller, &ScriptSignatureKey, source, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return controller;
}
%end
%end
%ctor { @autoreleasepool { if (IOSATShouldInitializeHooks()) { %init(IOSATWebGraphics); } } }
