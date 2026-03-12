//  WiFiTabViewController.m
//
//  Two sections separated by a divider:
//    1. ESP firmware flash (file, address, SPI mode)
//    2. AP configuration (slot, SSID, password, PHY, connect/disconnect/status)

#import "WiFiTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

// ── Helpers ───────────────────────────────────────────────────────────────────

static NSTextField *makeLabel(NSString *s) {
    NSTextField *f = [NSTextField labelWithString:s];
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

static NSTextField *makeField(NSString *placeholder) {
    NSTextField *f = [NSTextField textFieldWithString:@""];
    f.placeholderString = placeholder;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

@implementation WiFiTabViewController {
    // Firmware flash
    NSTextField   *_fwPathField;
    NSTextField   *_fwAddrField;
    NSPopUpButton *_spiModePopUp;
    NSButton      *_flashButton;

    // AP config
    NSSegmentedControl *_slotControl;
    NSButton           *_loadAPButton;
    NSTextField        *_ssidField;
    NSSecureTextField  *_passField;
    NSPopUpButton      *_phyPopUp;
    NSButton           *_saveAPButton;
    NSButton           *_joinButton;
    NSButton           *_leaveButton;
    NSButton           *_statusButton;
}

// ── Layout ────────────────────────────────────────────────────────────────────

- (void)loadView
{
    // Outer scroll view so the tab always fits regardless of window height
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 620, 460)];
    scroll.hasVerticalScroller   = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers    = YES;
    scroll.drawsBackground       = NO;
    self.view = scroll;

    NSView *root = [[NSView alloc] init];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = root;

    // Pin root width to scroll view width so it doesn't scroll horizontally
    [root.widthAnchor constraintEqualToAnchor:scroll.widthAnchor].active = YES;

    // ── Labels / controls ──────────────────────────────────────────────────

    // Section 1 heading
    NSTextField *fwTitle = makeLabel(@"Flash WiFi Firmware (ESP8266/ESP32-C3)");
    fwTitle.font = [NSFont boldSystemFontOfSize:13];
    [root addSubview:fwTitle];

    // File row
    NSTextField *fwFileLabel = makeLabel(@"Firmware file:");
    [root addSubview:fwFileLabel];

    _fwPathField = makeField(@"No file selected");
    _fwPathField.editable = NO;
    _fwPathField.bezeled  = NO;
    _fwPathField.drawsBackground = NO;
    [root addSubview:_fwPathField];

    NSButton *browseBtn = [NSButton buttonWithTitle:@"Browse…" target:self action:@selector(_browse:)];
    browseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:browseBtn];

    // Address row
    NSTextField *addrLabel = makeLabel(@"Flash address:");
    [root addSubview:addrLabel];

    _fwAddrField = makeField(@"0x00000");
    _fwAddrField.stringValue = @"0x00000";
    _fwAddrField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [root addSubview:_fwAddrField];

    // SPI mode row
    NSTextField *spiLabel = makeLabel(@"SPI mode:");
    [root addSubview:spiLabel];

    _spiModePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_spiModePopUp addItemsWithTitles:@[@"DIO (0)", @"DOUT (1)", @"QIO (2)", @"QOUT (3)"]];
    _spiModePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_spiModePopUp];

    // Flash button
    _flashButton = [NSButton buttonWithTitle:@"Flash Firmware" target:self action:@selector(_flash:)];
    _flashButton.bezelStyle = NSBezelStyleRounded;
    _flashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_flashButton];

    // ── Divider ────────────────────────────────────────────────────────────
    NSBox *divider = [[NSBox alloc] init];
    divider.boxType = NSBoxSeparator;
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:divider];

    // ── Section 2: AP Configuration ───────────────────────────────────────
    NSTextField *apTitle = makeLabel(@"WiFi Network Configuration");
    apTitle.font = [NSFont boldSystemFontOfSize:13];
    [root addSubview:apTitle];

    // Slot row
    NSTextField *slotLabel = makeLabel(@"Config slot:");
    [root addSubview:slotLabel];

    _slotControl = [[NSSegmentedControl alloc] init];
    [_slotControl setSegmentCount:3];
    [_slotControl setLabel:@"Slot 0" forSegment:0];
    [_slotControl setLabel:@"Slot 1" forSegment:1];
    [_slotControl setLabel:@"Slot 2" forSegment:2];
    _slotControl.selectedSegment = 0;
    _slotControl.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_slotControl];

    _loadAPButton = [NSButton buttonWithTitle:@"Load" target:self action:@selector(_loadAP:)];
    _loadAPButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_loadAPButton];

    // SSID row
    NSTextField *ssidLabel = makeLabel(@"SSID:");
    [root addSubview:ssidLabel];

    _ssidField = makeField(@"Network name");
    [root addSubview:_ssidField];

    // Password row
    NSTextField *passLabel = makeLabel(@"Password:");
    [root addSubview:passLabel];

    _passField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    _passField.placeholderString = @"WiFi password";
    _passField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_passField];

    // PHY row
    NSTextField *phyLabel = makeLabel(@"PHY type:");
    [root addSubview:phyLabel];

    _phyPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_phyPopUp addItemsWithTitles:@[@"802.11b/g/n (auto)", @"802.11b/g", @"802.11b only"]];
    _phyPopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_phyPopUp];

    // Action buttons
    _saveAPButton = [NSButton buttonWithTitle:@"Save Config"   target:self action:@selector(_saveAP:)];
    _joinButton   = [NSButton buttonWithTitle:@"Connect"       target:self action:@selector(_join:)];
    _leaveButton  = [NSButton buttonWithTitle:@"Disconnect"    target:self action:@selector(_leave:)];
    _statusButton = [NSButton buttonWithTitle:@"Check Status"  target:self action:@selector(_status:)];
    for (NSButton *b in @[_saveAPButton, _joinButton, _leaveButton, _statusButton]) {
        b.bezelStyle = NSBezelStyleRounded;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [root addSubview:b];
    }

    // ── Constraints ────────────────────────────────────────────────────────
    const CGFloat L  = 16;   // left margin
    const CGFloat R  = -16;  // right margin (negative for trailing)
    const CGFloat lw = 120;  // label column width
    const CGFloat rh = 26;   // row height for controls
    const CGFloat rs = 8;    // row spacing
    const CGFloat ss = 16;   // section spacing

    // Helper: pin a label (leading) and a control (leading = label.trailing + 8)
    // all with centerY relative to an anchor view (the label).

    [NSLayoutConstraint activateConstraints:@[
        // ── Section 1 ──
        [fwTitle.topAnchor      constraintEqualToAnchor:root.topAnchor     constant:ss],
        [fwTitle.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:L],

        // File row
        [fwFileLabel.topAnchor      constraintEqualToAnchor:fwTitle.bottomAnchor constant:rs],
        [fwFileLabel.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:L],
        [fwFileLabel.widthAnchor    constraintEqualToConstant:lw],
        [fwFileLabel.heightAnchor   constraintEqualToConstant:rh],

        [browseBtn.trailingAnchor   constraintEqualToAnchor:root.trailingAnchor  constant:R],
        [browseBtn.centerYAnchor    constraintEqualToAnchor:fwFileLabel.centerYAnchor],

        [_fwPathField.leadingAnchor  constraintEqualToAnchor:fwFileLabel.trailingAnchor constant:8],
        [_fwPathField.trailingAnchor constraintEqualToAnchor:browseBtn.leadingAnchor    constant:-8],
        [_fwPathField.centerYAnchor  constraintEqualToAnchor:fwFileLabel.centerYAnchor],

        // Address row
        [addrLabel.topAnchor     constraintEqualToAnchor:fwFileLabel.bottomAnchor constant:rs],
        [addrLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor       constant:L],
        [addrLabel.widthAnchor   constraintEqualToConstant:lw],
        [addrLabel.heightAnchor  constraintEqualToConstant:rh],

        [_fwAddrField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:8],
        [_fwAddrField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [_fwAddrField.widthAnchor   constraintEqualToConstant:110],

        // SPI row
        [spiLabel.topAnchor     constraintEqualToAnchor:addrLabel.bottomAnchor constant:rs],
        [spiLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:L],
        [spiLabel.widthAnchor   constraintEqualToConstant:lw],
        [spiLabel.heightAnchor  constraintEqualToConstant:rh],

        [_spiModePopUp.leadingAnchor constraintEqualToAnchor:spiLabel.trailingAnchor constant:8],
        [_spiModePopUp.centerYAnchor constraintEqualToAnchor:spiLabel.centerYAnchor],
        [_spiModePopUp.widthAnchor   constraintEqualToConstant:180],

        // Flash button
        [_flashButton.topAnchor     constraintEqualToAnchor:spiLabel.bottomAnchor constant:rs + 4],
        [_flashButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:L],
        [_flashButton.widthAnchor   constraintEqualToConstant:160],

        // ── Divider ──
        [divider.topAnchor      constraintEqualToAnchor:_flashButton.bottomAnchor constant:ss],
        [divider.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor        constant:8],
        [divider.trailingAnchor constraintEqualToAnchor:root.trailingAnchor       constant:-8],
        [divider.heightAnchor   constraintEqualToConstant:1],

        // ── Section 2 ──
        [apTitle.topAnchor     constraintEqualToAnchor:divider.bottomAnchor constant:ss],
        [apTitle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:L],

        // Slot row
        [slotLabel.topAnchor     constraintEqualToAnchor:apTitle.bottomAnchor constant:rs],
        [slotLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:L],
        [slotLabel.widthAnchor   constraintEqualToConstant:lw],
        [slotLabel.heightAnchor  constraintEqualToConstant:rh],

        [_slotControl.leadingAnchor constraintEqualToAnchor:slotLabel.trailingAnchor constant:8],
        [_slotControl.centerYAnchor constraintEqualToAnchor:slotLabel.centerYAnchor],

        [_loadAPButton.leadingAnchor constraintEqualToAnchor:_slotControl.trailingAnchor constant:8],
        [_loadAPButton.centerYAnchor constraintEqualToAnchor:slotLabel.centerYAnchor],

        // SSID row
        [ssidLabel.topAnchor     constraintEqualToAnchor:slotLabel.bottomAnchor constant:rs],
        [ssidLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:L],
        [ssidLabel.widthAnchor   constraintEqualToConstant:lw],
        [ssidLabel.heightAnchor  constraintEqualToConstant:rh],

        [_ssidField.leadingAnchor  constraintEqualToAnchor:ssidLabel.trailingAnchor constant:8],
        [_ssidField.trailingAnchor constraintEqualToAnchor:root.trailingAnchor      constant:R],
        [_ssidField.centerYAnchor  constraintEqualToAnchor:ssidLabel.centerYAnchor],

        // Password row
        [passLabel.topAnchor     constraintEqualToAnchor:ssidLabel.bottomAnchor constant:rs],
        [passLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:L],
        [passLabel.widthAnchor   constraintEqualToConstant:lw],
        [passLabel.heightAnchor  constraintEqualToConstant:rh],

        [_passField.leadingAnchor  constraintEqualToAnchor:passLabel.trailingAnchor constant:8],
        [_passField.trailingAnchor constraintEqualToAnchor:root.trailingAnchor      constant:R],
        [_passField.centerYAnchor  constraintEqualToAnchor:passLabel.centerYAnchor],

        // PHY row
        [phyLabel.topAnchor     constraintEqualToAnchor:passLabel.bottomAnchor constant:rs],
        [phyLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:L],
        [phyLabel.widthAnchor   constraintEqualToConstant:lw],
        [phyLabel.heightAnchor  constraintEqualToConstant:rh],

        [_phyPopUp.leadingAnchor constraintEqualToAnchor:phyLabel.trailingAnchor constant:8],
        [_phyPopUp.centerYAnchor constraintEqualToAnchor:phyLabel.centerYAnchor],
        [_phyPopUp.widthAnchor   constraintEqualToConstant:220],

        // Action buttons row
        [_saveAPButton.topAnchor     constraintEqualToAnchor:phyLabel.bottomAnchor constant:rs + 4],
        [_saveAPButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:L],

        [_joinButton.leadingAnchor  constraintEqualToAnchor:_saveAPButton.trailingAnchor constant:8],
        [_joinButton.centerYAnchor  constraintEqualToAnchor:_saveAPButton.centerYAnchor],

        [_leaveButton.leadingAnchor constraintEqualToAnchor:_joinButton.trailingAnchor  constant:8],
        [_leaveButton.centerYAnchor constraintEqualToAnchor:_saveAPButton.centerYAnchor],

        [_statusButton.leadingAnchor constraintEqualToAnchor:_leaveButton.trailingAnchor constant:8],
        [_statusButton.centerYAnchor constraintEqualToAnchor:_saveAPButton.centerYAnchor],

        // Bottom anchor so scroll view knows the content height
        [_saveAPButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-(ss)],
    ]];
}

