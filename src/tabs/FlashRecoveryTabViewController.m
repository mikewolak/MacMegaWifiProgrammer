//  FlashRecoveryTabViewController.m
//
//  One-click recovery: full erase + write + verify of the bundled
//  wflash loader firmware (wflash.bin @ 0x000000, complete 8 MB image).

#import "FlashRecoveryTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

@implementation FlashRecoveryTabViewController {
    NSButton *_recoverButton;
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

    NSString *infoStr = [NSString stringWithFormat:
        @"Restores the wflash WiFi loader firmware embedded in this app.\n\n"
        @"Connect the USB programmer dongle, then click Recover. The entire "
        @"flash will be erased and the complete wflash image written from "
        @"address 0x000000.\n\n"
        @"Bundled image: wflash.bin  —  %lu bytes  (%.2f MB)",
        (unsigned long)binSize, binSize / 1048576.0];

    NSTextField *infoText = [NSTextField wrappingLabelWithString:infoStr];
    infoText.font = [NSFont systemFontOfSize:12];
    infoText.translatesAutoresizingMaskIntoConstraints = NO;
    [infoBox addSubview:infoText];

    // ── Separator ──────────────────────────────────────────────────────────
    NSBox *div = [[NSBox alloc] init];
    div.boxType = NSBoxSeparator;
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div];

    // ── Recover button ─────────────────────────────────────────────────────
    _recoverButton = [NSButton buttonWithTitle:@"Recover wflash Loader"
                                        target:self action:@selector(_recover:)];
    _recoverButton.bezelStyle  = NSBezelStyleRounded;
    _recoverButton.keyEquivalent = @"\r";
    _recoverButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_recoverButton];

    // ── Constraints ────────────────────────────────────────────────────────
    const CGFloat L = 20, R = -20, ss = 14, rs = 10;

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

        [div.topAnchor      constraintEqualToAnchor:infoBox.bottomAnchor constant:ss],
        [div.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:8],
        [div.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:-8],
        [div.heightAnchor   constraintEqualToConstant:1],

        [_recoverButton.topAnchor     constraintEqualToAnchor:div.bottomAnchor    constant:rs],
        [_recoverButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor  constant:L],
        [_recoverButton.widthAnchor   constraintEqualToConstant:220],
    ]];
}

// ── Action ────────────────────────────────────────────────────────────────────

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

    NSURL *binURL = [[NSBundle mainBundle] URLForResource:@"wflash" withExtension:@"bin"];
    NSData *data  = binURL ? [NSData dataWithContentsOfURL:binURL] : nil;
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

    NSLog(@"[Recovery] wflash.bin loaded: %lu bytes from %@", (unsigned long)data.length, binURL.path);

    [self.windowController setOperationActive:YES];
    [self updateStatus:@"Starting recovery — erasing flash…"];
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
            NSLog(@"[Recovery] complete — wflash loader restored.");
            [self updateStatus:@"Recovery complete — wflash loader restored. Remove and reinsert the cart."];
        }
    }];
}

@end
