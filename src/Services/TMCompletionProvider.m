#import "TMCompletionProvider.h"
#include <sys/stat.h>

@implementation TMCompletionContext
@end

@interface TMCompletionProvider ()
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray *> *fileEntries;
@property (nonatomic, copy) NSArray<NSString *> *orderedPaths;
@property (nonatomic, copy, nullable) NSString *excludedPath;
@property (nonatomic, copy, nullable) NSString *currentDocumentKey;
@property (nonatomic) NSUInteger currentRevision;
@property (nonatomic, copy, nullable) NSString *currentTextSnapshot;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *currentSymbols;
@property (nonatomic) NSUInteger latestRequest;
@property (nonatomic, copy) NSArray<NSString *> *cachedLabels;
@property (nonatomic, copy) NSArray<NSString *> *cachedCitations;
@property (nonatomic, copy) NSArray<NSString *> *cachedEnvironments;
@property (nonatomic, copy) NSArray<NSString *> *cachedCommands;
@property (nonatomic, strong, nullable) NSDate *cacheDate;
@property (nonatomic, strong, nullable) NSURL *cacheRoot;
@end

@implementation TMCompletionProvider
@synthesize projectRootURL = _projectRootURL;

static void *TMCompletionQueueKey = &TMCompletionQueueKey;

- (instancetype)init {
    if ((self = [super init])) {
        _workQueue = dispatch_queue_create("app.texmini.completion", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_workQueue, TMCompletionQueueKey, (__bridge void *)self, NULL);
        _fileEntries = [NSMutableDictionary dictionary];
        _orderedPaths = @[];
    }
    return self;
}

- (NSURL *)projectRootURL {
    @synchronized (self) { return _projectRootURL; }
}

- (void)setProjectRootURL:(NSURL *)url {
    NSURL *root = url.URLByStandardizingPath;
    @synchronized (self) {
        if (_projectRootURL == root || [_projectRootURL isEqual:root]) return;
        _projectRootURL = root;
        ++_latestRequest;
        dispatch_async(self.workQueue, ^{ self.cacheDate = nil; });
    }
}

#pragma mark - 上下文分析

+ (TMCompletionContext *)contextInText:(NSString *)text cursorLocation:(NSUInteger)cursor {
    TMCompletionContext *ctx = [[TMCompletionContext alloc] init];
    ctx.kind = TMCompletionKindNone;
    ctx.partialRange = NSMakeRange(cursor, 0);
    ctx.partial = @"";
    if (cursor > text.length) return ctx;

    // 只看当前行光标之前的部分
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(cursor, 0)];
    NSString *prefix = [text substringWithRange:NSMakeRange(lineRange.location, cursor - lineRange.location)];

    // 1. \cmd[opt]{a, b, par  ←  在花括号参数内
    static NSRegularExpression *argRegex;
    static NSRegularExpression *cmdRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        argRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\([A-Za-z]+\\*?)(?:\\[[^\\]]*\\])?\\{([^{}]*)$" options:0 error:nil];
        cmdRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)\\\\([A-Za-z]*)$" options:0 error:nil];
    });

    NSTextCheckingResult *m = [argRegex firstMatchInString:prefix options:0 range:NSMakeRange(0, prefix.length)];
    if (m) {
        NSString *cmd = [prefix substringWithRange:[m rangeAtIndex:1]];
        NSRange argRange = [m rangeAtIndex:2];
        NSString *arg = [prefix substringWithRange:argRange];
        TMCompletionKind kind = [self kindForArgumentOfCommand:cmd];
        if (kind != TMCompletionKindNone) {
            // 多值参数（\cite{a,b}）只补最后一段
            NSRange lastComma = [arg rangeOfString:@"," options:NSBackwardsSearch];
            NSUInteger partialStart = argRange.location;
            if (lastComma.location != NSNotFound) partialStart = argRange.location + lastComma.location + 1;
            NSString *partial = [prefix substringFromIndex:partialStart];
            // 去掉逗号后的空格
            NSUInteger trimmed = 0;
            while (trimmed < partial.length && [partial characterAtIndex:trimmed] == ' ') trimmed++;
            partialStart += trimmed;
            partial = [prefix substringFromIndex:partialStart];

            ctx.kind = kind;
            ctx.partial = partial;
            ctx.partialRange = NSMakeRange(lineRange.location + partialStart, partial.length);
            return ctx;
        }
    }

    // 2. 正在输入命令名：\sec
    m = [cmdRegex firstMatchInString:prefix options:0 range:NSMakeRange(0, prefix.length)];
    if (m) {
        NSRange r = m.range; // 含反斜杠
        ctx.kind = TMCompletionKindCommand;
        ctx.partial = [prefix substringWithRange:r];
        ctx.partialRange = NSMakeRange(lineRange.location + r.location, r.length);
        return ctx;
    }
    return ctx;
}

