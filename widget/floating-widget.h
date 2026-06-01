#pragma once
#import <UIKit/UIKit.h>

@interface FloatingWidget : UIView
+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;
@end
