#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMLaTeXHighlighter : NSObject

/// 编辑器基准字号（默认 13.5），影响之后的所有着色。
+ (void)setBaseFontSize:(CGFloat)size;
+ (CGFloat)baseFontSize;
+ (NSFont *)baseFont;

/// 对 range 所在段落（空行分隔）重新着色。
+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
