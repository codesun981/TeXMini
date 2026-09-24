#import "TMFontSettings.h"

@implementation TMDocumentFontSettings
@end

/// 一处待应用的文本改动；最后按位置从后往前统一应用，互不干扰。
@interface TMTextEdit : NSObject
@property (nonatomic, assign) NSRange range;
@property (nonatomic, copy) NSString *replacement;
@end
@implementation TMTextEdit
+ (instancetype)editWithRange:(NSRange)range replacement:(NSString *)replacement {
    TMTextEdit *e = [[TMTextEdit alloc] init];
    e.range = range;
    e.replacement = replacement;
    return e;
}
@end

@implementation TMFontSettings

#pragma mark - 通用小工具

static NSRegularExpression *TMRegex(NSString *pattern, NSRegularExpressionOptions options) {
    static NSCache<NSString *, NSRegularExpression *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [[NSCache alloc] init]; });
    NSString *key = [NSString stringWithFormat:@"%lu|%@", (unsigned long)options, pattern];
    NSRegularExpression *re = [cache objectForKey:key];
    if (!re) {
        re = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
        if (re) [cache setObject:re forKey:key];
    }
    return re;
}

/// loc 所在行里，loc 之前是否有未转义的 %（即 loc 处于注释中）。
static BOOL TMIsCommented(NSString *content, NSUInteger loc) {
    NSUInteger start = [content lineRangeForRange:NSMakeRange(loc, 0)].location;
    for (NSUInteger i = start; i < loc; i++) {
        if ([content characterAtIndex:i] == '%' && (i == start || [content characterAtIndex:i - 1] != '\\')) return YES;
    }
    return NO;
}

/// range 内第一个不在注释里的匹配。
static NSTextCheckingResult *TMFirstLiveMatch(NSRegularExpression *re, NSString *content, NSRange range) {
    for (NSTextCheckingResult *m in [re matchesInString:content options:0 range:range]) {
        if (!TMIsCommented(content, m.range.location)) return m;
    }
    return nil;
}

static NSString *TMTrim(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSRegularExpression *TMDocumentClassRegex(void) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    // group 1：选项（可无），group 2：文档类名
    dispatch_once(&once, ^{ re = TMRegex(@"\\\\documentclass\\s*(?:\\[([^\\]]*)\\])?\\s*\\{([^}]*)\\}", 0); });
    return re;
}

/// \begin{document} 的位置；没有返回 NSNotFound。
static NSUInteger TMBeginDocumentLocation(NSString *content) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = TMRegex(@"\\\\begin\\s*\\{document\\}", 0); });
    NSTextCheckingResult *m = TMFirstLiveMatch(re, content, NSMakeRange(0, content.length));
    return m ? m.range.location : NSNotFound;
}

/// 导言区范围：文件开头到 \begin{document}（没有就到文末）。
static NSRange TMPreambleRange(NSString *content) {
    NSUInteger end = TMBeginDocumentLocation(content);
    return NSMakeRange(0, end == NSNotFound ? content.length : end);
}

static BOOL TMPackageLoaded(NSString *content, NSString *package) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = TMRegex(@"\\\\(?:usepackage|RequirePackage)\\s*(?:\\[[^\\]]*\\])?\\s*\\{([^}]*)\\}", 0); });
    NSRange preamble = TMPreambleRange(content);
    for (NSTextCheckingResult *m in [re matchesInString:content options:0 range:preamble]) {
        if (TMIsCommented(content, m.range.location)) continue;
        for (NSString *name in [[content substringWithRange:[m rangeAtIndex:1]] componentsSeparatedByString:@","]) {
            if ([TMTrim(name) isEqualToString:package]) return YES;
        }
    }
    return NO;
}

/// \<command>[…]{字体名}；group 1 是字体名。
static NSRegularExpression *TMFontCommandRegex(NSString *command) {
    NSString *pattern = [NSString stringWithFormat:@"\\\\%@\\s*(?:\\[[^\\]]*\\])?\\s*\\{([^}]*)\\}", command];
    return TMRegex(pattern, 0);
}

