#import "TMLaTeXHighlighter.h"
#import "TMMarkdownScanner.h"
#import <objc/runtime.h>

static CGFloat gBaseFontSize = 13.5;
static NSString *gBaseFontName = @"Menlo";

@implementation TMLaTeXHighlighter

+ (void)setBaseFontSize:(CGFloat)size {
    gBaseFontSize = size;
}

+ (CGFloat)baseFontSize {
    return gBaseFontSize;
}

+ (void)setBaseFontName:(NSString *)name {
    gBaseFontName = name.length ? [name copy] : @"Menlo";
}

+ (NSString *)baseFontName {
    return gBaseFontName;
}

+ (NSFont *)baseFont {
    return [NSFont fontWithName:gBaseFontName size:gBaseFontSize]
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

/// 每个文本存储上一次扫描的块结构摘要：摘要变了（例如刚打出 \begin{verbatim} 的 \end），整篇重画
static NSMapTable<NSTextStorage *, TMLaTeXScanResult *> *TMLastScans(void) {
    static NSMapTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSMapTable weakToStrongObjectsMapTable]; });
    return table;
}

+ (nullable TMLaTeXScanResult *)lastScanForTextStorage:(NSTextStorage *)textStorage {
    return [TMLastScans() objectForKey:textStorage];
}

/// 公式内容用沉稳的绿色：橙黄色容易被当成警告 / 没识别出来。浅色、深色模式各一套
+ (NSColor *)mathColor {
    static NSColor *color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = [NSColor colorWithName:@"TMMathColor" dynamicProvider:^NSColor *(NSAppearance *appearance) {
            BOOL dark = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] == NSAppearanceNameDarkAqua;
            return dark ? [NSColor colorWithSRGBRed:0.49 green:0.82 blue:0.60 alpha:1.0]
                        : [NSColor colorWithSRGBRed:0.10 green:0.50 blue:0.28 alpha:1.0];
        }];
    });
    return color;
}

#pragma mark - 按文件类型

static NSMapTable<NSTextStorage *, NSNumber *> *TMSyntaxes(void) {
    static NSMapTable *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ table = [NSMapTable weakToStrongObjectsMapTable]; });
    return table;
}

+ (TMEditorSyntax)syntaxForFileURL:(nullable NSURL *)url {
    if (!url) return TMEditorSyntaxLaTeX;
    NSString *ext = url.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) return TMEditorSyntaxMarkdown;
    if ([ext isEqualToString:@"bib"]) return TMEditorSyntaxBibTeX;
    static NSSet *latex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        latex = [NSSet setWithArray:@[@"tex", @"ltx", @"latex", @"sty", @"cls", @"dtx", @"ins", @"bbx", @"cbx", @"def", @"tikz", @"clo"]];
    });
    return [latex containsObject:ext] ? TMEditorSyntaxLaTeX : TMEditorSyntaxPlain;
}

+ (void)setSyntax:(TMEditorSyntax)syntax forTextStorage:(NSTextStorage *)textStorage {
    [TMSyntaxes() setObject:@(syntax) forKey:textStorage];
    // 换了规则，旧的扫描结果不再适用
    [TMLastScans() removeObjectForKey:textStorage];
}

+ (TMEditorSyntax)syntaxForTextStorage:(NSTextStorage *)textStorage {
    return (TMEditorSyntax)[[TMSyntaxes() objectForKey:textStorage] integerValue];
}

#pragma mark - 着色

+ (NSRange)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range {
    if (textStorage.length == 0) return NSMakeRange(0, 0);

    static BOOL isHighlighting = NO;
    if (isHighlighting) return NSMakeRange(0, 0);
    isHighlighting = YES;

    NSRange painted = NSMakeRange(0, 0);
    @try {
        switch ([self syntaxForTextStorage:textStorage]) {
            case TMEditorSyntaxLaTeX: painted = [self highlightLaTeX:textStorage inRange:range]; break;
            case TMEditorSyntaxMarkdown: painted = [self highlightMarkdown:textStorage inRange:range]; break;
            case TMEditorSyntaxBibTeX: painted = [self highlightBibTeX:textStorage inRange:range]; break;
            case TMEditorSyntaxPlain: painted = [self highlightPlain:textStorage inRange:range]; break;
        }
    } @finally {
        isHighlighting = NO;
    }
    return painted;
}

