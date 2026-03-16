//  InfoTabViewController.m
//  Device information and quick-action panel.
//
//  Shows: firmware version, flash IDs, flash layout, pushbutton state.
//  Provides cart-type selector (MegaWiFi / FrugalMapper) and Bootloader entry.
//  Auto-prompts cart-type selection when device has more than one driver key.

#import "InfoTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

@implementation InfoTabViewController {
    NSTextView        *_infoTextView;
    NSButton          *_refreshButton;
    NSButton          *_bootloaderButton;
    NSSegmentedControl *_cartTypeControl;
    NSTextField        *_cartTypeLabel;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0,0,620,440)];
    self.view = root;

    NSTextField *title = [NSTextField labelWithString:@"Device Info"];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:title];

    // --- Cart type selector ---
    _cartTypeLabel = [NSTextField labelWithString:@"Cartridge type:"];
    _cartTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_cartTypeLabel];

    _cartTypeControl = [[NSSegmentedControl alloc] init];
    [_cartTypeControl setSegmentCount:2];
    [_cartTypeControl setLabel:@"MegaWiFi"     forSegment:0];
    [_cartTypeControl setLabel:@"FrugalMapper" forSegment:1];
    _cartTypeControl.selectedSegment = 0;
    _cartTypeControl.target = self;
    _cartTypeControl.action = @selector(_cartTypeChanged:);
    _cartTypeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_cartTypeControl];

    // --- Buttons ---
    _refreshButton = [NSButton buttonWithTitle:@"Refresh" target:self action:@selector(_refresh:)];
    _refreshButton.bezelStyle = NSBezelStyleRounded;
    _refreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_refreshButton];

    _bootloaderButton = [NSButton buttonWithTitle:@"Enter Bootloader"
                                           target:self
                                           action:@selector(_enterBootloader:)];
    _bootloaderButton.bezelStyle = NSBezelStyleRounded;
    _bootloaderButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_bootloaderButton];

    // --- Scrollable text view ---
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:scroll];

    _infoTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _infoTextView.editable = NO;
    _infoTextView.selectable = YES;
    _infoTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _infoTextView.backgroundColor = [NSColor textBackgroundColor];
    _infoTextView.textContainerInset = NSMakeSize(4, 4);
    scroll.documentView = _infoTextView;

    [NSLayoutConstraint activateConstraints:@[
        // Row 1: title
        [title.topAnchor     constraintEqualToAnchor:root.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],

        // Row 2: cart type label + segmented control
        [_cartTypeLabel.topAnchor    constraintEqualToAnchor:title.bottomAnchor constant:14],
        [_cartTypeLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],

        [_cartTypeControl.centerYAnchor constraintEqualToAnchor:_cartTypeLabel.centerYAnchor],
        [_cartTypeControl.leadingAnchor constraintEqualToAnchor:_cartTypeLabel.trailingAnchor constant:8],

        // Row 3: action buttons
        [_refreshButton.topAnchor     constraintEqualToAnchor:_cartTypeLabel.bottomAnchor constant:12],
        [_refreshButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor           constant:20],

        [_bootloaderButton.centerYAnchor constraintEqualToAnchor:_refreshButton.centerYAnchor],
        [_bootloaderButton.leadingAnchor constraintEqualToAnchor:_refreshButton.trailingAnchor constant:8],

        // Scrollview fills the rest
        [scroll.topAnchor    constraintEqualToAnchor:_refreshButton.bottomAnchor constant:12],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12],
    ]];

    // Device notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_deviceConnected:)
                                                 name:MDMADeviceConnectedNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_deviceDisconnected:)
                                                 name:MDMADeviceDisconnectedNotification
                                               object:nil];

    [self _appendLine:@"Connect the MDMA cartridge to populate this panel."];
}

// ---------------------------------------------------------------------------
#pragma mark - Notifications
// ---------------------------------------------------------------------------

- (void)_deviceConnected:(NSNotification *)note
{
    [self _refresh:nil];
    // Auto-prompt if multiple driver keys
    MDMAInitInfo *info = [MDMADevice sharedDevice].deviceInfo;
    if (info && info.driverKeys.count > 1) {
        [self _promptCartTypeWithKeys:info.driverKeys];
    }
}

- (void)_deviceDisconnected:(NSNotification *)note
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_infoTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
    });
    [self _appendLine:@"Device disconnected."];
}

// ---------------------------------------------------------------------------
#pragma mark - Cart type
// ---------------------------------------------------------------------------

- (void)_cartTypeChanged:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No device connected."];
        return;
    }
    uint8_t type = (_cartTypeControl.selectedSegment == 0) ? 1 : 2; // 1=MegaWiFi 2=FrugalMapper
    [[MDMADevice sharedDevice] setCartType:type completion:^(NSError *err) {
        if (err) {
            [self updateStatus:[NSString stringWithFormat:@"Cart type change failed: %@",
                err.localizedDescription]];
        } else {
            [self updateStatus:_cartTypeControl.selectedSegment == 0
                ? @"Cartridge type: MegaWiFi"
                : @"Cartridge type: FrugalMapper"];
        }
    }];
}

