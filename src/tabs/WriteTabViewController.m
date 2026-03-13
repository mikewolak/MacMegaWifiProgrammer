//  WriteTabViewController.m
//
//  USB write: ROM → cartridge flash via programmer dongle
//  WiFi write: ROM → Genesis wflash ROM via TCP (port 1989)
//
//  The Genesis wflash ROM accepts ONE TCP connection per session.
//  Connect keeps the socket open; Write uses that socket; socket closes after AUTORUN.

#import "WriteTabViewController.h"
#import "MainWindowController.h"
#import "MDMADevice.h"
#include <unistd.h>   // close()

@implementation WriteTabViewController {
    // Shared file selector
    NSTextField  *_pathField;

    // USB write
    NSTextField  *_addrField;
    NSButton     *_autoEraseCheck;
    NSButton     *_verifyCheck;
    NSButton     *_writeUSBButton;

    // WiFi write
    NSTextField  *_hostField;
    NSTextField  *_portField;
    NSButton     *_connectWiFiButton;
    NSButton     *_writeWiFiButton;

    // Live wflash socket (-1 = not connected)
    int          _wifiSock;
}

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    self = [super initWithWindowController:wc];
    if (self) _wifiSock = -1;
    return self;
}

- (void)dealloc
{
    if (_wifiSock >= 0) { close(_wifiSock); _wifiSock = -1; }
}