static BOOL TMIsSizeOption(NSString *token) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = TMRegex(@"^(?:\\d+(?:\\.\\d+)?pt|zihao\\s*=.*)$", 0); });
    return [re firstMatchInString:token options:0 range:NSMakeRange(0, token.length)] != nil;
}

static NSMutableArray<NSString *> *TMOptionTokens(NSString *options) {
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *t in [options componentsSeparatedByString:@","]) {
        NSString *trimmed = TMTrim(t);
        if (trimmed.length) [tokens addObject:trimmed];
    }
    return tokens;
}

static NSString *TMApplyEdits(NSString *content, NSArray<TMTextEdit *> *edits) {
    NSArray<TMTextEdit *> *sorted = [edits sortedArrayUsingComparator:^NSComparisonResult(TMTextEdit *a, TMTextEdit *b) {
        if (a.range.location == b.range.location) return NSOrderedSame;
        return a.range.location > b.range.location ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableString *result = [content mutableCopy];
    for (TMTextEdit *e in sorted) [result replaceCharactersInRange:e.range withString:e.replacement];
    return result;
}

#pragma mark - 导言区

+ (nullable NSString *)documentClassInContent:(NSString *)content {
    NSTextCheckingResult *m = TMFirstLiveMatch(TMDocumentClassRegex(), content, NSMakeRange(0, content.length));
    return m ? TMTrim([content substringWithRange:[m rangeAtIndex:2]]) : nil;
}

+ (BOOL)contentHasPreamble:(NSString *)content {
    return [self documentClassInContent:content] != nil && TMBeginDocumentLocation(content) != NSNotFound;
}

+ (BOOL)isCTeXContent:(NSString *)content {
    NSString *cls = [self documentClassInContent:content];
    if ([@[@"ctexart", @"ctexrep", @"ctexbook", @"ctexbeamer"] containsObject:cls ?: @""]) return YES;
    return TMPackageLoaded(content, @"ctex");
}

+ (NSArray<NSString *> *)sizeOptionsForDocumentClass:(NSString *)documentClass {
    NSArray<NSString *> *standard = @[@"10pt", @"11pt", @"12pt"];
    NSArray<NSString *> *extended = @[@"8pt", @"9pt", @"10pt", @"11pt", @"12pt", @"14pt", @"17pt", @"20pt"];
    if ([@[@"article", @"report", @"book", @"amsart", @"amsbook", @"letter", @"proc"] containsObject:documentClass]) return standard;
    if ([@[@"ctexart", @"ctexrep", @"ctexbook"] containsObject:documentClass]) {
        return @[@"zihao=5", @"zihao=-4", @"10pt", @"11pt", @"12pt"];
    }
    if ([@[@"extarticle", @"extreport", @"extbook", @"beamer", @"ctexbeamer"] containsObject:documentClass]) return extended;
    return @[];
}

+ (NSString *)displayNameForSizeOption:(NSString *)option {
    NSString *compact = [option stringByReplacingOccurrencesOfString:@" " withString:@""];
    if ([compact isEqualToString:@"zihao=5"]) return @"五号（10.5pt）";
    if ([compact isEqualToString:@"zihao=-4"]) return @"小四（12pt）";
    return option;
}

+ (TMDocumentFontSettings *)settingsInContent:(NSString *)content {
    TMDocumentFontSettings *s = [[TMDocumentFontSettings alloc] init];
    NSRange preamble = TMPreambleRange(content);
    NSTextCheckingResult *latin = TMFirstLiveMatch(TMFontCommandRegex(@"setmainfont"), content, preamble);
    if (latin) s.latinFont = TMTrim([content substringWithRange:[latin rangeAtIndex:1]]);
    NSTextCheckingResult *cjk = TMFirstLiveMatch(TMFontCommandRegex(@"setCJKmainfont"), content, preamble);
    if (cjk) s.cjkFont = TMTrim([content substringWithRange:[cjk rangeAtIndex:1]]);

    NSTextCheckingResult *dc = TMFirstLiveMatch(TMDocumentClassRegex(), content, NSMakeRange(0, content.length));
    if (dc && [dc rangeAtIndex:1].location != NSNotFound) {
        for (NSString *t in TMOptionTokens([content substringWithRange:[dc rangeAtIndex:1]])) {
            if (TMIsSizeOption(t)) s.sizeOption = t;
        }
    }
    if (s.latinFont.length == 0) s.latinFont = nil;
    if (s.cjkFont.length == 0) s.cjkFont = nil;
    return s;
}

/// 删掉一条字体命令：独占一行就连行一起删，否则只删命令本身。
static TMTextEdit *TMRemovalEdit(NSString *content, NSRange commandRange) {
    NSRange line = [content lineRangeForRange:commandRange];
    NSString *lineText = TMTrim([content substringWithRange:line]);
    NSString *command = TMTrim([content substringWithRange:commandRange]);
    return [TMTextEdit editWithRange:([lineText isEqualToString:command] ? line : commandRange) replacement:@""];
}

+ (nullable NSString *)contentByApplyingSettings:(TMDocumentFontSettings *)settings
                                     cjkFakeBold:(BOOL)cjkFakeBold
                                       toContent:(NSString *)content {
    if (![self contentHasPreamble:content]) return nil;
    NSMutableArray<TMTextEdit *> *edits = [NSMutableArray array];
    NSRange preamble = TMPreambleRange(content);
    TMDocumentFontSettings *current = [self settingsInContent:content];

    // 1. 字号：改 \documentclass 的选项，其余选项原样保留
    NSString *newSize = settings.sizeOption.length ? settings.sizeOption : nil;
    if (!((newSize == nil && current.sizeOption == nil) || [newSize isEqualToString:current.sizeOption])) {
        NSTextCheckingResult *dc = TMFirstLiveMatch(TMDocumentClassRegex(), content, NSMakeRange(0, content.length));
        NSRange optRange = [dc rangeAtIndex:1];
        NSMutableArray<NSString *> *tokens = optRange.location == NSNotFound
            ? [NSMutableArray array] : TMOptionTokens([content substringWithRange:optRange]);
        [tokens filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *t, id _) { return !TMIsSizeOption(t); }]];
        if (newSize) [tokens addObject:newSize];
        NSString *cls = [content substringWithRange:[dc rangeAtIndex:2]];
        NSString *rebuilt = tokens.count
            ? [NSString stringWithFormat:@"\\documentclass[%@]{%@}", [tokens componentsJoinedByString:@","], cls]
            : [NSString stringWithFormat:@"\\documentclass{%@}", cls];
        [edits addObject:[TMTextEdit editWithRange:dc.range replacement:rebuilt]];
    }

    // 2. 字体命令：已有就改名（保留选项），设为默认就删掉，没有就排队插入
    NSMutableArray<NSString *> *newLines = [NSMutableArray array];
    NSTextCheckingResult *latin = TMFirstLiveMatch(TMFontCommandRegex(@"setmainfont"), content, preamble);
    NSTextCheckingResult *cjk = TMFirstLiveMatch(TMFontCommandRegex(@"setCJKmainfont"), content, preamble);
    BOOL insertLatin = NO, insertCJK = NO;

    if (settings.latinFont.length) {
        if (latin) [edits addObject:[TMTextEdit editWithRange:[latin rangeAtIndex:1] replacement:settings.latinFont]];
        else insertLatin = YES;
    } else if (latin) {
        [edits addObject:TMRemovalEdit(content, latin.range)];
    }
    if (settings.cjkFont.length) {
        if (cjk) [edits addObject:[TMTextEdit editWithRange:[cjk rangeAtIndex:1] replacement:settings.cjkFont]];
        else insertCJK = YES;
    } else if (cjk) {
        [edits addObject:TMRemovalEdit(content, cjk.range)];
    }

    // 3. 需要的宏包：ctex / xeCJK 都会带上 fontspec
    BOOL ctex = [self isCTeXContent:content];
    BOOL xeCJK = TMPackageLoaded(content, @"xeCJK");
    BOOL fontspec = TMPackageLoaded(content, @"fontspec") || TMPackageLoaded(content, @"unicode-math");
    BOOL addXeCJK = insertCJK && !ctex && !xeCJK;
    if (insertLatin && !ctex && !xeCJK && !fontspec && !addXeCJK && !cjk) [newLines addObject:@"\\usepackage{fontspec}"];
    if (addXeCJK) [newLines addObject:@"\\usepackage{xeCJK}"];
    if (insertLatin) [newLines addObject:[NSString stringWithFormat:@"\\setmainfont{%@}", settings.latinFont]];
    if (insertCJK) {
        [newLines addObject:[NSString stringWithFormat:@"\\setCJKmainfont%@{%@}", cjkFakeBold ? @"[AutoFakeBold]" : @"", settings.cjkFont]];
    }

    if (newLines.count) {
        NSUInteger begin = TMBeginDocumentLocation(content);
        NSUInteger lineStart = [content lineRangeForRange:NSMakeRange(begin, 0)].location;
        BOOL beginStartsLine = [TMTrim([content substringWithRange:NSMakeRange(lineStart, begin - lineStart)]) length] == 0;
        NSString *block = [[newLines componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
        if (beginStartsLine) {
            [edits addObject:[TMTextEdit editWithRange:NSMakeRange(lineStart, 0) replacement:block]];
        } else {
            [edits addObject:[TMTextEdit editWithRange:NSMakeRange(begin, 0) replacement:[@"\n" stringByAppendingString:block]]];
        }
    }

    return TMApplyEdits(content, edits);
}

#pragma mark - 缺失字体

+ (NSArray<NSString *> *)missingFontNamesInLog:(NSString *)log {
    if (log.length == 0) return @[];
    static NSRegularExpression *continuationRe, *fontspecRe, *primitiveRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // fontspec 的多行消息：续行以 "(fontspec)  " 开头
        continuationRe = TMRegex(@"\\n\\((?:fontspec|xeCJK)\\)\\s*", 0);
        fontspecRe = TMRegex(@"The font \"([^\"]+)\" cannot be found", 0);
        // XeTeX 原语：! Font \x="Name:feature" at 10pt not loadable
        primitiveRe = TMRegex(@"! Font \\\\\\S+?=\"([^\"]+)\"[^\\n]*not loadable", 0);
    });
    NSString *joined = [continuationRe stringByReplacingMatchesInString:log options:0 range:NSMakeRange(0, log.length) withTemplate:@" "];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    NSRange all = NSMakeRange(0, joined.length);
    for (NSTextCheckingResult *m in [fontspecRe matchesInString:joined options:0 range:all]) {
        [names addObject:[joined substringWithRange:[m rangeAtIndex:1]]];
    }
    for (NSTextCheckingResult *m in [primitiveRe matchesInString:joined options:0 range:all]) {
        NSString *name = [joined substringWithRange:[m rangeAtIndex:1]];
        name = [[name componentsSeparatedByString:@":"].firstObject componentsSeparatedByString:@"/"].firstObject;
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"[] "]];
        if (name.length) [names addObject:name];
    }
    return names.array;
}