// ── Firmware flash ──────────────────────────────────────────────────────────

- (void)_browse:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = @"Choose ESP firmware .bin file";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK && panel.URL)
            self->_fwPathField.stringValue = panel.URL.path;
    }];
}

- (void)_flash:(id)sender
{
    NSString *path = _fwPathField.stringValue;
    if (!path.length) { [self updateStatus:@"Select a firmware file first."]; return; }

    NSString *addrStr = [_fwAddrField.stringValue stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    uint32_t addr = (uint32_t)strtoul(addrStr.UTF8String, NULL, 16);
    int spiMode   = (int)[_spiModePopUp indexOfSelectedItem];

    [self.windowController setOperationActive:YES];
    [self updateStatus:@"Entering bootloader…"];
    [self updateProgress:0];

    [[MDMADevice sharedDevice] flashWiFiFirmwareAtPath:path address:addr spiMode:spiMode
        progress:^(double f, NSString *st) { [self updateProgress:f]; [self updateStatus:st]; }
      completion:^(NSError *err) {
        [self operationDone];
        [self updateStatus:err
            ? [NSString stringWithFormat:@"Flash failed: %@", err.localizedDescription]
            : @"WiFi firmware flashed successfully."];
    }];
}

// ── AP configuration ─────────────────────────────────────────────────────────

- (void)_loadAP:(id)sender
{
    uint8_t slot = (uint8_t)_slotControl.selectedSegment;
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No USB device connected."]; return;
    }
    [self updateStatus:[NSString stringWithFormat:@"Loading AP config slot %u…", slot]];
    [[MDMADevice sharedDevice] getAPConfigSlot:slot completion:^(NSString *ssid, NSString *pass, NSError *err) {
        if (err) { [self updateStatus:[NSString stringWithFormat:@"Load failed: %@", err.localizedDescription]]; return; }
        self->_ssidField.stringValue = ssid ?: @"";
        self->_passField.stringValue = pass ?: @"";
        [self updateStatus:[NSString stringWithFormat:@"Loaded slot %u: SSID = %@", slot, ssid]];
    }];
}

