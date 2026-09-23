#import "TMLaTeXHighlighter.h"

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

+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range {
    if (textStorage.length == 0) return;

    static BOOL isHighlighting = NO;
    if (isHighlighting) return;
    isHighlighting = YES;

    @try {
        NSString *string = textStorage.string;
        // 整篇扫描（线性、很快），只重画编辑附近的段落；结构变了才整篇重画
        TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:string];
        TMLaTeXScanResult *previous = [TMLastScans() objectForKey:textStorage];
        [TMLastScans() setObject:scan forKey:textStorage];

        NSRange scope = [self paragraphRangeForRange:range inString:string maxLines:200];
        if (previous && ![previous.blockSignature isEqualToString:scan.blockSignature]) {
            scope = NSMakeRange(0, string.length);
        }
        if (scope.length == 0) return;

        NSFont *normalFont = [self baseFont];
        NSFont *italicFont = [[NSFontManager sharedFontManager] convertFont:normalFont toHaveTrait:NSFontItalicTrait] ?: normalFont;

        NSColor *colors[6];
        colors[TMLaTeXRegionCommand] = [NSColor systemBlueColor];
        colors[TMLaTeXRegionEnvironment] = [NSColor systemPurpleColor];
        colors[TMLaTeXRegionMath] = [self mathColor];
        colors[TMLaTeXRegionVerbatim] = [NSColor systemTealColor];
        colors[TMLaTeXRegionComment] = [NSColor secondaryLabelColor];
        colors[TMLaTeXRegionRaw] = [NSColor textColor];

        [textStorage beginEditing];
        [textStorage removeAttribute:NSForegroundColorAttributeName range:scope];
        [textStorage removeAttribute:NSFontAttributeName range:scope];
        [textStorage addAttribute:NSFontAttributeName value:normalFont range:scope];
        [textStorage addAttribute:NSForegroundColorAttributeName value:[NSColor textColor] range:scope];

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
    } @finally {
        isHighlighting = NO;
    }
}

@end
