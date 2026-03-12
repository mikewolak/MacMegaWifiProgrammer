//  FlashRecoveryTabViewController.m
//
//  One-click recovery: full erase + write + verify of the bundled
//  wflash loader firmware (wflash.bin @ 0x000000, complete 8 MB image).

#import "FlashRecoveryTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"
#import <CommonCrypto/CommonDigest.h>

// Bundled firmware metadata
#define WFLASH_VERSION    @"v1.2"
#define WFLASH_MD5        @"3593bdeac241dc26200b07c118eab81f"
#define WFLASH_PKG_URL    @"https://gitlab.com/doragasu/mw-wflash/-/packages/50903297"

static NSString *md5OfData(NSData *data) {
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
#pragma clang diagnostic pop
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [s appendFormat:@"%02x", digest[i]];
    return s;
}

@implementation FlashRecoveryTabViewController {
    NSButton     *_recoverButton;
    NSButton     *_customButton;
    NSTextField  *_customPathField;
    NSData       *_customData;   // non-nil when user has chosen an override file
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 480)];
    self.view = root;

    // ── Title ──────────────────────────────────────────────────────────────
    NSTextField *title = [NSTextField labelWithString:@"Flash Recovery"];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:title];

    // ── Info box ───────────────────────────────────────────────────────────
    NSBox *infoBox = [[NSBox alloc] init];
    infoBox.boxType      = NSBoxCustom;
    infoBox.cornerRadius = 6;
    infoBox.borderColor  = [NSColor systemOrangeColor];
    infoBox.fillColor    = [[NSColor systemOrangeColor] colorWithAlphaComponent:0.08];
    infoBox.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:infoBox];

    NSURL *binURL = [[NSBundle mainBundle] URLForResource:@"wflash" withExtension:@"bin"];
    NSDictionary *attrs = binURL ? [[NSFileManager defaultManager]
                                    attributesOfItemAtPath:binURL.path error:nil] : nil;
    NSUInteger binSize = [attrs[NSFileSize] unsignedIntegerValue];

    NSTextField *infoText = [NSTextField wrappingLabelWithString:
        @"Restores the wflash WiFi loader firmware embedded in this app. "
        @"Connect the USB programmer dongle, then click Recover. The entire "
        @"flash will be erased and the complete wflash image written from address 0x000000."];
    infoText.font = [NSFont systemFontOfSize:12];
    infoText.translatesAutoresizingMaskIntoConstraints = NO;
    [infoBox addSubview:infoText];

    // ── Firmware metadata row ──────────────────────────────────────────────
    NSTextField *verLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Version: %@    Size: %lu bytes (%.2f MB)    MD5: %@",
         WFLASH_VERSION, (unsigned long)binSize, binSize / 1048576.0, WFLASH_MD5]];
    verLabel.font      = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    verLabel.textColor = [NSColor secondaryLabelColor];
    verLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:verLabel];

    // ── Clickable source URL ───────────────────────────────────────────────
    NSButton *urlButton = [NSButton buttonWithTitle:WFLASH_PKG_URL
                                             target:self action:@selector(_openURL:)];
    urlButton.bezelStyle = NSBezelStyleInline;
    urlButton.font       = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [urlButton setButtonType:NSButtonTypeMomentaryPushIn];
    urlButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:urlButton];

    // ── Separator ──────────────────────────────────────────────────────────
    NSBox *div = [[NSBox alloc] init];
    div.boxType = NSBoxSeparator;
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div];

    // ── Recover button ─────────────────────────────────────────────────────
    _recoverButton = [NSButton buttonWithTitle:@"Recover wflash Loader"
                                        target:self action:@selector(_recover:)];
    _recoverButton.bezelStyle    = NSBezelStyleRounded;
    _recoverButton.keyEquivalent = @"\r";
    _recoverButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_recoverButton];

    // ── Custom binary override ─────────────────────────────────────────────
    NSBox *div2 = [[NSBox alloc] init];
    div2.boxType = NSBoxSeparator;
    div2.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div2];

    NSTextField *customLabel = [NSTextField labelWithString:@"Custom Binary Override"];
    customLabel.font      = [NSFont boldSystemFontOfSize:12];
    customLabel.textColor = [NSColor secondaryLabelColor];
    customLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:customLabel];

    NSTextField *customHint = [NSTextField wrappingLabelWithString:
        @"Use any binary instead of the bundled firmware. "
        @"The selected file will replace the bundled image for the next recovery only."];
    customHint.font      = [NSFont systemFontOfSize:11];
    customHint.textColor = [NSColor tertiaryLabelColor];
    customHint.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:customHint];

    _customPathField = [NSTextField textFieldWithString:@""];
    _customPathField.placeholderString = @"No custom file selected — using bundled firmware";
    _customPathField.editable          = NO;
    _customPathField.bezeled           = YES;
    _customPathField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _customPathField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_customPathField];

    _customButton = [NSButton buttonWithTitle:@"Browse…"
                                       target:self action:@selector(_browseCustom:)];
    _customButton.bezelStyle = NSBezelStyleRounded;
    _customButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_customButton];

    NSButton *clearButton = [NSButton buttonWithTitle:@"Clear"
                                               target:self action:@selector(_clearCustom:)];
    clearButton.bezelStyle = NSBezelStyleRounded;
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:clearButton];

    // ── Constraints ────────────────────────────────────────────────────────
    const CGFloat L = 20, R = -20, ss = 14, rs = 8;

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor     constraintEqualToAnchor:root.topAnchor    constant:20],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],

        [infoBox.topAnchor      constraintEqualToAnchor:title.bottomAnchor  constant:12],
        [infoBox.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:L],
        [infoBox.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:R],

        [infoText.topAnchor      constraintEqualToAnchor:infoBox.topAnchor      constant:12],
        [infoText.leadingAnchor  constraintEqualToAnchor:infoBox.leadingAnchor  constant:12],
        [infoText.trailingAnchor constraintEqualToAnchor:infoBox.trailingAnchor constant:-12],
        [infoText.bottomAnchor   constraintEqualToAnchor:infoBox.bottomAnchor   constant:-12],

        [verLabel.topAnchor     constraintEqualToAnchor:infoBox.bottomAnchor constant:rs],
        [verLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:L],

        [urlButton.topAnchor     constraintEqualToAnchor:verLabel.bottomAnchor constant:4],
        [urlButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:L - 4],

        [div.topAnchor      constraintEqualToAnchor:urlButton.bottomAnchor constant:ss],
        [div.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor     constant:8],
        [div.trailingAnchor constraintEqualToAnchor:root.trailingAnchor    constant:-8],
        [div.heightAnchor   constraintEqualToConstant:1],

        [_recoverButton.topAnchor     constraintEqualToAnchor:div.bottomAnchor    constant:rs],
        [_recoverButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor  constant:L],
        [_recoverButton.widthAnchor   constraintEqualToConstant:220],

        [div2.topAnchor      constraintEqualToAnchor:_recoverButton.bottomAnchor constant:ss],
        [div2.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor          constant:8],
        [div2.trailingAnchor constraintEqualToAnchor:root.trailingAnchor         constant:-8],
        [div2.heightAnchor   constraintEqualToConstant:1],

        [customLabel.topAnchor     constraintEqualToAnchor:div2.bottomAnchor    constant:rs],
        [customLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:L],

        [customHint.topAnchor      constraintEqualToAnchor:customLabel.bottomAnchor constant:4],
        [customHint.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor        constant:L],
        [customHint.trailingAnchor constraintEqualToAnchor:root.trailingAnchor       constant:R],

        [_customPathField.topAnchor      constraintEqualToAnchor:customHint.bottomAnchor constant:rs],
        [_customPathField.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor       constant:L],
        [_customPathField.trailingAnchor constraintEqualToAnchor:_customButton.leadingAnchor constant:-8],

        [_customButton.centerYAnchor constraintEqualToAnchor:_customPathField.centerYAnchor],
        [_customButton.trailingAnchor constraintEqualToAnchor:clearButton.leadingAnchor constant:-8],
        [_customButton.widthAnchor   constraintEqualToConstant:80],

        [clearButton.centerYAnchor  constraintEqualToAnchor:_customPathField.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:R],
        [clearButton.widthAnchor    constraintEqualToConstant:60],
    ]];
}

