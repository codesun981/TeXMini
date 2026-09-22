#import "TMLaTeXHighlighter.h"

static CGFloat gBaseFontSize = 13.5;

@implementation TMLaTeXHighlighter

+ (void)setBaseFontSize:(CGFloat)size {
    gBaseFontSize = size;
}

+ (CGFloat)baseFontSize {
    return gBaseFontSize;
}

+ (NSFont *)baseFont {
    return [NSFont fontWithName:@"Menlo" size:gBaseFontSize]
        ?: [NSFont monospacedSystemFontOfSize:gBaseFontSize weight:NSFontWeightRegular];
}

/// 把 range 向前后扩展到最近的空行（段落边界），每个方向最多 maxLines 行。
/// 多行数学环境 / \[ \] 基本不会跨越空行，因此段落粒度足以正确着色，又不用全文重扫。
+ (NSRange)paragraphRangeForRange:(NSRange)range inString:(NSString *)string maxLines:(NSUInteger)maxLines {
    NSUInteger length = string.length;
    if (length == 0) return NSMakeRange(0, 0);
    if (NSMaxRange(range) > length) range = NSMakeRange(0, length);

    NSUInteger start = [string lineRangeForRange:NSMakeRange(range.location, 0)].location;
    NSUInteger lines = 0;
    while (start > 0 && lines < maxLines) {
        NSRange prev = [string lineRangeForRange:NSMakeRange(start - 1, 0)];
        NSString *prevLine = [string substringWithRange:prev];
        if ([prevLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) break;
        start = prev.location;
        lines++;
    }

    NSUInteger end = NSMaxRange([string lineRangeForRange:NSMakeRange(MAX(range.location, NSMaxRange(range) > 0 ? NSMaxRange(range) - 1 : 0), 0)]);
    lines = 0;
    while (end < length && lines < maxLines) {
        NSRange next = [string lineRangeForRange:NSMakeRange(end, 0)];
        NSString *nextLine = [string substringWithRange:next];
        if ([nextLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) break;
        end = NSMaxRange(next);
        lines++;
    }
    return NSMakeRange(start, end - start);
}

+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range {
    if (textStorage.length == 0) return;

    static BOOL isHighlighting = NO;
    if (isHighlighting) return;
    isHighlighting = YES;

    @try {
        NSString *string = textStorage.string;
        NSRange scope = [self paragraphRangeForRange:range inString:string maxLines:200];
        if (scope.length == 0) return;

        NSFont *normalFont = [self baseFont];
        NSFontManager *fm = [NSFontManager sharedFontManager];
        NSFont *italicFont = [fm convertFont:normalFont toHaveTrait:NSFontItalicTrait] ?: normalFont;

        NSColor *defaultColor = [NSColor textColor];
        NSColor *commandColor = [NSColor systemBlueColor];
        NSColor *envColor = [NSColor systemPurpleColor];
        NSColor *mathColor = [NSColor systemOrangeColor];
        NSColor *verbColor = [NSColor systemTealColor];
        NSColor *commentColor = [NSColor secondaryLabelColor];

        static NSRegularExpression *commandRegex;
        static NSRegularExpression *envRegex;
        static NSRegularExpression *mathRegex;
        static NSRegularExpression *displayMathRegex;
        static NSRegularExpression *verbRegex;
        static NSRegularExpression *commentRegex;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            commandRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\[a-zA-Z@]+\\*?|\\\\[^a-zA-Z@\\s]" options:0 error:nil];
            envRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(begin|end)\\{[^}]+\\}" options:0 error:nil];
            // 行内 $...$ 与 \(...\)
            mathRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\$(?:[^$\\\\]|\\\\.)+?\\$|\\\\\\((?:.|\\n)*?\\\\\\)" options:0 error:nil];
            // $$...$$、\[...\]、以及常见的显示数学环境（可跨行）
            displayMathRegex = [NSRegularExpression regularExpressionWithPattern:
                @"(?<!\\\\)\\$\\$(?:.|\\n)*?\\$\\$"
                @"|\\\\\\[(?:.|\\n)*?\\\\\\]"
                @"|\\\\begin\\{(equation|align|alignat|gather|multline|eqnarray|displaymath|math|flalign)(\\*?)\\}(?:.|\\n)*?\\\\end\\{\\1\\2\\}"
                options:0 error:nil];
            verbRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\verb\\*?([^a-zA-Z\\s])(.*?)\\1" options:0 error:nil];
            commentRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)%.*$" options:NSRegularExpressionAnchorsMatchLines error:nil];
        });

        [textStorage beginEditing];

        [textStorage removeAttribute:NSForegroundColorAttributeName range:scope];
        [textStorage removeAttribute:NSFontAttributeName range:scope];
        [textStorage addAttribute:NSFontAttributeName value:normalFont range:scope];
        [textStorage addAttribute:NSForegroundColorAttributeName value:defaultColor range:scope];

        void (^color)(NSRegularExpression *, NSColor *) = ^(NSRegularExpression *regex, NSColor *c) {
            [regex enumerateMatchesInString:string options:0 range:scope usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                if (result) [textStorage addAttribute:NSForegroundColorAttributeName value:c range:result.range];
            }];
        };

        // 顺序即优先级：后着色的覆盖先着色的
        color(commandRegex, commandColor);
        color(envRegex, envColor);
        color(displayMathRegex, mathColor);
        color(mathRegex, mathColor);
        color(verbRegex, verbColor);

        [commentRegex enumerateMatchesInString:string options:0 range:scope usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
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