+ (TMCompletionKind)kindForArgumentOfCommand:(NSString *)cmd {
    NSString *c = [cmd stringByReplacingOccurrencesOfString:@"*" withString:@""];
    static NSSet *cites, *refs, *envs;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cites = [NSSet setWithArray:@[@"cite", @"citep", @"citet", @"citeauthor", @"citeyear", @"citealp", @"citealt",
                                      @"parencite", @"textcite", @"autocite", @"footcite", @"fullcite", @"nocite",
                                      @"Cite", @"Parencite", @"Textcite", @"Autocite", @"supercite", @"citenum"]];
        refs = [NSSet setWithArray:@[@"ref", @"eqref", @"pageref", @"autoref", @"cref", @"Cref", @"nameref",
                                     @"vref", @"labelcref", @"hyperref"]];
        envs = [NSSet setWithArray:@[@"begin", @"end"]];
    });
    if ([cites containsObject:c]) return TMCompletionKindCitation;
    if ([refs containsObject:c]) return TMCompletionKindReference;
    if ([envs containsObject:c]) return TMCompletionKindEnvironment;
    return TMCompletionKindNone;
}

#pragma mark - 文本扫描

static NSArray<NSString *> *TMCaptures(NSString *pattern, NSString *text) {
    if (text.length == 0) return @[];
    // 模式是固定的几条字面量：编译一次后复用（补全时会频繁调用）
    static NSCache<NSString *, NSRegularExpression *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ cache = [[NSCache alloc] init]; });
    NSRegularExpression *re = [cache objectForKey:pattern];
    if (!re) {
        re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        if (re) [cache setObject:re forKey:pattern];
    }
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    [re enumerateMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *v = [[text substringWithRange:[m rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (v.length > 0 && ![seen containsObject:v]) { [seen addObject:v]; [result addObject:v]; }
    }];
    return result;
}

+ (NSArray<NSString *> *)labelsInText:(NSString *)text {
    return TMCaptures(@"\\\\label\\s*\\{([^}]+)\\}", text);
}

+ (NSArray<NSString *> *)citationKeysInBibText:(NSString *)text {
    // @article{key, …   忽略 @comment / @preamble / @string
    NSArray *all = TMCaptures(@"@(?!comment|preamble|string)[A-Za-z]+\\s*[{(]\\s*([^,\\s{}]+)\\s*,", text);
    return all;
}

+ (NSArray<NSString *> *)environmentsInText:(NSString *)text {
    return TMCaptures(@"\\\\begin\\s*\\{([A-Za-z*]+)\\}", text);
}

+ (NSArray<NSString *> *)commandsInText:(NSString *)text {
    // 用户在文中自定义或用到的命令（长度 ≥ 2，避免 \a \b 之类噪音）
    NSArray *cmds = TMCaptures(@"\\\\([A-Za-z]{2,})", text);
    NSMutableArray *defined = [NSMutableArray array];
    for (NSString *c in TMCaptures(@"\\\\(?:newcommand|renewcommand|providecommand|DeclareMathOperator)\\*?\\s*\\{?\\\\([A-Za-z]+)\\}?", text)) {
        [defined addObject:c];
    }
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:defined];
    [set addObjectsFromArray:cmds];
    return set.array;
}

+ (NSArray<NSString *> *)builtinEnvironments {
    return @[@"document", @"abstract", @"itemize", @"enumerate", @"description", @"figure", @"figure*", @"table", @"table*",
             @"tabular", @"tabularx", @"array", @"center", @"flushleft", @"flushright", @"quote", @"quotation", @"verbatim",
             @"equation", @"equation*", @"align", @"align*", @"gather", @"gather*", @"multline", @"split", @"cases",
             @"matrix", @"pmatrix", @"bmatrix", @"vmatrix", @"theorem", @"lemma", @"proof", @"definition", @"corollary",
             @"example", @"remark", @"minipage", @"tikzpicture", @"algorithm", @"algorithmic", @"lstlisting", @"frame",
             @"thebibliography", @"subfigure", @"wrapfigure", @"titlepage", @"appendix"];
}

