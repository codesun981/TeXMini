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

@end

NS_ASSUME_NONNULL_END
