#import "TMLaTeXScanner.h"

@implementation TMLaTeXHeading
@end

@interface TMLaTeXScanResult ()
@property (nonatomic, copy) NSArray<TMLaTeXHeading *> *headings;
@property (nonatomic, copy) NSString *blockSignature;
@end

@implementation TMLaTeXScanResult {
    TMLaTeXRegion *_regions;
    NSUInteger _count;
    NSUInteger _capacity;
    /// 可忽略区（注释 / 代码 / 原样参数）按起点排序后合并成不重叠的区间，供二分查找
    NSRange *_ignorable;
    NSUInteger _ignorableCount;
}

- (void)dealloc {
    free(_regions);
    free(_ignorable);
}

- (NSUInteger)regionCount { return _count; }
- (const TMLaTeXRegion *)regions { return _regions; }

- (void)addRegion:(TMLaTeXRegionKind)kind from:(NSUInteger)start to:(NSUInteger)end {
    if (end <= start) return;
    if (_count == _capacity) {
        _capacity = _capacity ? _capacity * 2 : 256;
        _regions = realloc(_regions, _capacity * sizeof(TMLaTeXRegion));
    }
    _regions[_count++] = (TMLaTeXRegion){kind, NSMakeRange(start, end - start)};
}

static int TMCompareRegions(const void *a, const void *b) {
    NSUInteger la = ((const TMLaTeXRegion *)a)->range.location;
    NSUInteger lb = ((const TMLaTeXRegion *)b)->range.location;
    return la < lb ? -1 : (la > lb ? 1 : 0);
}

- (void)finish {
    // 公式区在闭合时才登记，比里面的注释晚，排一次序
    qsort(_regions, _count, sizeof(TMLaTeXRegion), TMCompareRegions);

    _ignorable = malloc(MAX(_count, 1) * sizeof(NSRange));
    _ignorableCount = 0;
    NSMutableString *signature = [NSMutableString string];
    for (NSUInteger i = 0; i < _count; i++) {
        TMLaTeXRegion r = _regions[i];
        if (r.kind == TMLaTeXRegionComment || r.kind == TMLaTeXRegionVerbatim || r.kind == TMLaTeXRegionRaw) {
            if (_ignorableCount > 0 && r.range.location <= NSMaxRange(_ignorable[_ignorableCount - 1])) {
                NSRange *last = &_ignorable[_ignorableCount - 1];
                last->length = MAX(NSMaxRange(*last), NSMaxRange(r.range)) - last->location;
            } else {
                _ignorable[_ignorableCount++] = r.range;
            }
        }
        // 块级（长）区域的种类序列：数量或顺序变了，远处的颜色也会变
        if ((r.kind == TMLaTeXRegionMath || r.kind == TMLaTeXRegionVerbatim || r.kind == TMLaTeXRegionComment) && r.range.length > 80) {
            [signature appendFormat:@"%ld", (long)r.kind];
        }
    }
    self.blockSignature = signature;
}

- (BOOL)isIgnorableAtIndex:(NSUInteger)index {
    NSUInteger lo = 0, hi = _ignorableCount;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        NSRange r = _ignorable[mid];
        if (index < r.location) hi = mid;
        else if (index >= NSMaxRange(r)) lo = mid + 1;
        else return YES;
    }
    return NO;
}

@end

#pragma mark - 扫描器

typedef NS_ENUM(NSInteger, TMMathMode) {
    TMMathNone = 0,
    TMMathDollar,        // $…$
    TMMathDoubleDollar,  // $$…$$
    TMMathParen,         // \(…\)
    TMMathBracket,       // \[…\]
    TMMathEnvironment    // \begin{equation}…\end{equation}
};

@interface TMLaTeXScanner ()
@end

@implementation TMLaTeXScanner {
    const unichar *_s;
    NSUInteger _n;
    NSString *_string;
    TMLaTeXScanResult *_result;
    NSMutableArray<TMLaTeXHeading *> *_headings;
    /// 自定义命令 → 它包装的标题命令（mysub → subsection）
    NSMutableDictionary<NSString *, NSString *> *_headingAliases;
}

+ (NSSet<NSString *> *)headingCommands {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithArray:@[@"part", @"chapter", @"section", @"subsection", @"subsubsection", @"paragraph"]]; });
    return set;
}

+ (NSSet<NSString *> *)mathEnvironments {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableSet *m = [NSMutableSet set];
        for (NSString *e in @[@"equation", @"align", @"alignat", @"gather", @"multline", @"eqnarray", @"flalign", @"displaymath", @"math", @"dmath"]) {
            [m addObject:e];
            [m addObject:[e stringByAppendingString:@"*"]];
        }
        set = m;
    });
    return set;
}

