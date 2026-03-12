//  BaseTabViewController.m

#import "BaseTabViewController.h"
#import "MainWindowController.h"

@implementation BaseTabViewController

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) _windowController = wc;
    return self;
}

- (void)updateStatus:(NSString *)msg
{
    [_windowController setStatus:msg];
}

- (void)updateProgress:(double)fraction
{
    [_windowController setProgress:fraction];
}

- (void)operationDone
{
    [_windowController setOperationActive:NO];
}

@end
