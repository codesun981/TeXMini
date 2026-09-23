#import <Cocoa/Cocoa.h>
#import "TMCompletionProvider.h"

NS_ASSUME_NONNULL_BEGIN

@protocol TMEditorTextViewDelegate <NSTextViewDelegate>
@optional
- (void)editorTextViewDidChangeCursorPositionToLine:(NSInteger)line column:(NSInteger)column;
/// 用户在编辑器里 ⌘+点击（与 PDF 里 ⌘+点击对称）：请求正向同步到 PDF。
- (void)editorTextViewDidRequestForwardSync;
/// 用户把文件从访达拖进了编辑器。返回 YES 表示已处理（控制器插入了 \includegraphics / \input 等）；
/// NO 则退回系统默认行为。
- (BOOL)editorTextView:(NSTextView *)textView didDropFileURLs:(NSArray<NSURL *> *)urls atCharacterIndex:(NSUInteger)index;
@end

@interface TMEditorTextView : NSTextView

@property (nonatomic, weak) id<TMEditorTextViewDelegate> editorDelegate;
/// 提供 \cite / \ref / \begin / 命令 的候选；为 nil 时退回系统单词补全。
@property (nonatomic, strong, nullable) TMCompletionProvider *completionProvider;

- (void)setupEditor;
- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)column;
- (void)rehighlightAll;
/// 可撤销地在 location 插入文本，光标停在 location + cursorOffset。
- (void)insertSnippet:(NSString *)snippet atLocation:(NSUInteger)location cursorOffset:(NSUInteger)cursorOffset;

/// 编辑器字号（9–30），设置后立即重排并重新着色。
@property (nonatomic, assign) CGFloat editorFontSize;
/// 编辑器字体名（PostScript 名或家族名，找不到时退回系统等宽字体）。
@property (nonatomic, copy) NSString *editorFontName;
/// 自动换行；关闭后出现横向滚动条。默认 YES。
@property (nonatomic, assign) BOOL softWrapEnabled;

/// 以下动作作用于选区覆盖的整行，可撤销。
- (IBAction)toggleComment:(nullable id)sender;
- (IBAction)indentSelection:(nullable id)sender;
- (IBAction)outdentSelection:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