+ (nullable NSString *)failingCTeXFontsetInLog:(NSString *)log {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = TMRegex(@"ctex-fontset-([A-Za-z]+)\\.def:\\d+: Package fontspec Error", 0); });
    // TeX 按 79 列折行，文件名常被拆开，先拼回去
    NSString *flat = [log stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    NSTextCheckingResult *m = [re firstMatchInString:flat options:0 range:NSMakeRange(0, flat.length)];
    return m ? [flat substringWithRange:[m rangeAtIndex:1]] : nil;
}

+ (nullable NSString *)contentByRemovingCTeXFontset:(NSString *)fontset inContent:(NSString *)content {
    static NSRegularExpression *ctexPackageRe;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ ctexPackageRe = TMRegex(@"\\\\usepackage\\s*\\[([^\\]]*)\\]\\s*\\{ctex\\}", 0); });

    NSString *target = [[@"fontset=" stringByAppendingString:fontset] lowercaseString];
    NSMutableArray<TMTextEdit *> *edits = [NSMutableArray array];
    NSRange all = NSMakeRange(0, content.length);
    NSMutableArray<NSTextCheckingResult *> *candidates = [NSMutableArray array];
    NSTextCheckingResult *dc = TMFirstLiveMatch(TMDocumentClassRegex(), content, all);
    if (dc) [candidates addObject:dc];
    NSTextCheckingResult *pkg = TMFirstLiveMatch(ctexPackageRe, content, TMPreambleRange(content));
    if (pkg) [candidates addObject:pkg];

    for (NSTextCheckingResult *m in candidates) {
        NSRange optRange = [m rangeAtIndex:1];
        if (optRange.location == NSNotFound) continue;
        NSMutableArray<NSString *> *tokens = TMOptionTokens([content substringWithRange:optRange]);
        NSUInteger before = tokens.count;
        [tokens filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *t, id _) {
            return ![[[t stringByReplacingOccurrencesOfString:@" " withString:@""] lowercaseString] isEqualToString:target];
        }]];
        if (tokens.count == before) continue;
        NSString *joined = [tokens componentsJoinedByString:@","];
        if (tokens.count) {
            [edits addObject:[TMTextEdit editWithRange:optRange replacement:joined]];
        } else {
            // 选项清空：连方括号一起去掉
            NSString *text = [content substringWithRange:m.range];
            NSString *bracketed = [NSString stringWithFormat:@"[%@]", [content substringWithRange:optRange]];
            NSRange b = [text rangeOfString:bracketed];
            [edits addObject:[TMTextEdit editWithRange:NSMakeRange(m.range.location + b.location, b.length) replacement:@""]];
        }
    }
    return edits.count ? TMApplyEdits(content, edits) : nil;
}

