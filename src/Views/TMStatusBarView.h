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
/// 显示一条中性提示（不带 spinner，不清除错误按钮之外的状态）。
- (void)showInfoMessage:(NSString *)message;
- (void)setSelectedEngine:(TMTeXEngine)engine;

@end

NS_ASSUME_NONNULL_END
