//  ReadTabViewController.m
//  Read a region of flash and save to file.

#import "ReadTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

@implementation ReadTabViewController {
    NSTextField *_addrField;
    NSTextField *_lenField;
    NSTextField *_outPathField;
    NSButton    *_readButton;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0,0,620,440)];
    self.view = root;

    NSTextField *title = [NSTextField labelWithString:@"Read Flash to File"];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:title];

    // Address
    NSTextField *addrLabel = [NSTextField labelWithString:@"Start address (hex):"];
    addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:addrLabel];

    _addrField = [NSTextField textFieldWithString:@"0x000000"];
    _addrField.translatesAutoresizingMaskIntoConstraints = NO;
    _addrField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [root addSubview:_addrField];

    // Length
    NSTextField *lenLabel = [NSTextField labelWithString:@"Length (hex bytes):"];
    lenLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:lenLabel];

    _lenField = [NSTextField textFieldWithString:@"0x400000"];
    _lenField.translatesAutoresizingMaskIntoConstraints = NO;
    _lenField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    [root addSubview:_lenField];

    // Output path
    NSTextField *outLabel = [NSTextField labelWithString:@"Save to:"];
    outLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:outLabel];

    _outPathField = [NSTextField textFieldWithString:@""];
    _outPathField.placeholderString = @"Choose output file…";
    _outPathField.editable = NO;
    _outPathField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_outPathField];

    NSButton *chooseBtn = [NSButton buttonWithTitle:@"Choose…" target:self action:@selector(_chooseOut:)];
    chooseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:chooseBtn];

    _readButton = [NSButton buttonWithTitle:@"Read Flash" target:self action:@selector(_read:)];
    _readButton.bezelStyle = NSBezelStyleRounded;
    _readButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_readButton];

    // Constraints (use a grid-style layout)
    NSArray *cols = @[@160, @120];  // label width, field width — unused here, use anchors

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor    constraintEqualToAnchor:root.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],

        [addrLabel.topAnchor     constraintEqualToAnchor:title.bottomAnchor constant:24],
        [addrLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor  constant:20],
        [addrLabel.widthAnchor   constraintEqualToConstant:160],

        [_addrField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:8],
        [_addrField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [_addrField.widthAnchor   constraintEqualToConstant:120],

        [lenLabel.topAnchor     constraintEqualToAnchor:addrLabel.bottomAnchor constant:12],
        [lenLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:20],
        [lenLabel.widthAnchor   constraintEqualToConstant:160],

        [_lenField.leadingAnchor constraintEqualToAnchor:lenLabel.trailingAnchor constant:8],
        [_lenField.centerYAnchor constraintEqualToAnchor:lenLabel.centerYAnchor],
        [_lenField.widthAnchor   constraintEqualToConstant:120],

        [outLabel.topAnchor     constraintEqualToAnchor:lenLabel.bottomAnchor constant:20],
        [outLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:20],
        [outLabel.widthAnchor   constraintEqualToConstant:80],

        [_outPathField.leadingAnchor constraintEqualToAnchor:outLabel.trailingAnchor constant:8],
        [_outPathField.trailingAnchor constraintEqualToAnchor:chooseBtn.leadingAnchor constant:-8],
        [_outPathField.centerYAnchor constraintEqualToAnchor:outLabel.centerYAnchor],

        [chooseBtn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [chooseBtn.centerYAnchor  constraintEqualToAnchor:outLabel.centerYAnchor],

        [_readButton.topAnchor    constraintEqualToAnchor:outLabel.bottomAnchor constant:24],
        [_readButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:20],
        [_readButton.widthAnchor  constraintEqualToConstant:160],
    ]];
    (void)cols;
}

- (void)_chooseOut:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"flash_dump.bin";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK && panel.URL) {
            self->_outPathField.stringValue = panel.URL.path;
        }
    }];
}

- (void)_read:(id)sender
{
    NSString *outPath = _outPathField.stringValue;
    if (!outPath.length) { [self updateStatus:@"Choose an output file first."]; return; }

    NSString *addrStr = [_addrField.stringValue stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    NSString *lenStr  = [_lenField.stringValue  stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    uint32_t addr = (uint32_t)strtoul(addrStr.UTF8String, NULL, 16);
    uint32_t len  = (uint32_t)strtoul(lenStr.UTF8String,  NULL, 16);

    if (len == 0) { [self updateStatus:@"Length must be > 0."]; return; }

    [self.windowController setOperationActive:YES];
    [self updateStatus:@"Reading…"];
    [self updateProgress:0];

    [[MDMADevice sharedDevice] readFlashAtAddress:addr
                                           length:len
                                         progress:^(double f, NSString *st) {
        [self updateProgress:f];
        [self updateStatus:st];
    } completion:^(NSData *data, NSError *err) {
        [self operationDone];
        if (err || !data) {
            [self updateStatus:[NSString stringWithFormat:@"Read failed: %@", err.localizedDescription]];
            return;
        }
        NSError *writeErr;
        [data writeToFile:outPath options:NSDataWritingAtomic error:&writeErr];
        if (writeErr) {
            [self updateStatus:[NSString stringWithFormat:@"Save failed: %@", writeErr.localizedDescription]];
        } else {
            [self updateStatus:[NSString stringWithFormat:@"Read complete — %lu bytes saved.", (unsigned long)data.length]];
        }
    }];
}

@end
