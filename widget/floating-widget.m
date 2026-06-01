#import "floating-widget.h"
#import "widget-ipc.h"
#import <objc/runtime.h>

#define SCRIPTS_DIR @"/Library/IOSAutoTool/scripts"
#define WIDGET_SIZE  52.0
#define MENU_WIDTH  220.0
#define MENU_ROW_H   40.0

static NSString *const kPosKey = @"IOSAutoToolWidgetPos";

@interface FloatingWidget ()
@property (nonatomic, strong) UIWindow   *floatWindow;
@property (nonatomic, strong) UIWindow   *menuWindow;
@property (nonatomic, strong) UIButton   *bubble;
@property (nonatomic, assign) CGPoint     panStart;
@property (nonatomic, assign) CGPoint     viewStart;
@property (nonatomic, assign) BOOL        moved;
@end

@implementation FloatingWidget

+ (instancetype)sharedInstance {
    static FloatingWidget *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[FloatingWidget alloc] init]; });
    return inst;
}

- (void)show {
    if (self.floatWindow) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    CGPoint saved = [self loadSavedPosition];
    if (CGPointEqualToPoint(saved, CGPointZero)) {
        saved = CGPointMake(screen.size.width - WIDGET_SIZE - 12, screen.size.height / 2);
    }

    UIWindow *w = [[UIWindow alloc] initWithFrame:
                   CGRectMake(saved.x, saved.y, WIDGET_SIZE, WIDGET_SIZE)];
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = [UIColor clearColor];
    w.userInteractionEnabled = YES;
    w.hidden = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    w.rootViewController = vc;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, WIDGET_SIZE, WIDGET_SIZE);
    btn.backgroundColor = [UIColor colorWithRed:0.31 green:0.56 blue:0.97 alpha:0.92];
    btn.layer.cornerRadius = WIDGET_SIZE / 2;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.35;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    btn.layer.shadowRadius = 5;
    [btn setTitle:@"⚡" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:22];
    [btn addTarget:self action:@selector(onTap) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(onPan:)];
    [btn addGestureRecognizer:pan];

    [vc.view addSubview:btn];
    self.bubble = btn;
    self.floatWindow = w;
}

- (void)hide {
    [self dismissMenu];
    self.floatWindow.hidden = YES;
    self.floatWindow = nil;
}

- (CGPoint)loadSavedPosition {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPosKey];
    if (!d) return CGPointZero;
    return CGPointMake([d[@"x"] doubleValue], [d[@"y"] doubleValue]);
}

- (void)savePosition:(CGPoint)p {
    [[NSUserDefaults standardUserDefaults] setObject:@{@"x": @(p.x), @"y": @(p.y)}
                                              forKey:kPosKey];
}

- (void)onPan:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        self.panStart  = [pan locationInView:self.floatWindow.rootViewController.view];
        self.viewStart = self.floatWindow.frame.origin;
        self.moved = NO;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint cur = [pan locationInView:self.floatWindow.rootViewController.view];
        CGFloat dx = cur.x - self.panStart.x;
        CGFloat dy = cur.y - self.panStart.y;
        if (fabs(dx) > 4 || fabs(dy) > 4) self.moved = YES;

        CGRect f = self.floatWindow.frame;
        f.origin.x = self.viewStart.x + dx;
        f.origin.y = self.viewStart.y + dy;
        CGSize scr = [UIScreen mainScreen].bounds.size;
        f.origin.x = MAX(0, MIN(scr.width  - WIDGET_SIZE, f.origin.x));
        f.origin.y = MAX(20, MIN(scr.height - WIDGET_SIZE - 20, f.origin.y));
        self.floatWindow.frame = f;
    } else if (pan.state == UIGestureRecognizerStateEnded ||
               pan.state == UIGestureRecognizerStateCancelled) {
        [self savePosition:self.floatWindow.frame.origin];
    }
}

