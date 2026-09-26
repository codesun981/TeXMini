#import <Cocoa/Cocoa.h>
#import "TMCompiler.h"

NS_ASSUME_NONNULL_BEGIN

@protocol TMStatusBarViewDelegate <NSObject>
@optional
- (void)statusBarDidClickErrorLine:(NSInteger)line;
- (void)statusBarDidToggleLogDrawer;
- (void)statusBarDidChangeEngine:(TMTeXEngine)engine;
- (void)statusBarDidSelectParagraphStyle:(NSInteger)style;
@end

@interface TMStatusBarView : NSView

@property (nonatomic, weak) id<TMStatusBarViewDelegate> delegate;

- (void)setCursorLine:(NSInteger)line column:(NSInteger)column;
/// 单独更新字数（由控制器在文本变化后去抖调用）。
- (void)setWordCount:(NSUInteger)words;
- (void)showCompilingStateWithEngine:(NSString *)engineName;
- (void)showSuccessStateWithDuration:(double)duration warnings:(NSUInteger)warnings badBoxes:(NSUInteger)badBoxes;
- (void)showErrorStateWithMessage:(NSString *)message line:(NSInteger)line;
- (void)showReadyState;
/// 显示一条中性提示（不带 spinner，不清除错误按钮之外的状态）。
- (void)showInfoMessage:(NSString *)message;
- (void)setSelectedEngine:(TMTeXEngine)engine;
/// 段落样式框（「正文 ▾」）：显示光标所在段落的样式，也能点选修改。style 为负数时隐藏。
- (void)setParagraphStyleTitles:(NSArray<NSString *> *)titles;
- (void)setParagraphStyle:(NSInteger)style;
/// 常驻显示“目标文件 · 实际引擎”（⌘↩ 实际编译的文件和引擎）；tooltip 给出完整路径与引擎判断依据。
- (void)setCompileTargetFileName:(NSString *)fileName engine:(NSString *)engine toolTip:(nullable NSString *)toolTip;
/// 页码指示（1-based 显示）。pageCount <= 0 时隐藏。
- (void)setPageIndex:(NSInteger)pageIndex pageCount:(NSInteger)pageCount;

@end

NS_ASSUME_NONNULL_END
