//  FlashRecoveryTabViewController.m
//
//  One-click recovery for the wflash loader firmware embedded in the app.
//  Reflashes head (reset vectors at 0x000000) and/or tail (wflash program
//  at 0x7F0000) via the USB programmer dongle without needing any files.

#import "FlashRecoveryTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"
#import <CommonCrypto/CommonDigest.h>

#include "wflash_head.h"   // wflash_head[], wflash_head_len  — 512 bytes @ 0x000000
#include "wflash_tail.h"   // wflash_tail[], wflash_tail_len  — 65536 bytes @ 0x7F0000

static NSString *md5OfData(const void *bytes, NSUInteger len) {
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(bytes, (CC_LONG)len, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [s appendFormat:@"%02x", digest[i]];
    return s;
}

#define WFLASH_HEAD_ADDR  0x000000
#define WFLASH_TAIL_ADDR  0x7F0000

@implementation FlashRecoveryTabViewController {
    NSButton     *_flashHeadButton;
    NSButton     *_flashTailButton;
    NSButton     *_flashBothButton;
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

    NSTextField *infoText = [NSTextField wrappingLabelWithString:
        @"Use these controls to recover the wflash WiFi loader firmware embedded "
        @"in this app. Connect the USB programmer dongle, then choose what to reflash.\n\n"
        @"Head (512 B @ 0x000000): reset vectors — required if the cart boots "
        @"directly into a game and the wflash download menu is gone.\n\n"
        @"Tail (64 KB @ 0x7F0000): the wflash download menu program itself — "
        @"required if the menu appears corrupted or absent.\n\n"
        @"Flash Both restores the complete loader in one step."];
    infoText.font = [NSFont systemFontOfSize:12];
    infoText.translatesAutoresizingMaskIntoConstraints = NO;
    [infoBox addSubview:infoText];

    // ── Version label ──────────────────────────────────────────────────────
    NSTextField *verLabel = [NSTextField labelWithString:
        [NSString stringWithFormat:@"Embedded firmware: head %u B  |  tail %u B",
         wflash_head_len, wflash_tail_len]];
    verLabel.font      = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    verLabel.textColor = [NSColor secondaryLabelColor];
    verLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:verLabel];

    // ── Separator ──────────────────────────────────────────────────────────
    NSBox *div = [[NSBox alloc] init];
    div.boxType = NSBoxSeparator;
    div.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div];

    // ── Buttons ────────────────────────────────────────────────────────────
    _flashHeadButton = [NSButton buttonWithTitle:@"Flash Head  (0x000000, 512 B)"
                                          target:self action:@selector(_flashHead:)];
    _flashHeadButton.bezelStyle = NSBezelStyleRounded;
    _flashHeadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_flashHeadButton];

    _flashTailButton = [NSButton buttonWithTitle:@"Flash Tail  (0x7F0000, 64 KB)"
                                          target:self action:@selector(_flashTail:)];
    _flashTailButton.bezelStyle = NSBezelStyleRounded;
    _flashTailButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_flashTailButton];

    _flashBothButton = [NSButton buttonWithTitle:@"Flash Both  (full loader restore)"
                                          target:self action:@selector(_flashBoth:)];
    _flashBothButton.bezelStyle = NSBezelStyleRounded;
    _flashBothButton.keyEquivalent = @"\r";
    _flashBothButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_flashBothButton];

    // ── Constraints ────────────────────────────────────────────────────────
    const CGFloat L = 20, R = -20, ss = 14, rs = 10;

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor     constraintEqualToAnchor:root.topAnchor   constant:20],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],

        [infoBox.topAnchor      constraintEqualToAnchor:title.bottomAnchor  constant:12],
        [infoBox.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:L],
        [infoBox.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:R],

        [infoText.topAnchor      constraintEqualToAnchor:infoBox.topAnchor      constant:12],
        [infoText.leadingAnchor  constraintEqualToAnchor:infoBox.leadingAnchor  constant:12],
        [infoText.trailingAnchor constraintEqualToAnchor:infoBox.trailingAnchor constant:-12],
        [infoText.bottomAnchor   constraintEqualToAnchor:infoBox.bottomAnchor   constant:-12],

        [verLabel.topAnchor     constraintEqualToAnchor:infoBox.bottomAnchor constant:rs],
        [verLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:L],

        [div.topAnchor      constraintEqualToAnchor:verLabel.bottomAnchor constant:ss],
        [div.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor     constant:8],
        [div.trailingAnchor constraintEqualToAnchor:root.trailingAnchor    constant:-8],
        [div.heightAnchor   constraintEqualToConstant:1],

        [_flashHeadButton.topAnchor     constraintEqualToAnchor:div.bottomAnchor    constant:ss],
        [_flashHeadButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor  constant:L],
        [_flashHeadButton.widthAnchor   constraintEqualToConstant:240],

        [_flashTailButton.topAnchor     constraintEqualToAnchor:_flashHeadButton.bottomAnchor constant:rs],
        [_flashTailButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor             constant:L],
        [_flashTailButton.widthAnchor   constraintEqualToConstant:240],

        [_flashBothButton.topAnchor     constraintEqualToAnchor:_flashTailButton.bottomAnchor constant:rs + 4],
        [_flashBothButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor             constant:L],
        [_flashBothButton.widthAnchor   constraintEqualToConstant:240],
    ]];
}