+ (NSSet<NSString *> *)verbatimEnvironments {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"verbatim", @"verbatim*", @"Verbatim", @"Verbatim*", @"BVerbatim", @"LVerbatim",
                                    @"lstlisting", @"minted", @"filecontents", @"filecontents*"]];
    });
    return set;
}

+ (TMOutlineLevel)levelForHeadingCommand:(NSString *)name {
    if ([name isEqualToString:@"part"]) return TMOutlineLevelPart;
    if ([name isEqualToString:@"chapter"]) return TMOutlineLevelChapter;
    if ([name isEqualToString:@"subsection"]) return TMOutlineLevelSubsection;
    if ([name isEqualToString:@"subsubsection"]) return TMOutlineLevelSubsubsection;
    if ([name isEqualToString:@"paragraph"]) return TMOutlineLevelParagraph;
    return TMOutlineLevelSection;
}

+ (TMLaTeXScanResult *)scanString:(NSString *)string {
    TMLaTeXScanner *scanner = [[TMLaTeXScanner alloc] init];
    return [scanner scan:string ?: @""];
}

- (TMLaTeXScanResult *)scan:(NSString *)string {
    _string = string;
    _n = string.length;
    unichar *buffer = malloc(MAX(_n, 1) * sizeof(unichar));
    [string getCharacters:buffer range:NSMakeRange(0, _n)];
    _s = buffer;
    _result = [[TMLaTeXScanResult alloc] init];
    _headings = [NSMutableArray array];
    _headingAliases = [NSMutableDictionary dictionary];

    [self scanMain];

    free(buffer);
    _s = NULL;
    _result.headings = _headings;
    [_result finish];
    return _result;
}

#pragma mark 基础读取

static BOOL TMIsLetter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '@';
}

/// i 指向反斜杠；返回命令名结束位置（字母命令读到非字母；控制符号只占一个字符）
- (NSUInteger)commandEndAt:(NSUInteger)i {
    NSUInteger j = i + 1;
    if (j >= _n) return j;
    if (!TMIsLetter(_s[j])) return j + 1;
    while (j < _n && TMIsLetter(_s[j])) j++;
    return j;
}

- (NSUInteger)skipSpaces:(NSUInteger)i {
    while (i < _n && (_s[i] == ' ' || _s[i] == '\t')) i++;
    return i;
}

/// 空格、制表符、单个换行都跳过（参数之间允许换行，空行不行）
- (NSUInteger)skipWhitespace:(NSUInteger)i {
    i = [self skipSpaces:i];
    if (i < _n && _s[i] == '\n') i = [self skipSpaces:i + 1];
    return i;
}

/// i 指向 open；返回配对的 close 位置（跳过转义），找不到返回 NSNotFound
- (NSUInteger)matchFrom:(NSUInteger)i open:(unichar)open close:(unichar)close {
    NSInteger depth = 0;
    for (NSUInteger j = i; j < _n; j++) {
        unichar c = _s[j];
        if (c == '\\') { j++; continue; }
        if (c == '%') { while (j < _n && _s[j] != '\n') j++; continue; }
        if (c == open) depth++;
        else if (c == close && --depth == 0) return j;
    }
    return NSNotFound;
}

/// 读 {name}；成功时返回名字并把 *end 设为 } 之后
- (nullable NSString *)braceArgumentAt:(NSUInteger)i end:(NSUInteger *)end {
    i = [self skipWhitespace:i];
    if (i >= _n || _s[i] != '{') return nil;
    NSUInteger close = [self matchFrom:i open:'{' close:'}'];
    if (close == NSNotFound) return nil;
    if (end) *end = close + 1;
    return [_string substringWithRange:NSMakeRange(i + 1, close - i - 1)];
}

/// 跳过若干个 [..]（以及 beamer 的 <..>）
- (NSUInteger)skipOptionalArguments:(NSUInteger)i {
    while (YES) {
        NSUInteger j = [self skipWhitespace:i];
        if (j < _n && _s[j] == '[') {
            NSUInteger close = [self matchFrom:j open:'[' close:']'];
            if (close == NSNotFound) return i;
            i = close + 1;
        } else if (j < _n && _s[j] == '<') {
            NSUInteger k = j;
            while (k < _n && _s[k] != '>' && _s[k] != '\n') k++;
            if (k >= _n || _s[k] != '>') return i;
            i = k + 1;
        } else {
            return i;
        }
    }
}