// ── Build UI ──────────────────────────────────────────────────────────────────

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 620, 480)];
    self.view = root;

    // ── File selector ──────────────────────────────────────────────────────
    NSTextField *title = [NSTextField labelWithString:@"ROM File"];
    title.font = [NSFont boldSystemFontOfSize:14];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:title];

    NSBox *dropBox = [[NSBox alloc] init];
    dropBox.boxType      = NSBoxCustom;
    dropBox.cornerRadius = 8;
    dropBox.borderColor  = [NSColor separatorColor];
    dropBox.fillColor    = [NSColor windowBackgroundColor];
    dropBox.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:dropBox];

    NSTextField *dropHint = [NSTextField labelWithString:@"Drop ROM file here  —  or use Browse"];
    dropHint.font      = [NSFont systemFontOfSize:13];
    dropHint.textColor = [NSColor tertiaryLabelColor];
    dropHint.translatesAutoresizingMaskIntoConstraints = NO;
    [dropBox addSubview:dropHint];

    _pathField = [NSTextField textFieldWithString:@""];
    _pathField.placeholderString = @"No file selected";
    _pathField.editable          = NO;
    _pathField.bezeled           = NO;
    _pathField.drawsBackground   = NO;
    _pathField.translatesAutoresizingMaskIntoConstraints = NO;
    [dropBox addSubview:_pathField];

    NSButton *browseBtn = [NSButton buttonWithTitle:@"Browse…"
                                             target:self action:@selector(_browse:)];
    browseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [dropBox addSubview:browseBtn];

    // ── USB write section ──────────────────────────────────────────────────
    NSBox *div1 = [[NSBox alloc] init];
    div1.boxType = NSBoxSeparator;
    div1.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div1];

    NSTextField *usbTitle = [NSTextField labelWithString:@"Write via USB (Programmer Dongle)"];
    usbTitle.font = [NSFont boldSystemFontOfSize:13];
    usbTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:usbTitle];

    NSTextField *addrLabel = [NSTextField labelWithString:@"Start address (hex):"];
    addrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:addrLabel];

    _addrField = [NSTextField textFieldWithString:@"0x000000"];
    _addrField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _addrField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_addrField];

    _autoEraseCheck = [NSButton checkboxWithTitle:@"Auto-erase before writing"
                                           target:nil action:nil];
    _autoEraseCheck.state = NSControlStateValueOn;
    _autoEraseCheck.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_autoEraseCheck];

    _verifyCheck = [NSButton checkboxWithTitle:@"Verify after write"
                                        target:nil action:nil];
    _verifyCheck.state = NSControlStateValueOn;
    _verifyCheck.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_verifyCheck];

    _writeUSBButton = [NSButton buttonWithTitle:@"Write ROM via USB"
                                         target:self action:@selector(_writeUSB:)];
    _writeUSBButton.bezelStyle = NSBezelStyleRounded;
    _writeUSBButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_writeUSBButton];

    // ── WiFi write section ─────────────────────────────────────────────────
    NSBox *div2 = [[NSBox alloc] init];
    div2.boxType = NSBoxSeparator;
    div2.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:div2];

    NSTextField *wifiTitle = [NSTextField labelWithString:@"Write via WiFi (Genesis wflash ROM)"];
    wifiTitle.font = [NSFont boldSystemFontOfSize:13];
    wifiTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:wifiTitle];

    NSTextField *hostLabel = [NSTextField labelWithString:@"Genesis IP:"];
    hostLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:hostLabel];

    _hostField = [NSTextField textFieldWithString:@""];
    _hostField.placeholderString = @"192.168.1.x";
    _hostField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _hostField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_hostField];

    NSTextField *portLabel = [NSTextField labelWithString:@"Port:"];
    portLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:portLabel];

    _portField = [NSTextField textFieldWithString:@"1989"];
    _portField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _portField.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_portField];

    _connectWiFiButton = [NSButton buttonWithTitle:@"Connect"
                                            target:self action:@selector(_toggleWiFiConnect:)];
    _connectWiFiButton.bezelStyle = NSBezelStyleRounded;
    _connectWiFiButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_connectWiFiButton];

    _writeWiFiButton = [NSButton buttonWithTitle:@"Write ROM via WiFi"
                                          target:self action:@selector(_writeWiFi:)];
    _writeWiFiButton.bezelStyle = NSBezelStyleRounded;
    _writeWiFiButton.enabled    = NO;   // enabled only when connected
    _writeWiFiButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:_writeWiFiButton];

    // ── Constraints ────────────────────────────────────────────────────────
    const CGFloat L  = 20;
    const CGFloat R  = -20;
    const CGFloat rs = 10;
    const CGFloat ss = 14;

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor      constraintEqualToAnchor:root.topAnchor    constant:20],
        [title.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor constant:L],

        [dropBox.topAnchor      constraintEqualToAnchor:title.bottomAnchor  constant:10],
        [dropBox.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:L],
        [dropBox.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:R],
        [dropBox.heightAnchor   constraintEqualToConstant:72],

        [dropHint.centerXAnchor constraintEqualToAnchor:dropBox.centerXAnchor],
        [dropHint.topAnchor     constraintEqualToAnchor:dropBox.topAnchor constant:10],

        [browseBtn.trailingAnchor constraintEqualToAnchor:dropBox.trailingAnchor constant:-12],
        [browseBtn.bottomAnchor   constraintEqualToAnchor:dropBox.bottomAnchor   constant:-10],

        [_pathField.leadingAnchor  constraintEqualToAnchor:dropBox.leadingAnchor   constant:12],
        [_pathField.trailingAnchor constraintEqualToAnchor:browseBtn.leadingAnchor constant:-8],
        [_pathField.centerYAnchor  constraintEqualToAnchor:browseBtn.centerYAnchor],

        // USB section
        [div1.topAnchor      constraintEqualToAnchor:dropBox.bottomAnchor constant:ss],
        [div1.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor   constant:8],
        [div1.trailingAnchor constraintEqualToAnchor:root.trailingAnchor  constant:-8],
        [div1.heightAnchor   constraintEqualToConstant:1],

        [usbTitle.topAnchor     constraintEqualToAnchor:div1.bottomAnchor  constant:ss],
        [usbTitle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:L],

        [addrLabel.topAnchor     constraintEqualToAnchor:usbTitle.bottomAnchor constant:rs],
        [addrLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor    constant:L],

        [_addrField.leadingAnchor constraintEqualToAnchor:addrLabel.trailingAnchor constant:8],
        [_addrField.centerYAnchor constraintEqualToAnchor:addrLabel.centerYAnchor],
        [_addrField.widthAnchor   constraintEqualToConstant:120],

        [_autoEraseCheck.topAnchor     constraintEqualToAnchor:addrLabel.bottomAnchor constant:rs],
        [_autoEraseCheck.leadingAnchor constraintEqualToAnchor:root.leadingAnchor      constant:L],

        [_verifyCheck.topAnchor     constraintEqualToAnchor:_autoEraseCheck.bottomAnchor constant:6],
        [_verifyCheck.leadingAnchor constraintEqualToAnchor:root.leadingAnchor            constant:L],

        [_writeUSBButton.topAnchor     constraintEqualToAnchor:_verifyCheck.bottomAnchor constant:rs + 4],
        [_writeUSBButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor         constant:L],
        [_writeUSBButton.widthAnchor   constraintEqualToConstant:180],

        // WiFi section
        [div2.topAnchor      constraintEqualToAnchor:_writeUSBButton.bottomAnchor constant:ss],
        [div2.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor            constant:8],
        [div2.trailingAnchor constraintEqualToAnchor:root.trailingAnchor           constant:-8],
        [div2.heightAnchor   constraintEqualToConstant:1],

        [wifiTitle.topAnchor     constraintEqualToAnchor:div2.bottomAnchor    constant:ss],
        [wifiTitle.leadingAnchor constraintEqualToAnchor:root.leadingAnchor   constant:L],

        [hostLabel.topAnchor     constraintEqualToAnchor:wifiTitle.bottomAnchor constant:rs],
        [hostLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor     constant:L],

        [_hostField.leadingAnchor constraintEqualToAnchor:hostLabel.trailingAnchor constant:8],
        [_hostField.centerYAnchor constraintEqualToAnchor:hostLabel.centerYAnchor],
        [_hostField.widthAnchor   constraintEqualToConstant:160],

        [portLabel.leadingAnchor constraintEqualToAnchor:_hostField.trailingAnchor constant:20],
        [portLabel.centerYAnchor constraintEqualToAnchor:hostLabel.centerYAnchor],

        [_portField.leadingAnchor constraintEqualToAnchor:portLabel.trailingAnchor constant:8],
        [_portField.centerYAnchor constraintEqualToAnchor:hostLabel.centerYAnchor],
        [_portField.widthAnchor   constraintEqualToConstant:70],

        [_connectWiFiButton.topAnchor     constraintEqualToAnchor:hostLabel.bottomAnchor constant:rs + 4],
        [_connectWiFiButton.leadingAnchor constraintEqualToAnchor:root.leadingAnchor      constant:L],
        [_connectWiFiButton.widthAnchor   constraintEqualToConstant:120],

        [_writeWiFiButton.leadingAnchor constraintEqualToAnchor:_connectWiFiButton.trailingAnchor constant:12],
        [_writeWiFiButton.centerYAnchor constraintEqualToAnchor:_connectWiFiButton.centerYAnchor],
        [_writeWiFiButton.widthAnchor   constraintEqualToConstant:180],
    ]];

    [dropBox registerForDraggedTypes:@[NSPasteboardTypeFileURL]];

    // Restore last-used IP
    NSString *savedIP = [[NSUserDefaults standardUserDefaults] stringForKey:@"wflashLastIP"];
    if (savedIP.length) _hostField.stringValue = savedIP;
}

