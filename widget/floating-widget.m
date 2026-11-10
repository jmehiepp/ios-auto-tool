#import "floating-widget.h"
#import "widget-ipc.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

static const CGFloat WidgetSize = 52.0;
static const CGFloat MenuWidth = 248.0;
static const CGFloat RowHeight = 44.0;
static NSString *const PositionKey = @"IOSAutoToolWidgetPos";
static const void *ScriptNameKey = &ScriptNameKey;

@interface FloatingWidget ()
@property (nonatomic, strong) UIWindow *floatWindow;
@property (nonatomic, strong) UIWindow *menuWindow;
@property (nonatomic, strong) UIButton *bubble;
@property (nonatomic, strong) UIScrollView *menuScroll;
@property (nonatomic, strong) NSArray<NSString *> *scriptNames;
@property (nonatomic, strong) NSString *statusMessage;
@property (nonatomic, strong) NSTimer *statusTimer;
@property (nonatomic, strong) dispatch_queue_t ipcQueue;
@property (nonatomic, assign) CGPoint viewStart;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, assign) BOOL loadingScripts;
@property (nonatomic, assign) BOOL statusPending;
@property (nonatomic, assign) BOOL commandPending;
@property (nonatomic, assign) BOOL stopRequested;
@property (nonatomic, assign) NSUInteger stateVersion;
@end

@implementation FloatingWidget

+ (instancetype)sharedInstance {
    static FloatingWidget *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _ipcQueue = dispatch_queue_create("com.iosautotool.widget.ipc", DISPATCH_QUEUE_SERIAL);
        _scriptNames = @[];
        _statusMessage = @"Đang kết nối daemon…";
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reposition)
            name:UIDeviceOrientationDidChangeNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reposition)
            name:UIApplicationDidChangeStatusBarOrientationNotification object:nil];
    }
    return self;
}

- (UIWindow *)windowWithFrame:(CGRect)frame {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                window.frame = frame;
                break;
            }
        }
    }
    if (!window) window = [[UIWindow alloc] initWithFrame:frame];
    window.backgroundColor = UIColor.clearColor;
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = controller;
    // Do not become key: the widget must not steal text focus from other apps.
    return window;
}

- (CGPoint)clampedPosition:(CGPoint)position {
    CGRect screen = UIScreen.mainScreen.bounds;
    UIEdgeInsets insets = UIEdgeInsetsZero;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window != self.floatWindow && window != self.menuWindow && !window.hidden) {
            insets.top = MAX(insets.top, window.safeAreaInsets.top);
            insets.bottom = MAX(insets.bottom, window.safeAreaInsets.bottom);
        }
    }
    CGFloat minY = MAX(8, insets.top);
    CGFloat maxY = MAX(minY, CGRectGetHeight(screen) - WidgetSize - MAX(8, insets.bottom));
    return CGPointMake(MAX(0, MIN(CGRectGetWidth(screen) - WidgetSize, position.x)),
                       MAX(minY, MIN(maxY, position.y)));
}

- (void)show {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self show]; }); return;
    }
    if (self.floatWindow) { self.floatWindow.hidden = NO; return; }
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:PositionKey];
    CGSize size = UIScreen.mainScreen.bounds.size;
    CGPoint position = saved ? CGPointMake([saved[@"x"] doubleValue], [saved[@"y"] doubleValue]) :
        CGPointMake(size.width - WidgetSize - 12, size.height / 2);
    if (!isfinite(position.x) || !isfinite(position.y)) position = CGPointMake(12, size.height / 2);
    position = [self clampedPosition:position];
    self.floatWindow = [self windowWithFrame:CGRectMake(position.x, position.y, WidgetSize, WidgetSize)];
    self.floatWindow.windowLevel = UIWindowLevelAlert + 100;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, WidgetSize, WidgetSize);
    button.layer.cornerRadius = WidgetSize / 2;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = 0.3;
    button.layer.shadowOffset = CGSizeMake(0, 2);
    button.layer.shadowRadius = 5;
    button.titleLabel.font = [UIFont systemFontOfSize:23 weight:UIFontWeightSemibold];
    button.accessibilityLabel = @"iOS Auto Tool, mở menu macro";
    [button addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [button addGestureRecognizer:pan];
    [self.floatWindow.rootViewController.view addSubview:button];
    self.bubble = button;
    self.floatWindow.hidden = NO;
    [self updateBubble];
    self.statusTimer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(pollStatus)
        userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
    [self pollStatus];
}

- (void)hide {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hide]; }); return;
    }
    [self dismissMenu];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
    self.floatWindow.hidden = YES;
    self.floatWindow = nil;
    self.bubble = nil;
    // Hiding controls never stops or starts a saved macro.
}

