#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMLogDrawerView : NSView

@property (nonatomic, assign) BOOL isExpanded;

- (void)appendLogText:(NSString *)text;
- (void)clearLog;
- (void)toggleAnimated;

@end

NS_ASSUME_NONNULL_END
