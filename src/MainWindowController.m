//  MainWindowController.m  — NSToolbar-based tab navigation

#import "MainWindowController.h"
#import "MDMADevice.h"

#import "tabs/WriteTabViewController.h"
#import "tabs/ReadTabViewController.h"
#import "tabs/EraseTabViewController.h"
#import "tabs/WiFiTabViewController.h"
#import "tabs/InfoTabViewController.h"
#import "tabs/FlashRecoveryTabViewController.h"

static NSString * const kToolbarIdentifier = @"MDMAToolbar";

// Toolbar item identifiers
static NSString * const kItemWrite  = @"Write";
static NSString * const kItemRead   = @"Read";
static NSString * const kItemErase  = @"Erase";
static NSString * const kItemWiFi   = @"WiFi";
static NSString * const kItemInfo     = @"Info";
static NSString * const kItemRecovery = @"Recovery";

@interface MainWindowController () <NSToolbarDelegate>
@end

@implementation MainWindowController {
    // Child view controllers
    WriteTabViewController  *_writeVC;
    ReadTabViewController   *_readVC;
    EraseTabViewController  *_eraseVC;
    WiFiTabViewController   *_wifiVC;
    InfoTabViewController            *_infoVC;
    FlashRecoveryTabViewController   *_recoveryVC;
    NSViewController        *_currentVC;

    // Status area
    NSTextField             *_statusLabel;
    NSProgressIndicator     *_progressBar;
    NSButton                *_cancelButton;

    // Connection indicator
    NSTextField             *_connLabel;

    // Content view (area above status bar)
    NSView                  *_contentArea;
}

- (instancetype)init
{
    // Build the window now and pass it in — avoids NIB loading path entirely
    NSRect frame = NSMakeRect(0, 0, 640, 500);
    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable;
    NSWindow *win = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO];
    self = [super initWithWindow:win];
    if (self) [self _setup];
    return self;
}

- (void)_setup
{
    NSWindow *win = self.window;
    win.title = @"MegaDrive Programmer";
    win.minSize = NSMakeSize(540, 420);
    win.delegate = self;
    win.releasedWhenClosed = NO;
    [win center];

    [self _buildToolbar];
    [self _buildContentView];
    [self _buildStatusBar];
    [self _selectItem:kItemInfo];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_deviceConnected:)
                                                 name:MDMADeviceConnectedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_deviceDisconnected:)
                                                 name:MDMADeviceDisconnectedNotification
                                               object:nil];
    [self _updateConnectionLabel];
}

// ---------------------------------------------------------------------------
#pragma mark - Build UI
// ---------------------------------------------------------------------------

- (void)_buildToolbar
{
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:kToolbarIdentifier];
    tb.delegate = self;
    tb.allowsUserCustomization = NO;
    tb.autosavesConfiguration = NO;
    tb.displayMode = NSToolbarDisplayModeIconAndLabel;
    [self.window setToolbar:tb];
}

- (void)_buildContentView
{
    NSView *root = self.window.contentView;

    // Content area sits above the status strip (40px at bottom)
    _contentArea = [[NSView alloc] initWithFrame:NSZeroRect];
    _contentArea.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_contentArea];

    [NSLayoutConstraint activateConstraints:@[
        [_contentArea.topAnchor constraintEqualToAnchor:root.topAnchor],
        [_contentArea.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [_contentArea.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [_contentArea.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-40],
    ]];

    // Build child VCs (lazy)
    _writeVC = [[WriteTabViewController alloc] initWithWindowController:self];
    _readVC  = [[ReadTabViewController  alloc] initWithWindowController:self];
    _eraseVC = [[EraseTabViewController alloc] initWithWindowController:self];
    _wifiVC  = [[WiFiTabViewController  alloc] initWithWindowController:self];
    _infoVC      = [[InfoTabViewController           alloc] initWithWindowController:self];
    _recoveryVC  = [[FlashRecoveryTabViewController  alloc] initWithWindowController:self];
}

- (void)_buildStatusBar
{
    NSView *root = self.window.contentView;

    // Hairline separator
    NSBox *sep = [[NSBox alloc] initWithFrame:NSZeroRect];
    sep.boxType = NSBoxSeparator;
    sep.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:sep];

    // Connection indicator (right-aligned)
    _connLabel = [NSTextField labelWithString:@"● Programmer Disconnected"];
    _connLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _connLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _connLabel.textColor = [NSColor secondaryLabelColor];
    [root addSubview:_connLabel];

    // Progress bar (hidden initially)
    _progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _progressBar.style = NSProgressIndicatorStyleBar;
    _progressBar.indeterminate = NO;
    _progressBar.minValue = 0; _progressBar.maxValue = 1;
    _progressBar.doubleValue = 0;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    _progressBar.hidden = YES;
    [root addSubview:_progressBar];

    // Status label
    _statusLabel = [NSTextField labelWithString:@"Ready"];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [NSFont systemFontOfSize:11];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [root addSubview:_statusLabel];

    // Cancel button
    _cancelButton = [NSButton buttonWithTitle:@"Cancel"
                                       target:self
                                       action:@selector(_cancel:)];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.hidden = YES;
    _cancelButton.controlSize = NSControlSizeSmall;
    [root addSubview:_cancelButton];

    [NSLayoutConstraint activateConstraints:@[
        // Separator
        [sep.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor],
        [sep.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [sep.bottomAnchor   constraintEqualToAnchor:root.bottomAnchor constant:-40],

        // Connection label — right side, vertically centred in strip
        [_connLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],
        [_connLabel.centerYAnchor  constraintEqualToAnchor:root.bottomAnchor   constant:-20],

        // Cancel button — left of conn label
        [_cancelButton.trailingAnchor constraintEqualToAnchor:_connLabel.leadingAnchor constant:-8],
        [_cancelButton.centerYAnchor  constraintEqualToAnchor:_connLabel.centerYAnchor],

        // Progress bar — fills left portion
        [_progressBar.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor  constant:8],
        [_progressBar.trailingAnchor constraintEqualToAnchor:_cancelButton.leadingAnchor constant:-8],
        [_progressBar.centerYAnchor  constraintEqualToAnchor:_connLabel.centerYAnchor],

        // Status label — same space as progress bar when bar is hidden
        [_statusLabel.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:8],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:_cancelButton.leadingAnchor constant:-8],
        [_statusLabel.centerYAnchor  constraintEqualToAnchor:_connLabel.centerYAnchor],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - Tab switching
// ---------------------------------------------------------------------------

- (void)_selectItem:(NSString *)identifier
{
    NSViewController *vc;
    if      ([identifier isEqual:kItemWrite]) vc = _writeVC;
    else if ([identifier isEqual:kItemRead])  vc = _readVC;
    else if ([identifier isEqual:kItemErase]) vc = _eraseVC;
    else if ([identifier isEqual:kItemWiFi])     vc = _wifiVC;
    else if ([identifier isEqual:kItemRecovery]) vc = _recoveryVC;
    else                                         vc = _infoVC;

    if (vc == _currentVC) return;

    // Remove old
    if (_currentVC) {
        [_currentVC.view removeFromSuperview];
        [_currentVC removeFromParentViewController];
    }
    _currentVC = vc;

    NSView *v = vc.view;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentArea addSubview:v];

    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor    constraintEqualToAnchor:_contentArea.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:_contentArea.bottomAnchor],
        [v.leadingAnchor  constraintEqualToAnchor:_contentArea.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:_contentArea.trailingAnchor],
    ]];
}

