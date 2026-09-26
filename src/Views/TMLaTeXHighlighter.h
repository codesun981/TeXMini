#import <Cocoa/Cocoa.h>
#import "TMLaTeXScanner.h"

NS_ASSUME_NONNULL_BEGIN

/// 文件按什么规则着色。.md 里的 50% 不该把后半行染成注释。
typedef NS_ENUM(NSInteger, TMEditorSyntax) {
    TMEditorSyntaxLaTeX = 0,   // .tex .sty .cls …，以及未命名文档
    TMEditorSyntaxMarkdown,    // .md .markdown
    TMEditorSyntaxBibTeX,      // .bib
    TMEditorSyntaxPlain        // 其他（.txt .log …）：不着色
};

@interface TMLaTeXHighlighter : NSObject

/// 按扩展名判断；url 为 nil（未命名文档）按 LaTeX。
+ (TMEditorSyntax)syntaxForFileURL:(nullable NSURL *)url;
/// 这份文本按什么规则着色（默认 LaTeX）。改了之后需要整篇重新着色。
+ (void)setSyntax:(TMEditorSyntax)syntax forTextStorage:(NSTextStorage *)textStorage;
+ (TMEditorSyntax)syntaxForTextStorage:(NSTextStorage *)textStorage;

/// 编辑器基准字号（默认 13.5）与字体名（默认 Menlo），影响之后的所有着色。
+ (void)setBaseFontSize:(CGFloat)size;
+ (CGFloat)baseFontSize;
+ (void)setBaseFontName:(NSString *)name;
+ (NSString *)baseFontName;
+ (NSFont *)baseFont;

/// 对 range 所在段落（空行分隔）重新着色，返回实际重画的范围（没有重画时 length 为 0）。
+ (NSRange)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range;
/// 最近一次高亮时对这份文本的 LaTeX 扫描结果（括号匹配据此跳过注释和代码块）；非 LaTeX 文件为 nil。
+ (nullable TMLaTeXScanResult *)lastScanForTextStorage:(NSTextStorage *)textStorage;

@end

NS_ASSUME_NONNULL_END