+ (NSArray<NSString *> *)builtinCommands {
    return @[@"documentclass", @"usepackage", @"begin", @"end", @"section", @"section*", @"subsection", @"subsubsection",
             @"chapter", @"part", @"paragraph", @"subparagraph", @"title", @"author", @"date", @"maketitle", @"tableofcontents",
             @"label", @"ref", @"eqref", @"pageref", @"autoref", @"cref", @"cite", @"citep", @"citet", @"footnote", @"caption",
             @"centering", @"includegraphics", @"input", @"include", @"newcommand", @"renewcommand", @"newenvironment",
             @"textbf", @"textit", @"texttt", @"textsc", @"textsf", @"textrm", @"emph", @"underline", @"item", @"hline",
             @"toprule", @"midrule", @"bottomrule", @"multicolumn", @"multirow", @"vspace", @"hspace", @"newpage", @"clearpage",
             @"linebreak", @"noindent", @"indent", @"bibliography", @"bibliographystyle", @"addbibresource", @"printbibliography",
             @"frac", @"dfrac", @"sqrt", @"sum", @"prod", @"int", @"iint", @"oint", @"lim", @"infty", @"partial", @"nabla",
             @"alpha", @"beta", @"gamma", @"delta", @"epsilon", @"varepsilon", @"zeta", @"eta", @"theta", @"iota", @"kappa",
             @"lambda", @"mu", @"nu", @"xi", @"pi", @"rho", @"sigma", @"tau", @"upsilon", @"phi", @"varphi", @"chi", @"psi",
             @"omega", @"Gamma", @"Delta", @"Theta", @"Lambda", @"Xi", @"Pi", @"Sigma", @"Phi", @"Psi", @"Omega",
             @"mathbf", @"mathrm", @"mathit", @"mathcal", @"mathbb", @"mathfrak", @"mathsf", @"mathtt", @"boldsymbol",
             @"left", @"right", @"big", @"Big", @"bigg", @"Bigg", @"langle", @"rangle", @"lfloor", @"rfloor", @"lceil", @"rceil",
             @"cdot", @"cdots", @"ldots", @"vdots", @"ddots", @"times", @"div", @"pm", @"mp", @"leq", @"geq", @"neq", @"approx",
             @"equiv", @"sim", @"simeq", @"propto", @"subset", @"subseteq", @"supset", @"in", @"notin", @"cup", @"cap",
             @"setminus", @"forall", @"exists", @"rightarrow", @"leftarrow", @"Rightarrow", @"Leftarrow", @"leftrightarrow",
             @"mapsto", @"to", @"hat", @"bar", @"vec", @"tilde", @"dot", @"ddot", @"overline", @"underline", @"overbrace",
             @"underbrace", @"text", @"operatorname", @"quad", @"qquad", @"sin", @"cos", @"tan", @"log", @"ln", @"exp", @"max",
             @"min", @"arg", @"det", @"dim", @"ker", @"deg", @"gcd", @"binom", @"choose", @"nonumber", @"notag", @"tag",
             @"hfill", @"vfill", @"small", @"footnotesize", @"scriptsize", @"tiny", @"large", @"Large", @"LARGE", @"huge", @"Huge",
             @"normalsize", @"url", @"href", @"today", @"LaTeX", @"TeX", @"verb", @"newline", @"par", @"setlength", @"geometry"];
}

#pragma mark - 项目扫描与缓存

- (void)invalidate {
    @synchronized (self) {
        ++_latestRequest;
        dispatch_async(self.workQueue, ^{ self.cacheDate = nil; });
    }
}

- (void)invalidateFileAtURL:(NSURL *)url {
    NSString *path = url.URLByStandardizingPath.path;
    @synchronized (self) {
        ++_latestRequest;
        dispatch_async(self.workQueue, ^{
            if (path) [self.fileEntries removeObjectForKey:path];
            self.cacheDate = nil;
        });
    }
}

- (nullable NSString *)readCompletionTextAtURL:(NSURL *)url {
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil]
        ?: [NSString stringWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:nil];
}

// 数组顺序固定为 label / citation / environment / command，文件与当前缓冲区共用提取路径。
- (NSArray<NSArray<NSString *> *> *)symbolsInText:(NSString *)text bibliography:(BOOL)bib {
    if (bib) return @[@[], [self.class citationKeysInBibText:text], @[], @[]];
    return @[[self.class labelsInText:text], @[], [self.class environmentsInText:text], [self.class commandsInText:text]];
}

static BOOL TMCompletionEqual(id a, id b) { return a == b || [a isEqual:b]; }