// ── Actions ───────────────────────────────────────────────────────────────────

- (void)_flashHead:(id)sender { [self _recover:YES tail:NO]; }
- (void)_flashTail:(id)sender { [self _recover:NO  tail:YES]; }
- (void)_flashBoth:(id)sender { [self _recover:YES tail:YES]; }

- (void)_recover:(BOOL)doHead tail:(BOOL)doTail
{
    if (![MDMADevice sharedDevice].connected) {
        NSAlert *a = [[NSAlert alloc] init];
        a.messageText     = @"Programmer Not Connected";
        a.informativeText = @"Connect the USB programmer dongle and try again.";
        [a addButtonWithTitle:@"OK"];
        [a beginSheetModalForWindow:self.view.window completionHandler:nil];
        return;
    }

    NSString *what = (doHead && doTail) ? @"head + tail" : doHead ? @"head" : @"tail";
    NSLog(@"[Recovery] starting: doHead=%d doTail=%d (%@)", doHead, doTail, what);
    NSLog(@"[Recovery] head: addr=0x%06X len=%u md5=%@", WFLASH_HEAD_ADDR, wflash_head_len,
          md5OfData(wflash_head, wflash_head_len));
    NSLog(@"[Recovery] tail: addr=0x%06X len=%u md5=%@", WFLASH_TAIL_ADDR, wflash_tail_len,
          md5OfData(wflash_tail, wflash_tail_len));

    [self.windowController setOperationActive:YES];
    [self updateStatus:[NSString stringWithFormat:@"Recovering %@…", what]];
    [self updateProgress:0];

    [self _runRecovery:doHead tail:doTail step:0 totalSteps:(doHead ? 1 : 0) + (doTail ? 1 : 0)];
}

