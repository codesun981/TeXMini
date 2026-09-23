#import <Cocoa/Cocoa.h>
#import "TMLaTeXScanner.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMLaTeXHighlighter : NSObject

/// 编辑器基准字号（默认 13.5）与字体名（默认 Menlo），影响之后的所有着色。
+ (void)setBaseFontSize:(CGFloat)size;
+ (CGFloat)baseFontSize;
+ (void)setBaseFontName:(NSString *)name;
+ (NSString *)baseFontName;
+ (NSFont *)baseFont;

/// 对 range 所在段落（空行分隔）重新着色。
+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range;
/// 最近一次高亮时对这份文本的扫描结果（括号匹配据此跳过注释和代码块）。
+ (nullable TMLaTeXScanResult *)lastScanForTextStorage:(NSTextStorage *)textStorage;

@end

NS_ASSUME_NONNULL_END