/// 键：小写字体名；值：macOS 上的替代，按优先级。只收常见“换台电脑就没了”的字体。
static NSDictionary<NSString *, NSArray<NSString *> *> *TMReplacementTable(void) {
    static NSDictionary *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *song = @[@"Songti SC", @"STSong"];
        NSArray *hei = @[@"Heiti SC", @"STHeiti", @"Hiragino Sans GB"];
        NSArray *kai = @[@"Kaiti SC", @"STKaiti"];
        NSArray *fang = @[@"STFangsong"];
        NSArray *sans = @[@"Hiragino Sans GB", @"Heiti SC"];
        NSArray *songTC = @[@"Songti TC"];
        NSArray *heiTC = @[@"Heiti TC"];
        NSMutableDictionary *t = [NSMutableDictionary dictionary];
        for (NSString *k in @[@"simsun", @"nsimsun", @"宋体", @"新宋体", @"source han serif sc", @"source han serif cn",
                              @"noto serif cjk sc", @"noto serif sc", @"思源宋体"]) t[k] = song;
        for (NSString *k in @[@"simhei", @"黑体"]) t[k] = hei;
        for (NSString *k in @[@"kaiti", @"楷体", @"kaiti_gb2312", @"楷体_gb2312"]) t[k] = kai;
        for (NSString *k in @[@"fangsong", @"仿宋", @"fangsong_gb2312", @"仿宋_gb2312"]) t[k] = fang;
        // 苹方在 macOS 上是系统保留字体，XeTeX 读不到，一并换成可用的黑体
        for (NSString *k in @[@"microsoft yahei", @"microsoft yahei ui", @"微软雅黑", @"dengxian", @"等线",
                              @"source han sans sc", @"source han sans cn", @"noto sans cjk sc", @"noto sans sc", @"思源黑体",
                              @"pingfang sc", @"苹方-简", @"苹方"]) t[k] = sans;
        for (NSString *k in @[@"mingliu", @"pmingliu", @"細明體", @"新細明體", @"细明体", @"新细明体"]) t[k] = songTC;
        for (NSString *k in @[@"microsoft jhenghei", @"微軟正黑體", @"微软正黑体", @"pingfang tc", @"pingfang hk", @"苹方-繁"]) t[k] = heiTC;
        t[@"lisu"] = t[@"隶书"] = @[@"Libian SC", @"Baoli SC"];
        t[@"youyuan"] = t[@"幼圆"] = @[@"Yuanti SC"];
        t[@"calibri"] = t[@"segoe ui"] = @[@"Helvetica Neue", @"Helvetica"];
        t[@"cambria"] = @[@"Times New Roman"];
        t[@"consolas"] = @[@"Menlo"];
        table = t;
    });
    return table;
}

