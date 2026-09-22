#import "TMLaTeXHighlighter.h"

@implementation TMLaTeXHighlighter

+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range {
    if (textStorage.length == 0) return;

    static BOOL isHighlighting = NO;
    if (isHighlighting) return;
    isHighlighting = YES;

    @try {
        NSString *string = textStorage.string;
        if (range.location + range.length > string.length) {
            range = NSMakeRange(0, string.length);
        }

        // 扩大到整行范围，避免高亮截断
        NSRange lineRange = [string lineRangeForRange:range];

        NSFont *normalFont = [NSFont fontWithName:@"Menlo" size:13.5] ?: [NSFont monospacedSystemFontOfSize:13.5 weight:NSFontWeightRegular];
        NSFontManager *fm = [NSFontManager sharedFontManager];
        NSFont *italicFont = [fm convertFont:normalFont toHaveTrait:NSFontItalicTrait] ?: normalFont;

        NSColor *defaultColor = [NSColor textColor];
        NSColor *commandColor = [NSColor systemBlueColor];
        NSColor *envColor = [NSColor systemPurpleColor];
        NSColor *mathColor = [NSColor systemOrangeColor];
        NSColor *commentColor = [NSColor secondaryLabelColor];

        [textStorage beginEditing];

    // 重置基础字体与颜色
    [textStorage removeAttribute:NSForegroundColorAttributeName range:lineRange];
    [textStorage removeAttribute:NSFontAttributeName range:lineRange];
    [textStorage addAttribute:NSFontAttributeName value:normalFont range:lineRange];
    [textStorage addAttribute:NSForegroundColorAttributeName value:defaultColor range:lineRange];

    static NSRegularExpression *commandRegex;
    static NSRegularExpression *envRegex;
    static NSRegularExpression *mathRegex;
    static NSRegularExpression *commentRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commandRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\[a-zA-Z@]+" options:0 error:nil];
        envRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(begin|end)\\{[^}]+\\}" options:0 error:nil];
        mathRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\$[^$\\n]+\\$|(?<!\\\\)\\$\\$[^$]+\\$\\$" options:0 error:nil];
        commentRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)%.*$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    });

    // 1. 命令着色
    [commandRegex enumerateMatchesInString:string options:0 range:lineRange usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (result) {
            [textStorage addAttribute:NSForegroundColorAttributeName value:commandColor range:result.range];
        }
    }];

    // 2. 环境标签着色
    [envRegex enumerateMatchesInString:string options:0 range:lineRange usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (result) {
            [textStorage addAttribute:NSForegroundColorAttributeName value:envColor range:result.range];
        }
    }];

    // 3. 数学公式着色
    [mathRegex enumerateMatchesInString:string options:0 range:lineRange usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (result) {
            [textStorage addAttribute:NSForegroundColorAttributeName value:mathColor range:result.range];
        }
    }];

    // 4. 注释着色（优先级最高，覆盖其他着色）
    [commentRegex enumerateMatchesInString:string options:0 range:lineRange usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        if (result) {
            [textStorage addAttribute:NSForegroundColorAttributeName value:commentColor range:result.range];
            [textStorage addAttribute:NSFontAttributeName value:italicFont range:result.range];
        }
    }];

        [textStorage endEditing];
    } @finally {
        isHighlighting = NO;
    }
}

@end