/// 把 scope 恢复成正文字体、正文颜色（各语法着色的第一步）
+ (void)resetTextStorage:(NSTextStorage *)textStorage scope:(NSRange)scope {
    [textStorage removeAttribute:NSForegroundColorAttributeName range:scope];
    [textStorage removeAttribute:NSFontAttributeName range:scope];
    [textStorage addAttribute:NSFontAttributeName value:[self baseFont] range:scope];
    [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:scope];
}

+ (NSFont *)baseFontWithTrait:(NSFontTraitMask)trait {
    NSFont *normal = [self baseFont];
    return [[NSFontManager sharedFontManager] convertFont:normal toHaveTrait:trait] ?: normal;
}

+ (NSRange)highlightLaTeX:(NSTextStorage *)textStorage inRange:(NSRange)range {
    NSString *string = textStorage.string;
    // 整篇扫描（线性、很快），只重画编辑附近的段落；结构变了才整篇重画
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:string];
    TMLaTeXScanResult *previous = [TMLastScans() objectForKey:textStorage];
    [TMLastScans() setObject:scan forKey:textStorage];

    NSRange scope = [self paragraphRangeForRange:range inString:string maxLines:200];
    if (previous && ![previous.blockSignature isEqualToString:scan.blockSignature]) {
        scope = NSMakeRange(0, string.length);
    }
    if (scope.length == 0) return scope;

    NSFont *italicFont = [self baseFontWithTrait:NSItalicFontMask];

    NSColor *colors[6];
    colors[TMLaTeXRegionCommand] = [NSColor systemBlueColor];
    colors[TMLaTeXRegionEnvironment] = [NSColor systemPurpleColor];
    colors[TMLaTeXRegionMath] = [self mathColor];
    colors[TMLaTeXRegionVerbatim] = [NSColor systemTealColor];
    colors[TMLaTeXRegionComment] = [NSColor secondaryLabelColor];
    colors[TMLaTeXRegionRaw] = [NSColor textColor];

    [textStorage beginEditing];
    [self resetTextStorage:textStorage scope:scope];

    // 后画的覆盖先画的：公式先铺底色，公式里的命令和 \begin{equation} 再盖上去；注释最后
    static const TMLaTeXRegionKind order[] = {TMLaTeXRegionMath, TMLaTeXRegionCommand, TMLaTeXRegionEnvironment,
                                               TMLaTeXRegionVerbatim, TMLaTeXRegionComment};
    const TMLaTeXRegion *regions = scan.regions;
    NSUInteger count = scan.regionCount;
    for (size_t pass = 0; pass < sizeof(order) / sizeof(order[0]); pass++) {
        TMLaTeXRegionKind kind = order[pass];
        for (NSUInteger k = 0; k < count; k++) {
            if (regions[k].kind != kind) continue;
            NSRange r = NSIntersectionRange(regions[k].range, scope);
            if (r.length == 0) continue;
            [textStorage addAttribute:NSForegroundColorAttributeName value:colors[kind] range:r];
            if (kind == TMLaTeXRegionComment) [textStorage addAttribute:NSFontAttributeName value:italicFont range:r];
        }
    }
    [textStorage endEditing];
    return scope;
}