/// 小写并去掉 .ttf / .ttc / .otf 扩展名。
static NSString *TMNormalizedFontKey(NSString *name) {
    NSString *key = TMTrim(name).lowercaseString;
    for (NSString *ext in @[@".ttf", @".ttc", @".otf"]) {
        if ([key hasSuffix:ext]) return [key substringToIndex:key.length - ext.length];
    }
    return key;
}

+ (NSArray<NSString *> *)replacementCandidatesForFont:(NSString *)fontName {
    return TMReplacementTable()[TMNormalizedFontKey(fontName)] ?: @[];
}

/// 匹配一组字体名：只认字体参数的位置（前面是 { = , [，后面是 } , ]），可带文件扩展名，不区分大小写。
static NSRegularExpression *TMFontNameRegex(NSArray<NSString *> *names) {
    NSArray *sorted = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return a.length == b.length ? NSOrderedSame : (a.length > b.length ? NSOrderedAscending : NSOrderedDescending);
    }];
    NSMutableArray *escaped = [NSMutableArray array];
    for (NSString *n in sorted) [escaped addObject:[NSRegularExpression escapedPatternForString:n]];
    NSString *pattern = [NSString stringWithFormat:@"(?<=[{=,\\[])[ \\t]*((?:%@)(?:\\.(?:ttf|ttc|otf))?)(?=[ \\t]*[},\\]])",
                         [escaped componentsJoinedByString:@"|"]];
    return TMRegex(pattern, NSRegularExpressionCaseInsensitive);
}