- (void)reposition {
    if (!self.floatWindow) return;
    CGRect frame = self.floatWindow.frame;
    frame.origin = [self clampedPosition:frame.origin];
    self.floatWindow.frame = frame;
    if (self.menuWindow) [self renderMenu];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.viewStart = self.floatWindow.frame.origin;
        [self dismissMenu];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint delta = [pan translationInView:nil];
        CGPoint position = [self clampedPosition:CGPointMake(self.viewStart.x + delta.x, self.viewStart.y + delta.y)];
        self.floatWindow.frame = CGRectMake(position.x, position.y, WidgetSize, WidgetSize);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint position = self.floatWindow.frame.origin;
        [NSUserDefaults.standardUserDefaults setObject:@{@"x": @(position.x), @"y": @(position.y)} forKey:PositionKey];
    }
}

- (void)onTap {
    if (self.menuWindow) [self dismissMenu];
    else [self showMenu];
}

- (void)updateBubble {
    self.bubble.backgroundColor = self.running ? [UIColor colorWithRed:0.87 green:0.2 blue:0.25 alpha:0.96] :
        self.connected ? [UIColor colorWithRed:0.2 green:0.47 blue:0.95 alpha:0.96] : [UIColor colorWithWhite:0.35 alpha:0.96];
    [self.bubble setTitle:self.commandPending ? @"…" : (self.running ? @"■" : @"▶") forState:UIControlStateNormal];
    self.bubble.accessibilityValue = self.running ? @"Macro đang chạy" : self.statusMessage;
}

- (void)showMenu {
    if (!self.floatWindow || self.menuWindow) return;
    self.menuWindow = [self windowWithFrame:CGRectMake(0, 0, MenuWidth, RowHeight)];
    self.menuWindow.windowLevel = UIWindowLevelAlert + 99;
    self.menuWindow.rootViewController.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.98];
    self.menuWindow.rootViewController.view.layer.cornerRadius = 12;
    self.menuWindow.rootViewController.view.clipsToBounds = YES;
    self.menuScroll = [UIScrollView new];
    [self.menuWindow.rootViewController.view addSubview:self.menuScroll];
    self.menuWindow.hidden = NO;
    [self renderMenu];
    [self refreshScripts];
}

- (UIButton *)menuButton:(NSString *)title y:(CGFloat)y selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(8, y, MenuWidth - 16, RowHeight);
    button.titleLabel.font = [UIFont systemFontOfSize:14];
    button.titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 10, 0, 10);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:UIColor.grayColor forState:UIControlStateDisabled];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    [self.menuScroll addSubview:button];
    return button;
}

- (void)renderMenu {
    if (!self.menuWindow) return;
    CGPoint scrollPosition = self.menuScroll.contentOffset;
    for (UIView *view in self.menuScroll.subviews) [view removeFromSuperview];
    CGFloat y = 8;
    UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(14, y, MenuWidth - 28, 48)];
    status.text = self.statusMessage;
    status.textColor = self.connected ? UIColor.lightGrayColor : [UIColor colorWithRed:1 green:0.7 blue:0.4 alpha:1];
    status.numberOfLines = 2;
    status.font = [UIFont systemFontOfSize:12];
    [self.menuScroll addSubview:status];
    y += 48;
    UIButton *stop = [self menuButton:@"■  Dừng macro" y:y selector:@selector(stopScript)];
    stop.enabled = self.running && !self.commandPending;
    y += RowHeight;
    if (self.loadingScripts || !self.scriptNames.count) {
        UILabel *empty = [[UILabel alloc] initWithFrame:CGRectMake(16, y, MenuWidth - 32, RowHeight)];
        empty.text = self.loadingScripts ? @"Đang lấy danh sách…" : @"Chưa có script .lua đã lưu";
        empty.textColor = UIColor.lightGrayColor;
        empty.font = [UIFont systemFontOfSize:13];
        [self.menuScroll addSubview:empty];
        y += RowHeight;
    } else {
        for (NSString *name in self.scriptNames) {
            UIButton *row = [self menuButton:[@"▶  " stringByAppendingString:name] y:y selector:@selector(onMenuTap:)];
            objc_setAssociatedObject(row, ScriptNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
            row.enabled = self.connected && !self.running && !self.commandPending;
            row.accessibilityLabel = [@"Chạy macro " stringByAppendingString:name];
            y += RowHeight;
        }
    }
    UIButton *refresh = [self menuButton:@"↻  Làm mới danh sách" y:y selector:@selector(refreshScripts)];
    refresh.enabled = !self.loadingScripts;
    y += RowHeight;
    [self menuButton:@"Đóng menu" y:y selector:@selector(dismissMenu)];
    y += RowHeight + 8;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat height = MIN(y, screen.height * 0.65);
    CGRect bubble = self.floatWindow.frame;
    CGFloat x = CGRectGetMaxX(bubble) + 6;
    if (x + MenuWidth > screen.width - 6) x = bubble.origin.x - MenuWidth - 6;
    x = MAX(6, MIN(screen.width - MenuWidth - 6, x));
    CGFloat top = MAX(24, MIN(screen.height - height - 24, bubble.origin.y));
    self.menuWindow.frame = CGRectMake(x, top, MenuWidth, height);
    self.menuScroll.frame = CGRectMake(0, 0, MenuWidth, height);
    self.menuScroll.contentSize = CGSizeMake(MenuWidth, y);
    self.menuScroll.contentOffset = CGPointMake(0, MAX(0, MIN(y - height, scrollPosition.y)));
}

