// A persistent Touch Bar is only possible through the unsupported system-modal
// and Control Strip APIs. Keep that boundary in one macOS-only translation unit.
// The presentation approach follows Touch Bar Lyrics:
// https://github.com/iqbalrahman-jpg/mac-touchbar-lyric
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>

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
@property(nonatomic, strong) NSTextField *label;
@property(nonatomic, strong) NSCustomTouchBarItem *trayItem;
@property(nonatomic, strong) id activationObserver;
- (void)showLine:(NSString *)line;
- (void)tearDown;
@end

@implementation SpotifastTouchBar

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    self.label = [NSTextField labelWithString:@""];
    self.label.frame = NSMakeRect(8, 4, 634, 22);
    self.label.autoresizingMask = NSViewWidthSizable;
    self.label.alignment = NSTextAlignmentCenter;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    self.label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
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
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 650, 30)];
    [container addSubview:self.label];
    item.view = container;
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

- (void)showLine:(NSString *)line {
    if (![self.label.stringValue isEqualToString:line]) {
        self.label.stringValue = line;
    }
}

- (void)tearDown {
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

void spotifast_touch_bar_sync(int enabled, const char *line) {
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
        [presenter showLine:text ?: @""];
    }
}