- (void)onTap {
    if (self.moved) { self.moved = NO; return; }
    if (self.menuWindow) { [self dismissMenu]; return; }
    [self showMenu];
}

- (NSArray<NSString *> *)listScripts {
    NSArray *all = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:SCRIPTS_DIR error:nil];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *f in all) {
        if ([f hasSuffix:@".lua"]) [out addObject:f];
    }
    [out sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return out;
}

- (void)showMenu {
    NSArray *scripts = [self listScripts];
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat menuH = MIN(scr.height * 0.6, MAX(MENU_ROW_H, scripts.count * MENU_ROW_H + 12));

    CGRect bubbleFrame = self.floatWindow.frame;
    CGFloat mx = bubbleFrame.origin.x + WIDGET_SIZE + 6;
    if (mx + MENU_WIDTH > scr.width) mx = bubbleFrame.origin.x - MENU_WIDTH - 6;
    if (mx < 0) mx = 6;
    CGFloat my = bubbleFrame.origin.y;
    if (my + menuH > scr.height - 20) my = scr.height - 20 - menuH;

    UIWindow *mw = [[UIWindow alloc] initWithFrame:CGRectMake(mx, my, MENU_WIDTH, menuH)];
    mw.windowLevel = UIWindowLevelAlert + 99;
    mw.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    vc.view.layer.cornerRadius = 12;
    vc.view.layer.borderWidth = 1;
    vc.view.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
    mw.rootViewController = vc;

    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:
                        CGRectMake(0, 0, MENU_WIDTH, menuH)];
    sv.contentSize = CGSizeMake(MENU_WIDTH, scripts.count * MENU_ROW_H + 12);
    [vc.view addSubview:sv];

    if (scripts.count == 0) {
        UILabel *empty = [[UILabel alloc] initWithFrame:
            CGRectMake(0, 0, MENU_WIDTH, MENU_ROW_H)];
        empty.text = @"Chưa có script .lua";
        empty.textAlignment = NSTextAlignmentCenter;
        empty.textColor = [UIColor lightGrayColor];
        empty.font = [UIFont systemFontOfSize:13];
        [sv addSubview:empty];
    } else {
        for (NSUInteger i = 0; i < scripts.count; i++) {
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(8, 6 + i * MENU_ROW_H, MENU_WIDTH - 16, MENU_ROW_H - 2);
            row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            row.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 8);
            row.titleLabel.font = [UIFont systemFontOfSize:13];
            [row setTitle:[NSString stringWithFormat:@"▶  %@", scripts[i]]
                 forState:UIControlStateNormal];
            [row setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            row.layer.cornerRadius = 6;
            row.tag = (NSInteger)i;
            [row addTarget:self action:@selector(onMenuTap:)
                forControlEvents:UIControlEventTouchUpInside];
            objc_setAssociatedObject(row, "script", scripts[i],
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [sv addSubview:row];
        }
    }

    mw.hidden = NO;
    self.menuWindow = mw;
}

- (void)dismissMenu {
    self.menuWindow.hidden = YES;
    self.menuWindow = nil;
}

- (void)onMenuTap:(UIButton *)btn {
    NSString *name = objc_getAssociatedObject(btn, "script");
    if (!name) { [self dismissMenu]; return; }
    NSString *path = [SCRIPTS_DIR stringByAppendingPathComponent:name];

    [self flashBubbleColor:[UIColor colorWithRed:0.13 green:0.77 blue:0.37 alpha:0.95]];
    BOOL ok = widget_ipc_run_script(path);
    if (!ok) {
        [self flashBubbleColor:[UIColor colorWithRed:0.94 green:0.27 blue:0.27 alpha:0.95]];
    }
    [self dismissMenu];
}

- (void)flashBubbleColor:(UIColor *)color {
    UIColor *original = [UIColor colorWithRed:0.31 green:0.56 blue:0.97 alpha:0.92];
    self.bubble.backgroundColor = color;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        self.bubble.backgroundColor = original;
    });
}

@end