- (void)_saveAP:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No USB device connected."]; return;
    }
    NSString *ssid = _ssidField.stringValue;
    if (!ssid.length) { [self updateStatus:@"Enter an SSID."]; return; }
    uint8_t slot = (uint8_t)_slotControl.selectedSegment;
    uint8_t phyMap[] = {7, 3, 1};  // BGN, BG, B
    uint8_t phy = phyMap[[_phyPopUp indexOfSelectedItem]];

    [self updateStatus:@"Saving AP configuration…"];
    [[MDMADevice sharedDevice] setAPConfigSlot:slot ssid:ssid password:_passField.stringValue phy:phy
                                    completion:^(NSError *err) {
        [self updateStatus:err
            ? [NSString stringWithFormat:@"Save failed: %@", err.localizedDescription]
            : [NSString stringWithFormat:@"AP config saved to slot %u.", slot]];
    }];
}

- (void)_join:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No USB device connected."]; return;
    }
    uint8_t slot = (uint8_t)_slotControl.selectedSegment;
    [self updateStatus:[NSString stringWithFormat:@"Connecting to AP (slot %u)…", slot]];
    [[MDMADevice sharedDevice] joinAPSlot:slot completion:^(NSError *err) {
        [self updateStatus:err
            ? [NSString stringWithFormat:@"Connect failed: %@", err.localizedDescription]
            : @"Join command sent — use Check Status to confirm."];
    }];
}

- (void)_leave:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No USB device connected."]; return;
    }
    [self updateStatus:@"Disconnecting from AP…"];
    [[MDMADevice sharedDevice] leaveAPWithCompletion:^(NSError *err) {
        [self updateStatus:err
            ? [NSString stringWithFormat:@"Disconnect failed: %@", err.localizedDescription]
            : @"Disconnected from AP."];
    }];
}

- (void)_status:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        [self updateStatus:@"No USB device connected."]; return;
    }
    [self updateStatus:@"Querying WiFi status…"];
    [[MDMADevice sharedDevice] getWiFiStatusWithCompletion:^(uint8_t stat, NSString *str, NSError *err) {
        [self updateStatus:err
            ? [NSString stringWithFormat:@"Status error: %@", err.localizedDescription]
            : (str ?: @"No status")];
    }];
}

@end