- (void)_promptCartTypeWithKeys:(NSArray<NSNumber*> *)keys
{
    // Present an alert letting the user choose which driver to activate
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Multiple Cartridge Types Detected";
    alert.informativeText = @"The programmer supports more than one cartridge type. Select which one is installed.";
    [alert addButtonWithTitle:@"MegaWiFi"];
    [alert addButtonWithTitle:@"FrugalMapper"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleInformational;

    NSWindow *win = self.view.window;
    if (!win) { return; }   // view not yet in a window — skip the prompt
    [alert beginSheetModalForWindow:win completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn || r == NSAlertSecondButtonReturn) {
            NSInteger seg = (r == NSAlertFirstButtonReturn) ? 0 : 1;
            self->_cartTypeControl.selectedSegment = seg;
            [self _cartTypeChanged:nil];
        }
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Refresh
// ---------------------------------------------------------------------------

- (void)_appendLine:(NSString *)line
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString *add = [[NSAttributedString alloc]
            initWithString:[line stringByAppendingString:@"\n"]
                attributes:@{
                    NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: [NSColor labelColor]
                }];
        [self->_infoTextView.textStorage appendAttributedString:add];
        [self->_infoTextView scrollToEndOfDocument:nil];
    });
}

- (void)_refresh:(id)sender
{
    MDMADevice *dev = [MDMADevice sharedDevice];
    if (!dev.connected) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_infoTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
        });
        [self _appendLine:@"Not connected."];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_infoTextView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
    });

    MDMAInitInfo *info = dev.deviceInfo;
    if (info) {
        [self _appendLine:[NSString stringWithFormat:@"Programmer:  v%u.%u.%u",
            info.verMajor, info.verMinor, info.verMicro]];
        [self _appendLine:[NSString stringWithFormat:@"Drivers:     %u", info.numDrivers]];

        NSMutableString *keyStr = [NSMutableString string];
        for (NSNumber *k in info.driverKeys)
            [keyStr appendFormat:@"%@  ", k];
        [self _appendLine:[NSString stringWithFormat:@"Driver keys: %@", keyStr]];

        // Sync cart type control with actual first key
        if (info.driverKeys.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                uint8_t firstKey = [info.driverKeys[0] unsignedCharValue];
                self->_cartTypeControl.selectedSegment = (firstKey == 2) ? 1 : 0;
            });
        }
    }

    [dev queryFlashIDsWithCompletion:^(uint8_t manId, uint8_t d0, uint8_t d1, uint8_t d2, NSError *err) {
        if (err) {
            [self _appendLine:[NSString stringWithFormat:@"Flash IDs:   error — %@",
                err.localizedDescription]];
        } else {
            [self _appendLine:[NSString stringWithFormat:
                @"Flash IDs:   MAN=%02X  D0=%02X  D1=%02X  D2=%02X",
                manId, d0, d1, d2]];
        }

        [dev queryFlashLayoutWithCompletion:^(MDMAFlashLayout *layout, NSError *lerr) {
            if (lerr || !layout) {
                [self _appendLine:[NSString stringWithFormat:@"Flash layout: error — %@",
                    lerr.localizedDescription]];
            } else {
                [self _appendLine:[NSString stringWithFormat:
                    @"Flash size:  %u bytes  (%.1f MB)", layout.totalLen,
                    layout.totalLen / 1048576.0]];
                for (MDMAFlashRegion *r in layout.regions) {
                    [self _appendLine:[NSString stringWithFormat:
                        @"  Region:   start=0x%06X  sectors=%u  sector_len=%u B",
                        r.startAddr, r.numSectors, r.sectorLen]];
                }
            }

            uint8_t btn = 0;
            if ([dev readPushbuttonState:&btn]) {
                [self _appendLine:[NSString stringWithFormat:@"Pushbutton:  %@",
                    btn ? @"PRESSED" : @"not pressed"]];
            }
            [self _appendLine:@"\nMegaDrive Memory Administration (MDMA)"];
            [self _appendLine:@"by doragasu / mikewolak, 2015–2026"];
        }];
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Bootloader
// ---------------------------------------------------------------------------

- (void)_enterBootloader:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No device connected."];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Enter DFU Bootloader Mode?";
    alert.informativeText =
        @"The programmer will enter DFU bootloader mode. "
        @"Use a DFU utility such as dfu_flash to update the AVR firmware.\n\n"
        @"The device will disconnect after this operation.";
    [alert addButtonWithTitle:@"Enter Bootloader"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r) {
        if (r != NSAlertFirstButtonReturn) return;

        [self.windowController setOperationActive:YES];
        [self updateStatus:@"Entering bootloader — device will disconnect…"];

        [[MDMADevice sharedDevice] enterBootloaderWithCompletion:^(NSError *err) {
            [self operationDone];
            [self updateStatus:err
                ? [NSString stringWithFormat:@"Bootloader entry failed: %@", err.localizedDescription]
                : @"Device entered DFU bootloader. Use dfu_flash to update firmware."];
        }];
    }];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