/// 从 i 起找字面上的 \end{name}，返回反斜杠位置
- (NSUInteger)findEnd:(NSString *)name from:(NSUInteger)i {
    NSString *needle = [NSString stringWithFormat:@"\\end{%@}", name];
    NSRange r = [_string rangeOfString:needle options:NSLiteralSearch range:NSMakeRange(i, _n - i)];
    return r.location;
}

#pragma mark 主循环

- (void)scanMain {
    TMMathMode mode = TMMathNone;
    NSString *mathEnv = nil;
    NSUInteger mathStart = 0;
    BOOL lineHasContent = NO;
    NSUInteger i = 0;

    while (i < _n) {
        unichar c = _s[i];

        if (c == '\n') {
            // 空行 = 分段：$ 与 \[ 公式不能跨段，丢掉未闭合的，避免一处漏写染黄全文
            if (!lineHasContent && mode != TMMathNone && mode != TMMathEnvironment) mode = TMMathNone;
            lineHasContent = NO;
            i++;
            continue;
        }
        if (c != ' ' && c != '\t' && c != '\r') lineHasContent = YES;

        if (c == '%') {
            NSUInteger j = i;
            while (j < _n && _s[j] != '\n') j++;
            [_result addRegion:TMLaTeXRegionComment from:i to:j];
            i = j;
            continue;
        }

        if (c == '$') {
            BOOL doubled = i + 1 < _n && _s[i + 1] == '$';
            if (mode == TMMathNone) {
                mode = doubled ? TMMathDoubleDollar : TMMathDollar;
                mathStart = i;
                i += doubled ? 2 : 1;
            } else if (mode == TMMathDollar) {
                // 行内公式里遇到 $ 就是闭合：$a$$b$ 是两段
                [_result addRegion:TMLaTeXRegionMath from:mathStart to:i + 1];
                mode = TMMathNone;
                i++;
            } else if (mode == TMMathDoubleDollar) {
                NSUInteger end = doubled ? i + 2 : i + 1;
                [_result addRegion:TMLaTeXRegionMath from:mathStart to:end];
                mode = TMMathNone;
                i = end;
            } else {
                i++; // \[ … \] 或 equation 里的 $ 不管
            }
            continue;
        }

        if (c != '\\') { i++; continue; }

        // —— 控制序列 ——
        NSUInteger nameEnd = [self commandEndAt:i];
        if (nameEnd > _n) { i = _n; break; }
        unichar first = i + 1 < _n ? _s[i + 1] : 0;

        if (!TMIsLetter(first)) {
            // 控制符号：\( \) \[ \] 切换公式，其余（\\ \$ \% \{ …）原样跳过
            if (first == '(' && mode == TMMathNone) { mode = TMMathParen; mathStart = i; }
            else if (first == '[' && mode == TMMathNone) { mode = TMMathBracket; mathStart = i; }
            else if ((first == ')' && mode == TMMathParen) || (first == ']' && mode == TMMathBracket)) {
                [_result addRegion:TMLaTeXRegionMath from:mathStart to:nameEnd];
                mode = TMMathNone;
            }
            i = nameEnd;
            continue;
        }

        NSString *name = [_string substringWithRange:NSMakeRange(i + 1, nameEnd - i - 1)];

        if (mode != TMMathNone) {
            // 公式里只关心 equation 等环境的结束
            if (mode == TMMathEnvironment && [name isEqualToString:@"end"]) {
                NSUInteger argEnd = 0;
                NSString *env = [self braceArgumentAt:nameEnd end:&argEnd];
                if ([env isEqualToString:mathEnv]) {
                    [_result addRegion:TMLaTeXRegionEnvironment from:i to:argEnd];
                    [_result addRegion:TMLaTeXRegionMath from:mathStart to:argEnd];
                    mode = TMMathNone;
                    i = argEnd;
                    continue;
                }
            }
            // 公式里的命令也标出来，着色时叠在公式底色之上
            [_result addRegion:TMLaTeXRegionCommand from:i to:nameEnd];
            i = nameEnd;
            continue;
        }

        i = [self handleCommand:name at:i nameEnd:nameEnd mode:&mode mathEnv:&mathEnv mathStart:&mathStart];
    }
    // 到结尾都没闭合的公式不着色（和正在输入的 \begin{equation} 一样）
}