- (void)_runRecovery:(BOOL)doHead tail:(BOOL)doTail step:(int)step totalSteps:(int)total
{
    NSLog(@"[Recovery] _runRecovery: doHead=%d doTail=%d step=%d total=%d", doHead, doTail, step, total);

    if (doHead) {
        NSData *data = [NSData dataWithBytesNoCopy:(void *)wflash_head
                                            length:wflash_head_len
                                      freeWhenDone:NO];
        NSLog(@"[Recovery] writing head: %u bytes at 0x%06X", wflash_head_len, WFLASH_HEAD_ADDR);
        [self updateStatus:@"Erasing + writing head (0x000000, 512 B)…"];

        [[MDMADevice sharedDevice] writeFlashData:data
                                        atAddress:WFLASH_HEAD_ADDR
                                        autoErase:YES
                                           verify:YES
                                         progress:^(double f, NSString *st) {
            double overall = ((double)step + f) / total;
            [self updateProgress:overall];
            [self updateStatus:st];
        } completion:^(NSError *err) {
            if (err) {
                NSLog(@"[Recovery] HEAD FAILED: %@", err.localizedDescription);
                [self operationDone];
                [self updateStatus:[NSString stringWithFormat:@"Head flash FAILED: %@",
                                    err.localizedDescription]];
                return;
            }
            NSLog(@"[Recovery] head write+verify OK — now running MD5 readback");
            [self updateStatus:@"Head written — reading back for MD5 check…"];

            // MD5 readback verification
            [[MDMADevice sharedDevice] readFlashAtAddress:WFLASH_HEAD_ADDR
                                                   length:wflash_head_len
                                                 progress:nil
                                               completion:^(NSData *rb, NSError *re) {
                if (re || !rb) {
                    NSLog(@"[Recovery] head readback failed: %@", re.localizedDescription);
                    [self updateStatus:@"Head MD5 readback failed — flash may be incomplete."];
                } else {
                    NSString *expectedMD5 = md5OfData(wflash_head, wflash_head_len);
                    NSString *actualMD5   = md5OfData(rb.bytes, rb.length);
                    BOOL match = [expectedMD5 isEqualToString:actualMD5];
                    NSLog(@"[Recovery] head MD5 expected: %@", expectedMD5);
                    NSLog(@"[Recovery] head MD5 actual:   %@", actualMD5);
                    NSLog(@"[Recovery] head MD5 match: %@", match ? @"YES ✓" : @"NO ✗");
                    if (!match) {
                        [self operationDone];
                        [self updateStatus:[NSString stringWithFormat:
                            @"Head MD5 MISMATCH — flash corrupted!\n"
                            @"expected: %@\nactual:   %@", expectedMD5, actualMD5]];
                        return;
                    }
                    [self updateStatus:[NSString stringWithFormat:@"Head OK ✓  md5:%@", expectedMD5]];
                }

                if (doTail) {
                    [self _runRecovery:NO tail:YES step:step+1 totalSteps:total];
                } else {
                    [self operationDone];
                    NSLog(@"[Recovery] complete (head only)");
                }
            }];
        }];
        return;
    }

    if (doTail) {
        NSData *data = [NSData dataWithBytesNoCopy:(void *)wflash_tail
                                            length:wflash_tail_len
                                      freeWhenDone:NO];
        NSLog(@"[Recovery] writing tail: %u bytes at 0x%06X", wflash_tail_len, WFLASH_TAIL_ADDR);
        [self updateStatus:@"Erasing + writing tail (0x7F0000, 64 KB)…"];

        [[MDMADevice sharedDevice] writeFlashData:data
                                        atAddress:WFLASH_TAIL_ADDR
                                        autoErase:YES
                                           verify:YES
                                         progress:^(double f, NSString *st) {
            double overall = ((double)step + f) / total;
            [self updateProgress:overall];
            [self updateStatus:st];
        } completion:^(NSError *err) {
            if (err) {
                NSLog(@"[Recovery] TAIL FAILED: %@", err.localizedDescription);
                [self operationDone];
                [self updateStatus:[NSString stringWithFormat:@"Tail flash FAILED: %@",
                                    err.localizedDescription]];
                return;
            }
            NSLog(@"[Recovery] tail write+verify OK — now running MD5 readback");
            [self updateStatus:@"Tail written — reading back for MD5 check…"];

            [[MDMADevice sharedDevice] readFlashAtAddress:WFLASH_TAIL_ADDR
                                                   length:wflash_tail_len
                                                 progress:nil
                                               completion:^(NSData *rb, NSError *re) {
                if (re || !rb) {
                    NSLog(@"[Recovery] tail readback failed: %@", re.localizedDescription);
                    [self updateStatus:@"Tail MD5 readback failed — flash may be incomplete."];
                } else {
                    NSString *expectedMD5 = md5OfData(wflash_tail, wflash_tail_len);
                    NSString *actualMD5   = md5OfData(rb.bytes, rb.length);
                    BOOL match = [expectedMD5 isEqualToString:actualMD5];
                    NSLog(@"[Recovery] tail MD5 expected: %@", expectedMD5);
                    NSLog(@"[Recovery] tail MD5 actual:   %@", actualMD5);
                    NSLog(@"[Recovery] tail MD5 match: %@", match ? @"YES ✓" : @"NO ✗");
                    if (!match) {
                        [self operationDone];
                        [self updateStatus:[NSString stringWithFormat:
                            @"Tail MD5 MISMATCH — flash corrupted!\n"
                            @"expected: %@\nactual:   %@", expectedMD5, actualMD5]];
                        return;
                    }
                    [self updateStatus:[NSString stringWithFormat:@"Tail OK ✓  md5:%@", expectedMD5]];
                }
                [self operationDone];
                NSLog(@"[Recovery] complete");
            }];
        }];
    }
}

@end