+ (NSRange)highlightMarkdown:(NSTextStorage *)textStorage inRange:(NSRange)range {
    NSString *string = textStorage.string;
    TMMarkdownScanResult *scan = [TMMarkdownScanner scanString:string];
    [TMLastScans() removeObjectForKey:textStorage];

    // 代码块可以跨空行：块的数量变了就整篇重画（和 LaTeX 的结构摘要同一个思路）
    NSMutableString *signature = [NSMutableString string];
    const TMMarkdownRegion *regions = scan.regions;
    NSUInteger count = scan.regionCount;
    for (NSUInteger k = 0; k < count; k++) {
        if (regions[k].kind == TMMarkdownRegionCode && [string rangeOfString:@"\n" options:NSLiteralSearch range:regions[k].range].location != NSNotFound) {
            [signature appendString:@"c"];
        }
    }
    NSString *previous = objc_getAssociatedObject(textStorage, @selector(highlightMarkdown:inRange:));
    objc_setAssociatedObject(textStorage, @selector(highlightMarkdown:inRange:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);

    NSRange scope = [self paragraphRangeForRange:range inString:string maxLines:200];
    if (previous && ![previous isEqualToString:signature]) scope = NSMakeRange(0, string.length);
    if (scope.length == 0) return scope;

    NSFont *boldFont = [self baseFontWithTrait:NSBoldFontMask];
    NSFont *italicFont = [self baseFontWithTrait:NSItalicFontMask];

    [textStorage beginEditing];
    [self resetTextStorage:textStorage scope:scope];
    for (NSUInteger k = 0; k < count; k++) {
        NSRange r = NSIntersectionRange(regions[k].range, scope);
        if (r.length == 0) continue;
        switch (regions[k].kind) {
            case TMMarkdownRegionHeading:
                [textStorage addAttribute:NSFontAttributeName value:boldFont range:r];
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor systemBlueColor] range:r];
                break;
            case TMMarkdownRegionMarker:
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor systemPurpleColor] range:r];
                break;
            case TMMarkdownRegionStrong:
                [textStorage addAttribute:NSFontAttributeName value:boldFont range:r];
                break;
            case TMMarkdownRegionEmphasis:
                [textStorage addAttribute:NSFontAttributeName value:italicFont range:r];
                break;
            case TMMarkdownRegionStrike:
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor secondaryLabelColor] range:r];
                break;
            case TMMarkdownRegionCode:
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor systemTealColor] range:r];
                break;
            case TMMarkdownRegionLink:
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor linkColor] range:r];
                break;
            case TMMarkdownRegionQuote:
                [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor secondaryLabelColor] range:r];
                break;
        }
    }
    [textStorage endEditing];
    return scope;
}

/// .bib：@article 这样的条目类型、字段名、条目外的说明文字
+ (NSRange)highlightBibTeX:(NSTextStorage *)textStorage inRange:(NSRange)range {
    NSString *string = textStorage.string;
    [TMLastScans() removeObjectForKey:textStorage];
    NSRange scope = [self paragraphRangeForRange:range inString:string maxLines:200];
    if (scope.length == 0) return scope;

    static NSRegularExpression *entryRegex, *fieldRegex, *commentRegex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entryRegex = [NSRegularExpression regularExpressionWithPattern:@"@[A-Za-z]+" options:0 error:nil];
        fieldRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*([A-Za-z][A-Za-z0-9_-]*)[ \\t]*=" options:NSRegularExpressionAnchorsMatchLines error:nil];
        commentRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*%.*$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    });

    [textStorage beginEditing];
    [self resetTextStorage:textStorage scope:scope];
    [entryRegex enumerateMatchesInString:string options:0 range:scope usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor systemPurpleColor] range:m.range];
    }];
    [fieldRegex enumerateMatchesInString:string options:0 range:scope usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor systemBlueColor] range:[m rangeAtIndex:1]];
    }];
    NSFont *italicFont = [self baseFontWithTrait:NSItalicFontMask];
    [commentRegex enumerateMatchesInString:string options:0 range:scope usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor secondaryLabelColor] range:m.range];
        [textStorage addAttribute:NSFontAttributeName value:italicFont range:m.range];
    }];
    [textStorage endEditing];
    return scope;
}

+ (NSRange)highlightPlain:(NSTextStorage *)textStorage inRange:(NSRange)range {
    [TMLastScans() removeObjectForKey:textStorage];
    NSRange scope = [self paragraphRangeForRange:range inString:textStorage.string maxLines:200];
    if (scope.length == 0) return scope;
    [textStorage beginEditing];
    [self resetTextStorage:textStorage scope:scope];
    [textStorage endEditing];
    return scope;
}

@end
