//  BaseTabViewController.h  — shared init for all tab VCs

#import <Cocoa/Cocoa.h>
@class MainWindowController;

@interface BaseTabViewController : NSViewController

@property (nonatomic, weak) MainWindowController *windowController;

- (instancetype)initWithWindowController:(MainWindowController *)wc;

// Convenience — always dispatches to main queue
- (void)updateStatus:(NSString *)msg;
- (void)updateProgress:(double)fraction;
- (void)operationDone;

@end
