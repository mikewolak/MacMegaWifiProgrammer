//  EraseTabViewController.m
//  Full-chip or address-range erase.

#import "EraseTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"

@interface EraseTabViewController ()
- (void)_updateEraseButtonEnabled;
@end

@implementation EraseTabViewController {
    NSButton    *_fullChipRadio;
    NSButton    *_rangeRadio;
    NSTextField *_addrField;
    NSTextField *_lenField;
    NSButton    *_eraseButton;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0,0,620,440)];
    self.view = root;

    NSTextField *title = [NSTextField labelWithString:@"Erase Flash"];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:title];

    _fullChipRadio = [NSButton radioButtonWithTitle:@"Full chip erase" target:self action:@selector(_modeChanged:)];
    _fullChipRadio.state = NSControlStateValueOn;
    _fullChipRadio.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_fullChipRadio];

    _rangeRadio = [NSButton radioButtonWithTitle:@"Erase address range" target:self action:@selector(_modeChanged:)];
    _rangeRadio.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_rangeRadio];

    NSTextField *addrLabel = [NSTextField labelWithString:@"Start address (hex):"];
    addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:addrLabel];

    _addrField = [NSTextField textFieldWithString:@"0x000000"];
    _addrField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _addrField.translatesAutoresizingMaskIntoConstraints = NO;
    _addrField.enabled = NO;
    [root addSubview:_addrField];

    NSTextField *lenLabel = [NSTextField labelWithString:@"Length (hex bytes):"];
    lenLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:lenLabel];

    _lenField = [NSTextField textFieldWithString:@"0x10000"];
    _lenField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _lenField.translatesAutoresizingMaskIntoConstraints = NO;
    _lenField.enabled = NO;
    [root addSubview:_lenField];

    // Warning label
    NSTextField *warn = [NSTextField wrappingLabelWithString:
        @"⚠  Full chip erase can take up to 2 minutes. Do not disconnect the cartridge."];
    warn.textColor = [NSColor systemOrangeColor];
    warn.font = [NSFont systemFontOfSize:11];
    warn.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:warn];

    _eraseButton = [NSButton buttonWithTitle:@"Erase" target:self action:@selector(_erase:)];
    _eraseButton.bezelStyle = NSBezelStyleRounded;
    _eraseButton.translatesAutoresizingMaskIntoConstraints = NO;
    _eraseButton.enabled = [MDMADevice sharedDevice].connected;
    [root addSubview:_eraseButton];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_updateEraseButtonEnabled)
               name:MDMADeviceConnectedNotification    object:nil];
    [nc addObserver:self selector:@selector(_updateEraseButtonEnabled)
               name:MDMADeviceDisconnectedNotification object:nil];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor    constraintEqualToAnchor:root.topAnchor constant:20],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],

        [_fullChipRadio.topAnchor    constraintEqualToAnchor:title.bottomAnchor constant:20],
        [_fullChipRadio.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],

        [_rangeRadio.topAnchor    constraintEqualToAnchor:_fullChipRadio.bottomAnchor constant:8],
        [_rangeRadio.leadingAnchor constraintEqualToAnchor:root.leadingAnchor         constant:20],

        [addrLabel.topAnchor     constraintEqualToAnchor:_rangeRadio.bottomAnchor constant:16],
        [addrLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor        constant:40],
        [addrLabel.widthAnchor   constraintEqualToConstant:160],

        [_addrField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:8],
        [_addrField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [_addrField.widthAnchor   constraintEqualToConstant:120],

        [lenLabel.topAnchor     constraintEqualToAnchor:addrLabel.bottomAnchor constant:12],
        [lenLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:40],
        [lenLabel.widthAnchor   constraintEqualToConstant:160],

        [_lenField.leadingAnchor constraintEqualToAnchor:lenLabel.trailingAnchor constant:8],
        [_lenField.centerYAnchor constraintEqualToAnchor:lenLabel.centerYAnchor],
        [_lenField.widthAnchor   constraintEqualToConstant:120],

        [warn.topAnchor     constraintEqualToAnchor:lenLabel.bottomAnchor constant:20],
        [warn.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:20],
        [warn.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:-20],

        [_eraseButton.topAnchor    constraintEqualToAnchor:warn.bottomAnchor constant:20],
        [_eraseButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [_eraseButton.widthAnchor  constraintEqualToConstant:120],
    ]];
}

- (void)_updateEraseButtonEnabled
{
    _eraseButton.enabled = [MDMADevice sharedDevice].connected;
}

- (void)_modeChanged:(id)sender
{
    BOOL rangeMode = (_rangeRadio.state == NSControlStateValueOn);
    _addrField.enabled = rangeMode;
    _lenField.enabled  = rangeMode;
}

- (void)_erase:(id)sender
{
    [self.windowController setOperationActive:YES];

    if (_fullChipRadio.state == NSControlStateValueOn) {
        [self updateStatus:@"Full chip erase — this may take up to 2 minutes…"];
        [self updateProgress:0];
        [[MDMADevice sharedDevice] eraseFullChipWithProgress:^(double f, NSString *st) {
            [self updateProgress:f];
            [self updateStatus:st];
        } completion:^(NSError *err) {
            [self operationDone];
            [self updateStatus:err ? [NSString stringWithFormat:@"Erase failed: %@", err.localizedDescription]
                               : @"Full chip erase complete."];
        }];
    } else {
        NSString *addrStr = [_addrField.stringValue stringByReplacingOccurrencesOfString:@"0x" withString:@""];
        NSString *lenStr  = [_lenField.stringValue  stringByReplacingOccurrencesOfString:@"0x" withString:@""];
        uint32_t addr = (uint32_t)strtoul(addrStr.UTF8String, NULL, 16);
        uint32_t len  = (uint32_t)strtoul(lenStr.UTF8String,  NULL, 16);

        [self updateStatus:@"Erasing range…"];
        [self updateProgress:0];
        [[MDMADevice sharedDevice] eraseRangeAtAddress:addr
                                                length:len
                                              progress:^(double f, NSString *st) {
            [self updateProgress:f];
            [self updateStatus:st];
        } completion:^(NSError *err) {
            [self operationDone];
            [self updateStatus:err ? [NSString stringWithFormat:@"Erase failed: %@", err.localizedDescription]
                               : @"Range erase complete."];
        }];
    }
}

@end
