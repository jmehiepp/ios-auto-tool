#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

FOUNDATION_EXPORT NSString *const IOSATDeviceWebScriptMarker;
FOUNDATION_EXPORT BOOL IOSATUpdateDeviceWebScript(WKUserContentController *controller, NSString *source);
