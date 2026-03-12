//  AppDelegate.m

#import "AppDelegate.h"
#import "MDMADevice.h"
#import "MainWindowController.h"

@implementation AppDelegate {
    MainWindowController *_mainWindowController;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
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