// ── URL link ──────────────────────────────────────────────────────────────────

- (void)_openURL:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:WFLASH_PKG_URL]];
}

// ── Custom binary ─────────────────────────────────────────────────────────────

- (void)_browseCustom:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.message = @"Choose a binary image to flash at 0x000000";
    panel.allowedContentTypes = @[];
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r) {
        if (r != NSModalResponseOK || !panel.URL) return;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL];
        if (!data || !data.length) {
            [self updateStatus:@"Could not read selected file."];
            return;
        }
        self->_customData = data;
        self->_customPathField.stringValue = panel.URL.path;
        NSString *md5 = md5OfData(data);
        [self updateStatus:[NSString stringWithFormat:
            @"Custom: %lu bytes  md5:%@", (unsigned long)data.length, md5]];
        self->_recoverButton.title = @"Flash Custom Binary";
    }];
}

- (void)_clearCustom:(id)sender
{
    _customData = nil;
    _customPathField.stringValue = @"";
    _recoverButton.title = @"Recover wflash Loader";
    [self updateStatus:@"Custom override cleared — will use bundled firmware."];
}

// ── Recover / flash ───────────────────────────────────────────────────────────

- (void)_recover:(id)sender
{
    if (![MDMADevice sharedDevice].connected) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText     = @"Programmer Not Connected";
        a.informativeText = @"Connect the USB programmer dongle and try again.";
        [a addButtonWithTitle:@"OK"];
        NSWindow *win = self.view.window;
        if (win) [a beginSheetModalForWindow:win completionHandler:nil];
        else     [a runModal];
        return;
    }

    NSData *data;
    NSString *label;

    if (_customData) {
        data  = _customData;
        label = [NSString stringWithFormat:@"custom binary (%lu bytes)", (unsigned long)data.length];
    } else {
        NSURL *binURL = [[NSBundle mainBundle] URLForResource:@"wflash" withExtension:@"bin"];
        data = binURL ? [NSData dataWithContentsOfURL:binURL] : nil;
        if (!data || !data.length) {
            NSAlert *a = [[NSAlert alloc] init];
            a.messageText     = @"Firmware Not Found";
            a.informativeText = @"wflash.bin is missing from the app bundle.";
            [a addButtonWithTitle:@"OK"];
            NSWindow *win = self.view.window;
            if (win) [a beginSheetModalForWindow:win completionHandler:nil];
            else     [a runModal];
            return;
        }
        label = [NSString stringWithFormat:@"wflash %@ (%lu bytes)", WFLASH_VERSION,
                 (unsigned long)data.length];
    }

    NSLog(@"[Recovery] flashing %@  md5:%@", label, md5OfData(data));

    [self.windowController setOperationActive:YES];
    [self updateStatus:[NSString stringWithFormat:@"Starting recovery — erasing flash for %@…", label]];
    [self updateProgress:0];

    [[MDMADevice sharedDevice] writeFlashData:data
                                    atAddress:0x000000
                                    autoErase:YES
                                       verify:YES
                                     progress:^(double f, NSString *st) {
        [self updateProgress:f];
        [self updateStatus:st];
    } completion:^(NSError *err) {
        [self operationDone];
        if (err) {
            NSLog(@"[Recovery] FAILED: %@", err.localizedDescription);
            [self updateStatus:[NSString stringWithFormat:@"Recovery FAILED: %@",
                                err.localizedDescription]];
        } else {
            NSLog(@"[Recovery] complete.");
            [self updateStatus:@"Recovery complete — wflash loader restored. Remove and reinsert the cart."];
        }
    }];
}

@end
