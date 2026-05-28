#import "../spoof-config.h"
#import <WebKit/WebKit.h>

// JS injected before page load to add per-session noise to canvas getImageData
static NSString *canvas_noise_js(void) {
    // Random seed per session so fingerprint changes each app launch
    uint32_t seed = arc4random();
    return [NSString stringWithFormat:
        @"(function(){"
         "var orig=CanvasRenderingContext2D.prototype.getImageData;"
         "var seed=%u;"
         "CanvasRenderingContext2D.prototype.getImageData=function(){"
         "var d=orig.apply(this,arguments);"
         "for(var i=0;i<d.data.length;i+=4){"
         "var n=((seed=(seed*1664525+1013904223)>>>0)&0xFF)*0.004;"
         "d.data[i]=(d.data[i]+n)&255;"
         "d.data[i+1]=(d.data[i+1]+n)&255;"
         "d.data[i+2]=(d.data[i+2]+n)&255;"
         "}return d;};"
         "})();", seed];
}

static NSString *webgl_js(NSString *vendor, NSString *renderer) {
    return [NSString stringWithFormat:
        @"(function(){"
         "var orig=WebGLRenderingContext.prototype.getParameter;"
         "WebGLRenderingContext.prototype.getParameter=function(p){"
         "if(p===0x9245)return '%@';"   // UNMASKED_VENDOR_WEBGL
         "if(p===0x9246)return '%@';"   // UNMASKED_RENDERER_WEBGL
         "return orig.call(this,p);};"
         "})();", vendor, renderer];
}

%hook WKWebViewConfiguration
- (WKUserContentController *)userContentController {
    WKUserContentController *ctrl = %orig;
    if (!spoof_on(@"canvas") && !spoof_on(@"webgl_vendor") && !spoof_on(@"webgl_renderer"))
        return ctrl;

    NSMutableArray *scripts = [NSMutableArray array];
    if (spoof_on(@"canvas"))
        [scripts addObject:canvas_noise_js()];
    NSString *vendor   = spoof_str(@"webgl_vendor");
    NSString *renderer = spoof_str(@"webgl_renderer");
    if (vendor || renderer)
        [scripts addObject:webgl_js(vendor ?: @"Apple Inc.", renderer ?: @"Apple GPU")];

    NSString *combined = [scripts componentsJoinedByString:@"\n"];
    WKUserScript *s = [[WKUserScript alloc]
        initWithSource:combined
         injectionTime:WKUserScriptInjectionTimeAtDocumentStart
      forMainFrameOnly:NO];
    [ctrl addUserScript:s];
    return ctrl;
}
%end
