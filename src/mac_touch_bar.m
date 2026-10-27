// A persistent Touch Bar is only possible through the unsupported system-modal
// and Control Strip APIs. Keep that boundary in one macOS-only translation unit.
// The presentation approach follows Touch Bar Lyrics:
// https://github.com/iqbalrahman-jpg/mac-touchbar-lyric
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <math.h>

// Both surfaces use the same clock. Returning a pixel offset instead of a
// substring lets AppKit lay out Unicode and right-to-left text intact.
double spotifast_marquee_offset(double overflow, double viewport,
                                double elapsed, int reducedMotion) {
    if (overflow <= 0 || viewport <= 0) return 0;
    if (reducedMotion) {
        double page = fmax(1, viewport - 20);
        double pages = ceil(overflow / page) + 1;
        double index = floor(fmax(0, elapsed) / 2.5);
        return fmin(overflow, fmod(index, pages) * page);
    }
    const double pause = 0.8;
    const double speed = 60;
    double travel = overflow / speed;
    double phase = fmod(fmax(0, elapsed), travel + 2 * pause);
    if (phase < pause) return 0;
    return fmin(overflow, (phase - pause) * speed);
}

@interface SpotifastMarqueeView : NSView
@property(nonatomic, strong) NSTextField *label;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *line;
@property(nonatomic) CGFloat textWidth;
@property(nonatomic) CGFloat previousWidth;
@property(nonatomic) NSTimeInterval started;
@property(nonatomic) BOOL reducedMotion;
- (instancetype)initWithFrame:(NSRect)frame font:(NSFont *)font;
- (void)showLine:(NSString *)line reducedMotion:(BOOL)reducedMotion;
@end

static NSStatusItem *lyricStatusItem;
static SpotifastMarqueeView *lyricStatusView;

void spotifast_menu_lyrics_sync(int enabled, const char *line, int reducedMotion) {
    if (![NSThread isMainThread]) return;
    @autoreleasepool {
        NSString *text = line ? [NSString stringWithUTF8String:line] : nil;
        if (!enabled || text.length == 0) {
            [lyricStatusView showLine:@"" reducedMotion:reducedMotion != 0];
            lyricStatusItem.visible = NO;
            return;
        }
        if (!lyricStatusItem) {
            lyricStatusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:28];
            NSStatusBarButton *button = lyricStatusItem.button;
            button.title = @"";
            lyricStatusView = [[SpotifastMarqueeView alloc]
                initWithFrame:button.bounds font:[NSFont systemFontOfSize:13]];
            lyricStatusView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [button addSubview:lyricStatusView];
        }
        if (![lyricStatusView.line isEqualToString:text]) {
            CGFloat textWidth = ceil([text sizeWithAttributes:@{
                NSFontAttributeName: lyricStatusView.label.font
            }].width) + 8;
            lyricStatusItem.length = fmin(220, fmax(28, textWidth + 20));
            lyricStatusView.frame = lyricStatusItem.button.bounds;
        }
        [lyricStatusView showLine:text reducedMotion:reducedMotion != 0];
        lyricStatusItem.button.toolTip = text;
        lyricStatusView.toolTip = text;
        lyricStatusItem.visible = YES;
    }
}

@implementation SpotifastMarqueeView

- (instancetype)initWithFrame:(NSRect)frame font:(NSFont *)font {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.clipsToBounds = YES;
    self.line = @"";
    self.label = [NSTextField labelWithString:@""];
    self.label.font = font;
    self.label.textColor = [NSColor labelColor];
    self.label.lineBreakMode = NSLineBreakByClipping;
    self.label.maximumNumberOfLines = 1;
    self.label.cell.baseWritingDirection = NSWritingDirectionNatural;
    [self addSubview:self.label];
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)showLine:(NSString *)line reducedMotion:(BOOL)reducedMotion {
    BOOL changed = ![self.line isEqualToString:line];
    if (changed) {
        self.line = [line copy];
        self.label.stringValue = line;
        self.textWidth = ceil([line sizeWithAttributes:@{
            NSFontAttributeName: self.label.font
        }].width) + 8;
        self.started = [NSProcessInfo processInfo].systemUptime;
        self.accessibilityLabel = line;
    }
    BOOL motionChanged = self.reducedMotion != reducedMotion;
    if (motionChanged) {
        self.reducedMotion = reducedMotion;
        self.started = [NSProcessInfo processInfo].systemUptime;
        [self.timer invalidate];
        self.timer = nil;
    }
    if (changed || motionChanged) [self updatePosition];
}

- (void)layout {
    [super layout];
    CGFloat width = self.bounds.size.width;
    if (width != self.previousWidth) {
        self.previousWidth = width;
        self.started = [NSProcessInfo processInfo].systemUptime;
        [self updatePosition];
    }
}

