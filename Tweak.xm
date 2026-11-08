// Signal Bars: shows iOS 26 style cellular bars where the Wi-Fi icon normally is.
// The original Wi-Fi view stays in place (invisible) so the status bar layout does not change.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface _UIStatusBarWifiSignalView : UIView @end

static const void *kBarsKey = &kBarsKey;
static const void *kAlphaKey = &kAlphaKey;

// ---------------------------------------------------------------- the bars
@interface LGBarsView : UIView
@property (nonatomic, weak) UIView *source;
@property (nonatomic, strong) NSArray *bars;
@property (nonatomic) NSInteger active;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) NSTimer *timer;
- (void)syncFromSource;
@end

@implementation LGBarsView

- (instancetype)initWithFrame:(CGRect)f {
    self = [super initWithFrame:f];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor clearColor];
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < 4; i++) {
        CALayer *l = [CALayer layer];
        [self.layer addSublayer:l];
        [a addObject:l];
    }
    _bars = a;
    _active = 4;
    _color = [UIColor whiteColor];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.timer invalidate];
    self.timer = nil;
    if (self.window) {
        __weak LGBarsView *ws = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *t) {
            [ws syncFromSource];
        }];
        [self syncFromSource];
    }
}

// Reads strength and color from the real Wi-Fi view when it exposes them; otherwise shows full bars.
- (void)syncFromSource {
    UIView *src = self.source;
    if (!src) return;
    if (src.superview == self.superview && !CGRectEqualToRect(self.frame, src.frame)) {
        self.frame = src.frame;
    }

    NSInteger nBars = 3, nAct = 3;
    BOOL haveAct = NO;
    @try {
        id v = [src valueForKey:@"numberOfBars"];
        if ([v respondsToSelector:@selector(integerValue)] && [v integerValue] > 0) nBars = [v integerValue];
    } @catch (NSException *e) {}
    @try {
        id v = [src valueForKey:@"numberOfActiveBars"];
        if ([v respondsToSelector:@selector(integerValue)]) { nAct = [v integerValue]; haveAct = YES; }
    } @catch (NSException *e) {}

    NSInteger act = haveAct ? (NSInteger)ceil((double)nAct * 4.0 / (double)nBars) : 4;
    act = MIN(4, MAX(0, act));

    UIColor *c = nil;
    @try { c = [src valueForKey:@"activeColor"]; } @catch (NSException *e) {}
    if (![c isKindOfClass:[UIColor class]]) c = [UIColor whiteColor];

    if (act != self.active || ![c isEqual:self.color]) {
        self.active = act;
        self.color = c;
        [self setNeedsLayout];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, H = self.bounds.size.height;
    if (W < 4 || H < 4) return;
    CGFloat scale = H / 11.0;
    CGFloat barW = 2.8 * scale;
    CGFloat gap = (W - 4 * barW) / 3.0;
    if (gap < 0.5) { gap = 0.5; barW = (W - 3 * gap) / 4.0; }
    CGFloat heights[4] = {3.4, 6.2, 8.6, 11.0};

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < 4; i++) {
        CALayer *l = self.bars[i];
        CGFloat h = heights[i] * scale;
        l.frame = CGRectMake(i * (barW + gap), H - h, barW, h);
        l.cornerRadius = MIN(barW, h) / 2.0;
        BOOL on = i < self.active;
        l.backgroundColor = [self.color colorWithAlphaComponent:on ? 1.0 : 0.3].CGColor;
    }
    [CATransaction commit];
}
@end

// ---------------------------------------------------------------- wiring
static LGBarsView *barsFor(UIView *wifi) {
    return objc_getAssociatedObject(wifi, kBarsKey);
}

static void syncBars(UIView *wifi) {
    UIView *parent = wifi.superview;
    if (!parent) return;

    // Remember the alpha the status bar wants, then keep the Wi-Fi arcs invisible.
    if (!objc_getAssociatedObject(wifi, kAlphaKey)) {
        objc_setAssociatedObject(wifi, kAlphaKey, @(wifi.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    wifi.layer.opacity = 0.0;

    LGBarsView *b = barsFor(wifi);
    if (!b) {
        b = [[LGBarsView alloc] initWithFrame:wifi.frame];
        b.source = wifi;
        objc_setAssociatedObject(wifi, kBarsKey, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (b.superview != parent) [parent insertSubview:b aboveSubview:wifi];
    if (!CGRectEqualToRect(b.frame, wifi.frame)) b.frame = wifi.frame;

    NSNumber *req = objc_getAssociatedObject(wifi, kAlphaKey);
    b.alpha = req ? (CGFloat)req.doubleValue : 1.0;
    b.hidden = wifi.hidden;
}

%hook _UIStatusBarWifiSignalView
- (void)layoutSubviews {
    %orig;
    syncBars(self);
}
- (void)didMoveToWindow {
    %orig;
    syncBars(self);
}
- (void)setFrame:(CGRect)f {
    %orig;
    LGBarsView *b = barsFor(self);
    if (b && b.superview == self.superview) b.frame = f;
}
- (void)setAlpha:(CGFloat)a {
    objc_setAssociatedObject(self, kAlphaKey, @(a), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(0.0);  // the arcs stay invisible
    LGBarsView *b = barsFor(self);
    if (b) b.alpha = a;  // runs inside the status bar's own animation, so it fades with it
}
- (void)setHidden:(BOOL)h {
    %orig;
    LGBarsView *b = barsFor(self);
    if (b) b.hidden = h;
}
%end
