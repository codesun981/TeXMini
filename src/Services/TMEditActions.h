#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 纯字符串级别的编辑动作，不依赖 AppKit，便于单元测试。
/// 所有 "lines" 参数都是若干整行拼接的文本（可含末尾换行），返回同样形状的文本。
@interface TMEditActions : NSObject

/// 若所有非空行都以 % 开头（允许前导空白），去掉第一个 % 及其后的一个空格；否则给每个非空行行首加 "% "。
+ (NSString *)toggledCommentForLines:(NSString *)lines;

/// 给每个非空行行首加 indent。
+ (NSString *)indentedLines:(NSString *)lines indent:(NSString *)indent;

/// 从每行行首移除最多 width 个空格，或一个 tab。
+ (NSString *)outdentedLines:(NSString *)lines width:(NSUInteger)width;

/// 若该行含未被注释的 \begin{X} 且同一行没有对应 \end{X}，返回 X；否则返回 nil。
+ (nullable NSString *)environmentToCloseInLine:(NSString *)line;

/// 行首的空白（空格与 tab）。
+ (NSString *)leadingWhitespaceOfLine:(NSString *)line;

#pragma mark - 拖入图片 / 文件

/// 拖入编辑器时会被当作图片处理的扩展名（小写）：png jpg jpeg pdf eps。
+ (NSArray<NSString *> *)droppableImageExtensions;

/// 从文件名生成 label 主体：去扩展名，小写，非字母数字变 '-'，例如 "My Plot 1.png" → "my-plot-1"。
+ (NSString *)labelSlugForFileName:(NSString *)fileName;

/// figure 环境骨架。cursorOffset 返回 \caption{ 之后（应放光标处）相对于返回串起点的偏移。
+ (NSString *)figureSnippetForImagePath:(NSString *)relativePath label:(NSString *)label cursorOffset:(nullable NSUInteger *)cursorOffset;

/// 若内容里没有 \usepackage{graphicx}（或 graphbox），返回应插入 "\\usepackage{graphicx}\n" 的位置
/// （\documentclass 行之后）；已存在或找不到 \documentclass 时返回 NSNotFound。
+ (NSUInteger)graphicxInsertionLocationInContent:(NSString *)content;

/// file 相对 directory 的路径（用 / 分隔）；file 不在 directory 内时返回 nil。
+ (nullable NSString *)relativePathFromDirectory:(NSURL *)directory toFile:(NSURL *)file;

@end

NS_ASSUME_NONNULL_END
