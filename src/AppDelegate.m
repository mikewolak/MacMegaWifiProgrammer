//  AppDelegate.m

#import "AppDelegate.h"
#import "MDMADevice.h"
#import "MainWindowController.h"
#import "AboutWindowController.h"

@implementation AppDelegate {
    MainWindowController *_mainWindowController;
}

- (void)buildMenu
{
    NSMenu *menuBar = [[NSMenu alloc] init];
    [NSApp setMainMenu:menuBar];

    // App menu (title is replaced by the OS with the app name)
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    appItem.submenu = appMenu;

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:@"About MegaWifi Programmer"
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    aboutItem.target = self;
    [appMenu addItem:aboutItem];
    [appMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit MegaWifi Programmer"
                                                      action:@selector(terminate:)
                                               keyEquivalent:@"q"];
    [appMenu addItem:quitItem];
}

- (IBAction)showAbout:(id)sender
{
    [[AboutWindowController sharedController] showWindow:nil];
    [[AboutWindowController sharedController].window makeKeyAndOrderFront:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    [self buildMenu];
    NSLog(@"AppDelegate: launching");
    @try {
        [[MDMADevice sharedDevice] startMonitoring];
        NSLog(@"AppDelegate: monitoring started");
        _mainWindowController = [[MainWindowController alloc] init];
        NSLog(@"AppDelegate: window controller created, window=%@", _mainWindowController.window);
        [_mainWindowController showWindow:nil];
        [_mainWindowController.window makeKeyAndOrderFront:nil];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        NSLog(@"AppDelegate: window shown, visible=%d", _mainWindowController.window.isVisible);
    } @catch (NSException *e) {
        NSLog(@"AppDelegate EXCEPTION: %@ — %@", e.name, e.reason);
        NSLog(@"Stack: %@", e.callStackSymbols);
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note
{
    [[MDMADevice sharedDevice] stopMonitoring];
    [[MDMADevice sharedDevice] disconnect];
}

@end