// ── Browse ───────────────────────────────────────────────────────────────────

- (void)_browse:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[];
    panel.message = @"Choose a ROM image (.bin, .md, .gen, or raw binary)";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse r) {
        if (r == NSModalResponseOK && panel.URL)
            self->_pathField.stringValue = panel.URL.path;
    }];
}

// ── USB write ─────────────────────────────────────────────────────────────────

- (void)_writeUSB:(id)sender
{
    NSData *data = [self _loadROM];
    if (!data) return;

    if (![MDMADevice sharedDevice].connected) {
        [self _alertTitle:@"No Programmer Connected"
                  message:@"Plug in the MDMA programmer dongle and try again."];
        return;
    }

    NSString *addrStr = [_addrField.stringValue
                         stringByReplacingOccurrencesOfString:@"0x" withString:@""];
    uint32_t addr  = (uint32_t)strtoul(addrStr.UTF8String, NULL, 16);
    BOOL autoErase = (_autoEraseCheck.state == NSControlStateValueOn);
    BOOL verify    = (_verifyCheck.state    == NSControlStateValueOn);

    [self.windowController setOperationActive:YES];
    [self updateStatus:@"Writing via USB…"];
    [self updateProgress:0];

    [[MDMADevice sharedDevice] writeFlashData:data
                                    atAddress:addr
                                    autoErase:autoErase
                                       verify:verify
                                     progress:^(double f, NSString *st) {
        [self updateProgress:f];
        [self updateStatus:st];
    } completion:^(NSError *err) {
        [self operationDone];
        [self updateStatus:err
            ? [NSString stringWithFormat:@"USB write failed: %@", err.localizedDescription]
            : @"USB write complete."];
    }];
}

// ── WiFi connect / disconnect toggle ─────────────────────────────────────────