- (void)dismissMenu {
    self.menuWindow.hidden = YES;
    self.menuWindow = nil;
    self.menuScroll = nil;
}

- (NSString *)errorMessage:(NSDictionary *)reply error:(NSError *)error {
    if (error) return error.localizedDescription;
    NSString *message = [reply[@"error"] isKindOfClass:NSString.class] ? reply[@"error"] : nil;
    return message.length ? message : @"Daemon từ chối yêu cầu.";
}

- (void)refreshScripts {
    if (self.loadingScripts) return;
    self.loadingScripts = YES;
    [self renderMenu];
    NSUInteger version = self.stateVersion;
    dispatch_async(self.ipcQueue, ^{
        NSError *error = nil;
        NSDictionary *reply = widget_ipc_request(@"list_scripts", nil, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loadingScripts = NO;
            if ([reply[@"ok"] boolValue] && [reply[@"scripts"] isKindOfClass:NSArray.class]) {
                NSMutableSet *names = [NSMutableSet set];
                for (id name in reply[@"scripts"]) if (widget_ipc_valid_script_name(name)) [names addObject:name];
                self.scriptNames = [[names allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
                self.connected = YES;
                if (version == self.stateVersion && [reply[@"running"] isKindOfClass:NSNumber.class]) {
                    self.running = [reply[@"running"] boolValue];
                    if (!self.running) self.stopRequested = NO;
                    self.statusMessage = self.running ? (self.stopRequested ? @"Đang chờ macro dừng…" : @"Macro đang chạy") : @"Chọn macro đã lưu để chạy";
                }
            } else {
                self.connected = NO;
                self.statusMessage = [self errorMessage:reply error:error];
            }
            [self updateBubble]; [self renderMenu];
        });
    });
}

- (void)pollStatus {
    if (self.statusPending || self.commandPending || !self.floatWindow) return;
    self.statusPending = YES;
    NSUInteger version = self.stateVersion;
    dispatch_async(self.ipcQueue, ^{
        NSError *error = nil;
        NSDictionary *reply = widget_ipc_request(@"script_status", nil, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusPending = NO;
            if (version != self.stateVersion) return;
            if ([reply[@"ok"] boolValue] && [reply[@"running"] isKindOfClass:NSNumber.class]) {
                self.connected = YES;
                self.running = [reply[@"running"] boolValue];
                if (!self.running) self.stopRequested = NO;
                self.statusMessage = self.running ? (self.stopRequested ? @"Đang chờ macro dừng…" : @"Macro đang chạy") : @"Sẵn sàng · chạm để chọn macro";
            } else {
                self.connected = NO;
                self.statusMessage = [self errorMessage:reply error:error];
            }
            [self updateBubble]; [self renderMenu];
        });
    });
}

- (void)onMenuTap:(UIButton *)button {
    NSString *name = objc_getAssociatedObject(button, ScriptNameKey);
    if (!widget_ipc_valid_script_name(name) || self.commandPending || self.running) return;
    [self sendAction:@"run_saved_script" name:name];
}

- (void)stopScript {
    if (!self.running || self.commandPending) return;
    [self sendAction:@"stop_script" name:nil];
}

- (void)sendAction:(NSString *)action name:(NSString *)name {
    self.commandPending = YES;
    self.stateVersion++;
    self.statusMessage = name ? @"Đang gửi lệnh chạy…" : @"Đang yêu cầu dừng…";
    [self updateBubble]; [self renderMenu];
    dispatch_async(self.ipcQueue, ^{
        NSError *error = nil;
        NSDictionary *reply = widget_ipc_request(action, name, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.commandPending = NO;
            if ([reply[@"ok"] boolValue]) {
                self.connected = YES;
                if (name) {
                    self.running = YES;
                    self.stopRequested = NO;
                    self.statusMessage = @"Đã nhận lệnh chạy macro";
                    [self dismissMenu];
                } else {
                    // ACK means stop requested; keep the running state until status says false.
                    self.stopRequested = YES;
                    self.statusMessage = @"Đã yêu cầu dừng · đang chờ macro kết thúc";
                }
            } else {
                self.statusMessage = [self errorMessage:reply error:error];
                if (error) self.connected = NO;
            }
            [self updateBubble]; [self renderMenu];
            [self pollStatus];
        });
    });
}

@end
