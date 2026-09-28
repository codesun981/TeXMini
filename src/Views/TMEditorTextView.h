#import <Cocoa/Cocoa.h>
#import "TMCompletionProvider.h"
#import "TMLaTeXHighlighter.h"
#import "TMLineIndex.h"

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
/// 正式文档为规范化路径；设为 nil 时为未命名文档生成独立标识，同时取消旧请求。
@property (nonatomic, copy, nullable) NSString *completionDocumentKey;
/// 文件保存后索引可能更新，仅在补全会话仍活跃时刷新。
- (void)refreshCompletionIfNeeded;
- (void)dismissCompletion;

- (void)setupEditor;
/// 当前字符版本共用的行首索引；属性着色不使其失效。
@property (nonatomic, strong, readonly) TMLineIndex *lineIndex;
/// 按什么规则着色；非 LaTeX 文件不做 $ 配对、\begin 补全和命令补全。换了规则会整篇重新着色。
@property (nonatomic, assign) TMEditorSyntax syntax;
- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)column;
- (void)rehighlightAll;
/// 可撤销地在 location 插入文本，光标停在 location + cursorOffset。
- (void)insertSnippet:(NSString *)snippet atLocation:(NSUInteger)location cursorOffset:(NSUInteger)cursorOffset;
/// 用 newText 整体替换内容，但只改动真正不同的那一段：一步可撤销，光标尽量留在原处。
- (void)replaceTextWith:(NSString *)newText actionName:(NSString *)actionName;
/// 可撤销地把 range 换成 replacement，之后选中 selection（替换后的坐标）。
- (void)replaceRange:(NSRange)range withText:(NSString *)replacement selection:(NSRange)selection actionName:(NSString *)actionName;

/// 编辑器字号（9–30），设置后立即重排并重新着色。
@property (nonatomic, assign) CGFloat editorFontSize;
/// 编辑器字体名（PostScript 名或家族名，找不到时退回系统等宽字体）。
@property (nonatomic, copy) NSString *editorFontName;
/// 自动换行；关闭后出现横向滚动条。默认 YES。
@property (nonatomic, assign) BOOL softWrapEnabled;
/// 光标所在行淡淡的底色。默认 YES。
@property (nonatomic, assign) BOOL highlightsCurrentLine;

/// 以下动作作用于选区覆盖的整行，可撤销。
- (IBAction)toggleComment:(nullable id)sender;
- (IBAction)indentSelection:(nullable id)sender;
- (IBAction)outdentSelection:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