/// 正文里的一个 \name；返回继续扫描的位置
- (NSUInteger)handleCommand:(NSString *)name at:(NSUInteger)i nameEnd:(NSUInteger)nameEnd
                       mode:(TMMathMode *)mode mathEnv:(NSString **)mathEnv mathStart:(NSUInteger *)mathStart {
    NSUInteger end = nameEnd;
    if (end < _n && _s[end] == '*') end++;

    // \verb|…|：整段按原样
    if ([name isEqualToString:@"verb"]) {
        if (end < _n && !TMIsLetter(_s[end]) && _s[end] != ' ' && _s[end] != '\n') {
            unichar delim = _s[end];
            NSUInteger j = end + 1;
            while (j < _n && _s[j] != delim && _s[j] != '\n') j++;
            if (j < _n && _s[j] == delim) {
                [_result addRegion:TMLaTeXRegionVerbatim from:i to:j + 1];
                return j + 1;
            }
        }
        [_result addRegion:TMLaTeXRegionCommand from:i to:end];
        return end;
    }

    [_result addRegion:TMLaTeXRegionCommand from:i to:end];

    // \url{…} \href{…}：参数里的 % # _ 不是 TeX 语法
    if ([name isEqualToString:@"url"] || [name isEqualToString:@"href"] || [name isEqualToString:@"path"]) {
        NSUInteger j = [self skipSpaces:end];
        if (j < _n && _s[j] == '{') {
            NSUInteger k = j + 1;
            while (k < _n && _s[k] != '}' && _s[k] != '\n') k++;
            if (k < _n && _s[k] == '}') {
                [_result addRegion:TMLaTeXRegionRaw from:j + 1 to:k];
                return k + 1;
            }
        }
        return end;
    }

    if ([name isEqualToString:@"begin"] || [name isEqualToString:@"end"]) {
        NSUInteger argEnd = 0;
        NSString *env = [self braceArgumentAt:nameEnd end:&argEnd];
        if (!env) return end;
        [_result addRegion:TMLaTeXRegionEnvironment from:i to:argEnd];
        if ([name isEqualToString:@"end"]) return argEnd;
        return [self handleBeginEnvironment:env at:i argEnd:argEnd mode:mode mathEnv:mathEnv mathStart:mathStart];
    }

    // 命令定义：定义体只做浅着色，不切换公式 / 代码块，里面的 \section{#1} 也不是标题
    if ([name isEqualToString:@"newcommand"] || [name isEqualToString:@"renewcommand"] ||
        [name isEqualToString:@"providecommand"] || [name isEqualToString:@"DeclareRobustCommand"] ||
        [name isEqualToString:@"def"] || [name isEqualToString:@"gdef"] || [name isEqualToString:@"edef"]) {
        return [self handleDefinitionAt:end isDef:[name hasSuffix:@"def"]];
    }
    if ([name isEqualToString:@"newenvironment"] || [name isEqualToString:@"renewenvironment"]) {
        NSUInteger argEnd = 0;
        if (![self braceArgumentAt:end end:&argEnd]) return end;
        NSUInteger j = [self skipOptionalArguments:argEnd];
        for (int body = 0; body < 2; body++) {
            j = [self skipWhitespace:j];
            if (j >= _n || _s[j] != '{') break;
            NSUInteger close = [self matchFrom:j open:'{' close:'}'];
            if (close == NSNotFound) break;
            [self scanFlatFrom:j + 1 to:close];
            j = close + 1;
        }
        return j;
    }

    NSString *headingCommand = [[TMLaTeXScanner headingCommands] containsObject:name] ? name : _headingAliases[name];
    if (headingCommand || [name isEqualToString:@"frametitle"]) {
        NSUInteger j = [self skipOptionalArguments:end];  // \section[短标题]{完整标题}
        NSUInteger argEnd = 0;
        NSString *title = [self braceArgumentAt:j end:&argEnd];
        if (title) {
            TMLaTeXHeading *h = [[TMLaTeXHeading alloc] init];
            h.commandName = name;
            h.rawTitle = title;
            h.location = i;
            // beamer 的帧放在 section 之下
            h.level = headingCommand ? [TMLaTeXScanner levelForHeadingCommand:headingCommand] : TMOutlineLevelSubsection;
            [_headings addObject:h];
        }
        // 标题里可能有 $…$，参数交给主循环继续扫
        return end;
    }
    return end;
}

