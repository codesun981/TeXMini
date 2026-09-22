#import <Cocoa/Cocoa.h>
#import "TMCompiler.h"

NS_ASSUME_NONNULL_BEGIN

@protocol TMStatusBarViewDelegate <NSObject>
@optional
- (void)statusBarDidClickErrorLine:(NSInteger)line;
- (void)statusBarDidToggleLogDrawer;
- (void)statusBarDidChangeEngine:(TMTeXEngine)engine;
@end

@interface TMStatusBarView : NSView

@property (nonatomic, weak) id<TMStatusBarViewDelegate> delegate;

- (void)setCursorLine:(NSInteger)line column:(NSInteger)column totalChars:(NSUInteger)totalChars;
- (void)showCompilingStateWithEngine:(NSString *)engineName;
- (void)showSuccessStateWithDuration:(double)duration;
- (void)showErrorStateWithMessage:(NSString *)message line:(NSInteger)line;
- (void)showReadyState;
- (void)setSelectedEngine:(TMTeXEngine)engine;

@end

NS_ASSUME_NONNULL_END