- (void)rescanIfNeededForRoot:(NSURL *)root excludingPath:(NSString *)excluded {
    BOOL sameRoot = TMCompletionEqual(self.cacheRoot, root);
    BOOL fresh = sameRoot && self.cacheDate && -self.cacheDate.timeIntervalSinceNow < 30.0;
    if (fresh && TMCompletionEqual(self.excludedPath, excluded)) return;

    if (!fresh) {
        if (!sameRoot) [self.fileEntries removeAllObjects];
        NSMutableArray<NSString *> *paths = [NSMutableArray array];
        NSDirectoryEnumerator *en = root ? [[NSFileManager defaultManager] enumeratorAtURL:root
                                            includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                            options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil] : nil;
        NSUInteger scanned = 0;
        for (NSURL *url in en) {
            if (en.level > 4) { [en skipDescendants]; continue; }
            NSNumber *isDir = nil;
            [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
            if (isDir.boolValue) {
                NSString *name = url.lastPathComponent.lowercaseString;
                if ([name isEqualToString:@"build"] || [name isEqualToString:@"node_modules"]) [en skipDescendants];
                continue;
            }
            NSString *ext = url.pathExtension.lowercaseString;
            BOOL isTeX = [ext isEqualToString:@"tex"] || [ext isEqualToString:@"ltx"] || [ext isEqualToString:@"latex"];
            BOOL isBib = [ext isEqualToString:@"bib"];
            if (!isTeX && !isBib) continue;
            struct stat info;
            if (stat(url.fileSystemRepresentation, &info) != 0 || info.st_size > 8 * 1024 * 1024) continue;
            if (++scanned > 400) break;
            NSString *path = url.URLByStandardizingPath.path;
            // inode 与 ctime 也参与：原子替换或保留 mtime 的等长编辑不能误命中。
            NSArray *fingerprint = @[@(info.st_dev), @(info.st_ino), @(info.st_size),
                @(info.st_mtimespec.tv_sec), @(info.st_mtimespec.tv_nsec),
                @(info.st_ctimespec.tv_sec), @(info.st_ctimespec.tv_nsec)];
            NSArray *entry = self.fileEntries[path];
            if (!entry || ![entry[0] isEqual:fingerprint]) {
                NSString *text = [self readCompletionTextAtURL:url];
                if (!text) { [self.fileEntries removeObjectForKey:path]; continue; }
                entry = @[fingerprint, [self symbolsInText:text bibliography:isBib]];
                self.fileEntries[path] = entry;
            }
            [paths addObject:path];
        }
        NSSet *livePaths = [NSSet setWithArray:paths];
        for (NSString *path in self.fileEntries.allKeys) {
            if (![livePaths containsObject:path]) [self.fileEntries removeObjectForKey:path];
        }
        self.orderedPaths = paths;
        self.cacheRoot = root;
        self.cacheDate = [NSDate date];
    }
    NSMutableOrderedSet *labels = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *cites = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *envs = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet *cmds = [NSMutableOrderedSet orderedSet];

    for (NSString *path in self.orderedPaths) {
        if ([path isEqualToString:excluded]) continue;
        NSArray *symbols = self.fileEntries[path][1];
        [labels addObjectsFromArray:symbols[0]];
        [cites addObjectsFromArray:symbols[1]];
        [envs addObjectsFromArray:symbols[2]];
        [cmds addObjectsFromArray:symbols[3]];
    }

    self.cachedLabels = labels.array;
    self.cachedCitations = cites.array;
    self.cachedEnvironments = envs.array;
    self.cachedCommands = cmds.array;
    self.excludedPath = excluded;
}

#pragma mark - 候选

- (NSArray<NSString *> *)completionsForContext:(TMCompletionContext *)context currentText:(NSString *)currentText {
    return [self completionsForContext:context currentText:currentText documentKey:nil revision:0];
}

static TMCompletionContext *TMCompletionSnapshot(TMCompletionContext *context) {
    TMCompletionContext *snapshot = [TMCompletionContext new];
    snapshot.kind = context.kind;
    snapshot.partial = [context.partial copy];
    snapshot.partialRange = context.partialRange;
    return snapshot;
}

- (NSArray<NSString *> *)completionsForContext:(TMCompletionContext *)context currentText:(NSString *)text
                                 documentKey:(NSString *)key revision:(NSUInteger)revision {
    context = TMCompletionSnapshot(context); text = [text copy]; key = [key copy];
    NSURL *root = self.projectRootURL;
    __block NSArray *result;
    void (^query)(void) = ^{ result = [self queryContext:context text:text documentKey:key revision:revision root:root]; };
    if (dispatch_get_specific(TMCompletionQueueKey) == (__bridge void *)self) query();
    else dispatch_sync(self.workQueue, query);
    return result;
}

- (void)requestCompletionsForContext:(TMCompletionContext *)context currentText:(NSString *)text
                        documentKey:(NSString *)key revision:(NSUInteger)revision
                         completion:(void (^)(NSArray<NSString *> *))completion {
    context = TMCompletionSnapshot(context); text = [text copy]; key = [key copy];
    @synchronized (self) {
        NSURL *root = _projectRootURL;
        NSUInteger request = ++_latestRequest;
        dispatch_async(self.workQueue, ^{
            @synchronized (self) { if (request != self->_latestRequest) return; }
            NSArray *result = [self queryContext:context text:text documentKey:key revision:revision root:root];
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized (self) { if (request != self->_latestRequest) return; }
                completion(result);
            });
        });
    }
}

