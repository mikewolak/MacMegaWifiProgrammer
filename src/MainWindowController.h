//  MainWindowController.h

#import <Cocoa/Cocoa.h>

@interface MainWindowController : NSWindowController <NSWindowDelegate>

// Called by tab controllers to update the shared status bar
- (void)setStatus:(NSString *)message;
- (void)setProgress:(double)fraction;  // 0..1; pass -1 to hide bar
- (void)setOperationActive:(BOOL)active;

@end