- (NSUInteger)handleBeginEnvironment:(NSString *)env at:(NSUInteger)i argEnd:(NSUInteger)argEnd
                                mode:(TMMathMode *)mode mathEnv:(NSString **)mathEnv mathStart:(NSUInteger *)mathStart {
    if ([[TMLaTeXScanner mathEnvironments] containsObject:env]) {
        *mode = TMMathEnvironment;
        *mathEnv = env;
        *mathStart = i;
        return argEnd;
    }

    BOOL isComment = [env isEqualToString:@"comment"];
    if (isComment || [[TMLaTeXScanner verbatimEnvironments] containsObject:env]) {
        NSUInteger contentStart = argEnd;
        if (!isComment) {
            contentStart = [self skipOptionalArguments:argEnd];            // lstlisting[language=…]
            if ([env isEqualToString:@"minted"] || [env hasPrefix:@"filecontents"]) {
                NSUInteger langEnd = 0;
                if ([self braceArgumentAt:contentStart end:&langEnd]) contentStart = langEnd; // minted{python}
            }
        }
        NSUInteger endLoc = [self findEnd:env from:contentStart];
        if (endLoc == NSNotFound) return argEnd; // 还没写 \end：先当普通环境
        [_result addRegion:(isComment ? TMLaTeXRegionComment : TMLaTeXRegionVerbatim) from:contentStart to:endLoc];
        NSUInteger endArg = endLoc + 5 + env.length + 2;
        [_result addRegion:TMLaTeXRegionEnvironment from:endLoc to:endArg];
        return endArg;
    }

    if ([env isEqualToString:@"frame"]) {
        // \begin{frame}[opts]{帧标题}
        NSUInteger j = [self skipOptionalArguments:argEnd];
        NSUInteger k = [self skipSpaces:j];
        if (k < _n && _s[k] == '{') {
            NSUInteger titleEnd = 0;
            NSString *title = [self braceArgumentAt:k end:&titleEnd];
            if (title.length) {
                TMLaTeXHeading *h = [[TMLaTeXHeading alloc] init];
                h.commandName = @"frame";
                h.rawTitle = title;
                h.location = i;
                h.level = TMOutlineLevelSubsection;
                [_headings addObject:h];
            }
        }
    }
    return argEnd;
}

/// \newcommand{\foo}[1][默认]{定义体} 或 \def\foo#1{定义体}；end 指向命令名之后
- (NSUInteger)handleDefinitionAt:(NSUInteger)end isDef:(BOOL)isDef {
    NSUInteger j = [self skipWhitespace:end];
    NSString *macro = nil;
    if (j < _n && _s[j] == '{') j = [self skipWhitespace:j + 1];
    if (j < _n && _s[j] == '\\') {
        NSUInteger macroEnd = [self commandEndAt:j];
        macro = [_string substringWithRange:NSMakeRange(j + 1, MIN(macroEnd, _n) - j - 1)];
        [_result addRegion:TMLaTeXRegionCommand from:j to:MIN(macroEnd, _n)];
        j = macroEnd;
    }
    j = [self skipSpaces:j];
    if (j < _n && _s[j] == '}') j++;
    if (isDef) {
        while (j < _n && _s[j] != '{' && _s[j] != '\n') j++; // \def\foo#1#2{
    } else {
        j = [self skipOptionalArguments:j];
    }
    j = [self skipWhitespace:j];
    if (j >= _n || _s[j] != '{') return j;
    NSUInteger close = [self matchFrom:j open:'{' close:'}'];
    if (close == NSNotFound) return j + 1;

    [self scanFlatFrom:j + 1 to:close];

    // 定义体里包了一个以 #1 为标题的标准标题命令：这个宏就是标题
    if (macro.length && ![[TMLaTeXScanner headingCommands] containsObject:macro]) {
        static NSRegularExpression *bodyRegex;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            bodyRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(part|chapter|section|subsection|subsubsection|paragraph)\\*?\\s*(?:\\[[^\\]]*\\])?\\s*\\{\\s*#1\\s*\\}"
                                                                  options:0 error:nil];
        });
        NSTextCheckingResult *m = [bodyRegex firstMatchInString:_string options:0 range:NSMakeRange(j, close - j)];
        if (m) _headingAliases[macro] = [_string substringWithRange:[m rangeAtIndex:1]];
    }
    return close + 1;
}

/// 定义体内部：只标命令和注释，不进入公式 / 代码块
- (void)scanFlatFrom:(NSUInteger)start to:(NSUInteger)stop {
    NSUInteger i = start;
    while (i < stop) {
        unichar c = _s[i];
        if (c == '%') {
            NSUInteger j = i;
            while (j < stop && _s[j] != '\n') j++;
            [_result addRegion:TMLaTeXRegionComment from:i to:j];
            i = j;
        } else if (c == '\\') {
            NSUInteger e = MIN([self commandEndAt:i], stop);
            if (i + 1 < stop && TMIsLetter(_s[i + 1])) {
                if (e < stop && _s[e] == '*') e++;
                [_result addRegion:TMLaTeXRegionCommand from:i to:e];
            }
            i = MAX(e, i + 1);
        } else {
            i++;
        }
    }
}

@end