- (NSArray<NSString *> *)queryContext:(TMCompletionContext *)context text:(NSString *)text
                         documentKey:(NSString *)key revision:(NSUInteger)revision root:(NSURL *)root {
    if (context.kind == TMCompletionKindNone) return @[];
    NSString *excluded = key.isAbsolutePath ? key.stringByStandardizingPath : nil;
    [self rescanIfNeededForRoot:root excludingPath:excluded];
    BOOL bibliography = [key.pathExtension.lowercaseString isEqualToString:@"bib"];
    if (context.kind != TMCompletionKindCitation || bibliography) {
        BOOL same = self.currentSymbols && TMCompletionEqual(key, self.currentDocumentKey) &&
            (key ? revision == self.currentRevision : [text isEqualToString:self.currentTextSnapshot]);
        if (!same) {
            self.currentSymbols = [self symbolsInText:text ?: @"" bibliography:bibliography];
            self.currentDocumentKey = key;
            self.currentRevision = revision;
            self.currentTextSnapshot = key ? nil : text;
        }
    }

    NSMutableOrderedSet<NSString *> *pool = [NSMutableOrderedSet orderedSet];
    NSString *partial = context.partial ?: @"";
    NSString *matchPartial = partial;

    switch (context.kind) {
        case TMCompletionKindCitation:
            if (bibliography) [pool addObjectsFromArray:self.currentSymbols[1]];
            [pool addObjectsFromArray:self.cachedCitations ?: @[]];
            break;
        case TMCompletionKindReference:
            // 当前文档（可能尚未保存）里的 label 放最前
            [pool addObjectsFromArray:self.currentSymbols[0]];
            [pool addObjectsFromArray:self.cachedLabels ?: @[]];
            break;
        case TMCompletionKindEnvironment:
            [pool addObjectsFromArray:self.currentSymbols[2]];
            [pool addObjectsFromArray:self.cachedEnvironments ?: @[]];
            [pool addObjectsFromArray:[TMCompletionProvider builtinEnvironments]];
            break;
        case TMCompletionKindCommand: {
            // partial 含反斜杠；候选也要带反斜杠
            matchPartial = partial.length > 0 ? [partial substringFromIndex:1] : @"";
            NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
            [names addObjectsFromArray:self.currentSymbols[3]];
            [names addObjectsFromArray:self.cachedCommands ?: @[]];
            [names addObjectsFromArray:[TMCompletionProvider builtinCommands]];
            for (NSString *n in names) [pool addObject:[@"\\" stringByAppendingString:n]];
            break;
        }
        default:
            break;
    }

    NSMutableArray<NSString *> *prefixMatches = [NSMutableArray array];
    NSMutableArray<NSString *> *substringMatches = [NSMutableArray array];
    for (NSString *cand in pool) {
        NSString *body = context.kind == TMCompletionKindCommand ? [cand substringFromIndex:1] : cand;
        if (matchPartial.length == 0) { [prefixMatches addObject:cand]; continue; }
        if ([body isEqualToString:matchPartial]) continue; // 已经输全了
        NSRange r = [body rangeOfString:matchPartial options:NSCaseInsensitiveSearch];
        if (r.location == 0) [prefixMatches addObject:cand];
        else if (r.location != NSNotFound && context.kind != TMCompletionKindCommand) [substringMatches addObject:cand];
    }
    // 命令按字母排序更好找；label / cite 保持出现顺序（通常与文档结构一致）
    if (context.kind == TMCompletionKindCommand || context.kind == TMCompletionKindEnvironment) {
        [prefixMatches sortUsingSelector:@selector(caseInsensitiveCompare:)];
    }
    NSArray *result = [prefixMatches arrayByAddingObjectsFromArray:substringMatches];
    return result.count > 60 ? [result subarrayWithRange:NSMakeRange(0, 60)] : result;
}

@end
