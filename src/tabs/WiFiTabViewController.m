//  WiFiTabViewController.m — ESP WiFi firmware flash (app UART commands removed)

#import "WiFiTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

@implementation WiFiTabViewController {
    NSTextField   *_fwPathField;
    NSTextField   *_fwAddrField;
    NSPopUpButton *_spiModePopUp;
    NSButton      *_flashButton;
}

- (void)loadView
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 620, 460)];
    scroll.hasVerticalScroller   = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.autohidesScrollers    = YES;
    scroll.drawsBackground       = NO;
    self.view = scroll;

    NSView *root = [[NSView alloc] init];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = root;
    [root.widthAnchor constraintEqualToAnchor:scroll.widthAnchor].active = YES;

    // ── Controls ──────────────────────────────────────────────────────────

    NSTextField *fwTitle = [NSTextField labelWithString:@"Flash WiFi Firmware (ESP8266/ESP32-C3)"];
    fwTitle.font = [NSFont boldSystemFontOfSize:13];
    fwTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:fwTitle];

    NSTextField *fwFileLabel = [NSTextField labelWithString:@"Firmware file:"];
    fwFileLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:fwFileLabel];

    _fwPathField = [NSTextField textFieldWithString:@""];
    _fwPathField.placeholderString = @"No file selected";
    _fwPathField.editable = NO;
    _fwPathField.bezeled  = NO;
    _fwPathField.drawsBackground = NO;
    _fwPathField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_fwPathField];

    NSButton *browseBtn = [NSButton buttonWithTitle:@"Browse…" target:self action:@selector(_browse:)];
    browseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:browseBtn];

    NSTextField *addrLabel = [NSTextField labelWithString:@"Flash address:"];
    addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:addrLabel];

    _fwAddrField = [NSTextField textFieldWithString:@"0x00000"];
    _fwAddrField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _fwAddrField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_fwAddrField];

    NSTextField *spiLabel = [NSTextField labelWithString:@"SPI mode:"];
    spiLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:spiLabel];

    _spiModePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_spiModePopUp addItemsWithTitles:@[@"DIO (0)", @"DOUT (1)", @"QIO (2)", @"QOUT (3)"]];
    _spiModePopUp.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_spiModePopUp];

    _flashButton = [NSButton buttonWithTitle:@"Flash Firmware" target:self action:@selector(_flash:)];
    _flashButton.bezelStyle = NSBezelStyleRounded;
    _flashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_flashButton];

    // ── Constraints ───────────────────────────────────────────────────────
    const CGFloat L  = 16;
    const CGFloat R  = -16;
    const CGFloat lw = 120;
    const CGFloat rh = 26;
    const CGFloat rs = 8;
    const CGFloat ss = 16;

    [NSLayoutConstraint activateConstraints:@[
        [fwTitle.topAnchor      constraintEqualToAnchor:root.topAnchor constant:ss],
        [fwTitle.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:L],

        [fwFileLabel.topAnchor     constraintEqualToAnchor:fwTitle.bottomAnchor constant:rs],
        [fwFileLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],
        [fwFileLabel.widthAnchor   constraintEqualToConstant:lw],
        [fwFileLabel.heightAnchor  constraintEqualToConstant:rh],

        [browseBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:R],
        [browseBtn.centerYAnchor  constraintEqualToAnchor:fwFileLabel.centerYAnchor],

        [_fwPathField.leadingAnchor  constraintEqualToAnchor:fwFileLabel.trailingAnchor constant:8],
        [_fwPathField.trailingAnchor constraintEqualToAnchor:browseBtn.leadingAnchor constant:-8],
        [_fwPathField.centerYAnchor  constraintEqualToAnchor:fwFileLabel.centerYAnchor],

        [addrLabel.topAnchor     constraintEqualToAnchor:fwFileLabel.bottomAnchor constant:rs],
        [addrLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],
        [addrLabel.widthAnchor   constraintEqualToConstant:lw],
        [addrLabel.heightAnchor  constraintEqualToConstant:rh],

        [_fwAddrField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:8],
        [_fwAddrField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [_fwAddrField.widthAnchor   constraintEqualToConstant:110],

        [spiLabel.topAnchor     constraintEqualToAnchor:addrLabel.bottomAnchor constant:rs],
        [spiLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],
        [spiLabel.widthAnchor   constraintEqualToConstant:lw],
        [spiLabel.heightAnchor  constraintEqualToConstant:rh],

        [_spiModePopUp.leadingAnchor constraintEqualToAnchor:spiLabel.trailingAnchor constant:8],
        [_spiModePopUp.centerYAnchor constraintEqualToAnchor:spiLabel.centerYAnchor],
        [_spiModePopUp.widthAnchor   constraintEqualToConstant:180],

        [_flashButton.topAnchor     constraintEqualToAnchor:spiLabel.bottomAnchor constant:rs + 4],
        [_flashButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],
        [_flashButton.widthAnchor   constraintEqualToConstant:160],

        // Bottom anchor so scroll view knows the content height
        [_flashButton.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-(ss)],
    ]];
}

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

@end