/// 字体名只在“字体相关行”上认，避免把正文里的“宋体”两个字也改掉。
static NSArray<NSTextCheckingResult *> *TMFontLineMatches(NSRegularExpression *re, NSString *content) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:content options:0 range:NSMakeRange(0, content.length)]) {
        NSRange line = [content lineRangeForRange:m.range];
        if ([[content substringWithRange:line] rangeOfString:@"font" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [result addObject:m];
        }
    }
    return result;
}

+ (NSArray<NSString *> *)knownReplaceableFontNamesInContent:(NSString *)content {
    if (content.length == 0) return @[];
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ re = TMFontNameRegex(TMReplacementTable().allKeys); });
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (NSTextCheckingResult *m in TMFontLineMatches(re, content)) {
        [names addObject:[content substringWithRange:[m rangeAtIndex:1]]];
    }
    return names.array;
}

+ (NSString *)contentByReplacingFonts:(NSDictionary<NSString *, NSString *> *)replacements
                            inContent:(NSString *)content
                                count:(nullable NSUInteger *)count {
    if (count) *count = 0;
    if (replacements.count == 0 || content.length == 0) return content;
    NSMutableDictionary<NSString *, NSString *> *byKey = [NSMutableDictionary dictionary];
    for (NSString *name in replacements) byKey[TMNormalizedFontKey(name)] = replacements[name];

    NSMutableArray<TMTextEdit *> *edits = [NSMutableArray array];
    for (NSTextCheckingResult *m in TMFontLineMatches(TMFontNameRegex(replacements.allKeys), content)) {
        NSRange r = [m rangeAtIndex:1];
        NSString *to = byKey[TMNormalizedFontKey([content substringWithRange:r])];
        if (to) [edits addObject:[TMTextEdit editWithRange:r replacement:to]];
    }
    if (count) *count = edits.count;
    return edits.count ? TMApplyEdits(content, edits) : content;
}

@end