// ---------------------------------------------------------------------------
#pragma mark - NSToolbarDelegate
// ---------------------------------------------------------------------------

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb
{
    return @[kItemWrite, kItemRead, kItemErase, kItemWiFi, kItemInfo, kItemRecovery];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb
{
    return @[kItemWrite, kItemRead, kItemErase, kItemWiFi, kItemInfo, kItemRecovery];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
     itemForItemIdentifier:(NSToolbarItemIdentifier)ident
 willBeInsertedIntoToolbar:(BOOL)flag
{
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    item.label = ident;
    item.paletteLabel = ident;
    item.target = self;
    item.action = @selector(_toolbarItemClicked:);

    NSString *sfName = nil;
    if      ([ident isEqual:kItemWrite]) sfName = @"square.and.arrow.down";
    else if ([ident isEqual:kItemRead])  sfName = @"square.and.arrow.up";
    else if ([ident isEqual:kItemErase]) sfName = @"trash";
    else if ([ident isEqual:kItemWiFi])  sfName = @"wifi";
    else if ([ident isEqual:kItemRecovery]) sfName = @"bandage";
    else                                    sfName = @"info.circle";

    item.image = [NSImage imageWithSystemSymbolName:sfName
                              accessibilityDescription:ident];
    return item;
}

- (void)_toolbarItemClicked:(NSToolbarItem *)item
{
    [self _selectItem:item.itemIdentifier];
}

// ---------------------------------------------------------------------------
#pragma mark - Public interface
// ---------------------------------------------------------------------------

- (void)setStatus:(NSString *)message
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.stringValue = message ?: @"";
    });
}

- (void)setProgress:(double)fraction
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (fraction < 0) {
            self->_progressBar.hidden = YES;
            self->_statusLabel.hidden = NO;
        } else {
            self->_progressBar.hidden = NO;
            self->_statusLabel.hidden = YES;
            self->_progressBar.doubleValue = fraction;
        }
    });
}

- (void)setOperationActive:(BOOL)active
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_cancelButton.hidden = !active;
        if (!active) {
            [self setProgress:-1];
        }
    });
}

- (void)_cancel:(id)sender
{
    [[MDMADevice sharedDevice] cancelCurrentOperation];
    [self setStatus:@"Cancelled."];
    [self setOperationActive:NO];
}

// ---------------------------------------------------------------------------
#pragma mark - Device notifications
// ---------------------------------------------------------------------------

- (void)_deviceConnected:(NSNotification *)note
{
    [self _updateConnectionLabel];
    [self setStatus:@"Device connected."];
}

- (void)_deviceDisconnected:(NSNotification *)note
{
    [self _updateConnectionLabel];
    [self setStatus:@"Device disconnected — waiting for reconnect…"];
}

- (void)_updateConnectionLabel
{
    BOOL conn = [MDMADevice sharedDevice].connected;
    _connLabel.stringValue = conn ? @"● Programmer Connected" : @"● Programmer Disconnected";
    _connLabel.textColor   = conn ? [NSColor systemGreenColor]
                                  : [NSColor secondaryLabelColor];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
