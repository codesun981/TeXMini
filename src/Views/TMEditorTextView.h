#import <Cocoa/Cocoa.h>
#import "TMCompletionProvider.h"

NS_ASSUME_NONNULL_BEGIN

@protocol TMEditorTextViewDelegate <NSTextViewDelegate>
@optional
- (void)editorTextViewDidChangeCursorPositionToLine:(NSInteger)line column:(NSInteger)column;
/// 用户在编辑器里 ⌘+点击（与 PDF 里 ⌘+点击对称）：请求正向同步到 PDF。
- (void)editorTextViewDidRequestForwardSync;
@end

@interface TMEditorTextView : NSTextView

@property (nonatomic, weak) id<TMEditorTextViewDelegate> editorDelegate;
/// 提供 \cite / \ref / \begin / 命令 的候选；为 nil 时退回系统单词补全。
@property (nonatomic, strong, nullable) TMCompletionProvider *completionProvider;

- (void)setupEditor;
- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)column;
- (void)rehighlightAll;

/// 编辑器字号（9–30），设置后立即重排并重新着色。
@property (nonatomic, assign) CGFloat editorFontSize;

/// 以下动作作用于选区覆盖的整行，可撤销。
- (IBAction)toggleComment:(nullable id)sender;
- (IBAction)indentSelection:(nullable id)sender;
- (IBAction)outdentSelection:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