- (void)_toggleWiFiConnect:(id)sender
{
    if (_wifiSock >= 0) {
        // Disconnect
        close(_wifiSock);
        _wifiSock = -1;
        [self _updateWiFiConnectionState];
        [self updateStatus:@"Disconnected from Genesis."];
        return;
    }

    NSString *host = _hostField.stringValue;
    if (!host.length) {
        [self _alertTitle:@"No IP Address" message:@"Enter the Genesis IP address."]; return;
    }
    uint16_t port = (uint16_t)(_portField.intValue ?: 1989);
    [[NSUserDefaults standardUserDefaults] setObject:host forKey:@"wflashLastIP"];

    _connectWiFiButton.enabled = NO;
    [self updateStatus:[NSString stringWithFormat:@"Connecting to %@:%u…", host, port]];

    [[MDMADevice sharedDevice] connectToWflashHost:host port:port
                                        completion:^(int sock, NSError *err) {
        if (err) {
            self->_connectWiFiButton.enabled = YES;
            [self updateStatus:[NSString stringWithFormat:@"Connect failed: %@",
                               err.localizedDescription]];
        } else {
            self->_wifiSock = sock;
            [self _updateWiFiConnectionState];
            [self updateStatus:[NSString stringWithFormat:
                @"Connected to %@:%u — ready to write.", host, port]];
        }
    }];
}

- (void)_updateWiFiConnectionState
{
    BOOL connected = (_wifiSock >= 0);
    [_connectWiFiButton setTitle:connected ? @"Disconnect" : @"Connect"];
    _connectWiFiButton.enabled = YES;
    _writeWiFiButton.enabled   = YES;   // always enabled — auto-connects if needed
    _hostField.enabled         = !connected;
    _portField.enabled         = !connected;
}

// ── WiFi write ────────────────────────────────────────────────────────────────

- (void)_writeWiFi:(id)sender
{
    NSData *data = [self _loadROM];
    if (!data) return;

    if (_wifiSock < 0) {
        // Auto-connect then write — developer workflow: one button per flash cycle
        NSString *host = _hostField.stringValue;
        if (!host.length) {
            [self _alertTitle:@"No IP Address" message:@"Enter the Genesis IP address first."]; return;
        }
        uint16_t port = (uint16_t)(_portField.intValue ?: 1989);
        [[NSUserDefaults standardUserDefaults] setObject:host forKey:@"wflashLastIP"];

        [self.windowController setOperationActive:YES];
        [self updateStatus:[NSString stringWithFormat:@"Connecting to %@:%u…", host, port]];
        [self updateProgress:0];

        [[MDMADevice sharedDevice] connectToWflashHost:host port:port
                                            completion:^(int sock, NSError *connErr) {
            if (connErr) {
                [self operationDone];
                [self updateStatus:[NSString stringWithFormat:@"Connect failed: %@",
                                   connErr.localizedDescription]];
                return;
            }
            [self _doWriteOnSocket:sock data:data];
        }];
        return;
    }

    int sock = _wifiSock;
    _wifiSock = -1;
    [self _updateWiFiConnectionState];

    [self.windowController setOperationActive:YES];
    [self updateStatus:@"Erasing…"];
    [self updateProgress:0];
    [self _doWriteOnSocket:sock data:data];
}

- (void)_doWriteOnSocket:(int)sock data:(NSData *)data
{
    [[MDMADevice sharedDevice] writeFlashOnSocket:sock
                                             data:data
                                        atAddress:0x000000
                                         progress:^(double f, NSString *st) {
        [self updateProgress:f];
        [self updateStatus:st];
    } completion:^(NSError *err) {
        self->_wifiSock = -1;
        [self _updateWiFiConnectionState];
        [self operationDone];
        if (err) {
            [self updateStatus:[NSString stringWithFormat:@"WiFi write failed: %@",
                               err.localizedDescription]];
        } else {
            [self updateStatus:@"WiFi write complete — ROM is running. Click Write to flash again."];
        }
    }];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

- (NSData *)_loadROM
{
    NSString *path = _pathField.stringValue;
    if (!path.length) {
        [self _alertTitle:@"No ROM File" message:@"Select a ROM file first."]; return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || !data.length) {
        [self _alertTitle:@"Cannot Read File"
                  message:[NSString stringWithFormat:@"Could not read: %@", path]];
        return nil;
    }
    return data;
}

- (void)_alertTitle:(NSString *)title message:(NSString *)msg
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText     = title;
    alert.informativeText = msg;
    [alert addButtonWithTitle:@"OK"];
    NSWindow *win = self.view.window;
    if (win) [alert beginSheetModalForWindow:win completionHandler:nil];
    else     [alert runModal];
}

@end