- (void)updatePosition {
    CGFloat width = self.bounds.size.width;
    CGFloat viewport = fmax(0, width - 16);
    CGFloat overflow = fmax(0, self.textWidth - viewport);
    if (overflow > 0 && self.line.length > 0) {
        if (!self.timer) {
            __weak SpotifastMarqueeView *weakSelf = self;
            self.timer = [NSTimer timerWithTimeInterval:self.reducedMotion ? 0.25 : 1.0 / 30.0
                repeats:YES
                block:^(NSTimer *timer) {
                    (void)timer;
                    [weakSelf updatePosition];
                }];
            [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        }
    } else if (self.timer) {
        [self.timer invalidate];
        self.timer = nil;
    }
    double elapsed = [NSProcessInfo processInfo].systemUptime - self.started;
    CGFloat offset = spotifast_marquee_offset(overflow, viewport, elapsed,
                                              self.reducedMotion);
    CGFloat x = overflow > 0 ? 8 - offset : (width - self.textWidth) / 2;
    self.label.frame = NSMakeRect(x, (self.bounds.size.height - 22) / 2,
                                  self.textWidth, 22);
}

@end

@interface NSTouchBar (SpotifastSystemModal)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar
                        placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

@interface NSTouchBarItem (SpotifastControlStrip)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

typedef void (*ControlStripPresence)(NSTouchBarItemIdentifier, BOOL);
typedef void (*ModalCloseBox)(BOOL);

static ControlStripPresence controlStripPresence;
static ModalCloseBox modalCloseBox;
static BOOL privateAPIAvailable(void) {
    static dispatch_once_t once;
    static BOOL available;
    dispatch_once(&once, ^{
        void *framework = dlopen(
            "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (!framework) return;
        controlStripPresence = (ControlStripPresence)dlsym(
            framework, "DFRElementSetControlStripPresenceForIdentifier"
        );
        modalCloseBox = (ModalCloseBox)dlsym(
            framework, "DFRSystemModalShowsCloseBoxWhenFrontMost"
        );
        available = controlStripPresence && modalCloseBox
            && [NSTouchBar respondsToSelector:@selector(
                presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]
            && [NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)]
            && [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]
            && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)];
    });
    return available;
}

static NSTouchBarItemIdentifier const lyricIdentifier = @"rocks.spotifast.lyrics";
static NSTouchBarItemIdentifier const trayIdentifier = @"rocks.spotifast.lyrics.tray";

@interface SpotifastTouchBar : NSObject <NSTouchBarDelegate>
@property(nonatomic, strong) NSTouchBar *bar;
@property(nonatomic, strong) SpotifastMarqueeView *marquee;
@property(nonatomic, strong) NSCustomTouchBarItem *trayItem;
@property(nonatomic, strong) id activationObserver;
- (void)showLine:(NSString *)line reducedMotion:(BOOL)reducedMotion;
- (void)tearDown;
@end

@implementation SpotifastTouchBar

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    self.marquee = [[SpotifastMarqueeView alloc]
        initWithFrame:NSMakeRect(0, 0, 650, 30)
                 font:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium]];
    self.bar = [NSTouchBar new];
    self.bar.delegate = self;
    self.bar.defaultItemIdentifiers = @[lyricIdentifier];
    self.bar.principalItemIdentifier = lyricIdentifier;

    self.trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:trayIdentifier];
    self.trayItem.view = [NSButton buttonWithTitle:@"♫"
                                           target:self
                                           action:@selector(reveal:)];
    [NSTouchBarItem addSystemTrayItem:self.trayItem];
    controlStripPresence(trayIdentifier, YES);

    __weak SpotifastTouchBar *weakSelf = self;
    self.activationObserver = [[NSWorkspace sharedWorkspace].notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
        (void)notification;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                       dispatch_get_main_queue(), ^{
            [weakSelf present];
        });
    }];
    [self present];
    return self;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)bar
      makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)bar;
    if (![identifier isEqualToString:lyricIdentifier]) return nil;
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    item.view = self.marquee;
    item.customizationLabel = @"Spotifast Lyrics";
    return item;
}

- (void)present {
    [NSTouchBar presentSystemModalTouchBar:self.bar
                                placement:0
                  systemTrayItemIdentifier:trayIdentifier];
}

- (void)reveal:(id)sender {
    (void)sender;
    [self present];
}

- (void)showLine:(NSString *)line reducedMotion:(BOOL)reducedMotion {
    [self.marquee showLine:line reducedMotion:reducedMotion];
}

- (void)tearDown {
    [self.marquee showLine:@"" reducedMotion:NO];
    if (self.activationObserver) {
        [[NSWorkspace sharedWorkspace].notificationCenter
            removeObserver:self.activationObserver];
        self.activationObserver = nil;
    }
    [NSTouchBar dismissSystemModalTouchBar:self.bar];
    controlStripPresence(trayIdentifier, NO);
    [NSTouchBarItem removeSystemTrayItem:self.trayItem];
    self.trayItem = nil;
}

@end

void spotifast_touch_bar_sync(int enabled, const char *line, int reducedMotion) {
    if (![NSThread isMainThread]) return;
    static SpotifastTouchBar *presenter;
    @autoreleasepool {
        if (!enabled) {
            [presenter tearDown];
            presenter = nil;
            return;
        }
        if (!privateAPIAvailable()) return;
        if (!presenter) presenter = [SpotifastTouchBar new];
        NSString *text = line ? [NSString stringWithUTF8String:line] : nil;
        [presenter showLine:text ?: @"" reducedMotion:reducedMotion != 0];
    }
}
