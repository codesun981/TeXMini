#import "TMDocument.h"
#import "TMCompiler.h"
#import "TMMagicComments.h"
#import <CommonCrypto/CommonDigest.h>
#import <libproc.h>
#import <signal.h>
#include <sys/stat.h>

@interface TMCompilerOutputPaths ()
@property (nonatomic, readwrite) NSURL *outputDirectoryURL;
@property (nonatomic, readwrite) NSURL *auxiliaryDirectoryURL;
@property (nonatomic, readwrite) NSString *jobName;
@property (nonatomic, readwrite) BOOL usesManagedAuxiliaryDirectory;
@end

@implementation TMCompilerOutputPaths
- (NSURL *)outputFileURLWithExtension:(NSString *)extension {
    return [self.outputDirectoryURL URLByAppendingPathComponent:[self.jobName stringByAppendingPathExtension:extension]];
}
- (NSURL *)auxiliaryFileURLWithExtension:(NSString *)extension {
    return [self.auxiliaryDirectoryURL URLByAppendingPathComponent:[self.jobName stringByAppendingPathExtension:extension]];
}
- (NSURL *)pdfURL { return [self outputFileURLWithExtension:@"pdf"]; }
- (NSURL *)synctexURL { return [self outputFileURLWithExtension:@"synctex.gz"]; }
@end

/// 把路径选项与其他参数分开；命令行和产物定位必须使用同一份解析结果。
static NSDictionary<NSString *, NSString *> *TMOutputOptions(NSArray<NSString *> *arguments, NSMutableArray<NSString *> *remaining) {
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *argument = arguments[i];
        NSString *option = [argument hasPrefix:@"--"] ? [argument substringFromIndex:2]
                         : [argument hasPrefix:@"-"] ? [argument substringFromIndex:1] : @"";
        NSRange equals = [option rangeOfString:@"="];
        NSString *name = equals.location == NSNotFound ? option : [option substringToIndex:equals.location];
        NSString *key = ([name isEqualToString:@"outdir"] || [name isEqualToString:@"output-directory"]) ? @"output"
                      : ([name isEqualToString:@"auxdir"] || [name isEqualToString:@"aux-directory"]) ? @"auxiliary"
                      : [name isEqualToString:@"jobname"] ? @"job" : nil;
        if (!key || (equals.location == NSNotFound && (i + 1 == arguments.count || [arguments[i + 1] hasPrefix:@"-"]))) {
            if (remaining) [remaining addObject:argument];
            continue;
        }
        options[key] = equals.location == NSNotFound ? arguments[++i] : [option substringFromIndex:equals.location + 1];
    }
    return options;
}

static NSURL *TMOutputDirectoryURL(NSString *path, NSURL *relativeTo) {
    if (path.length == 0) return relativeTo;
    return [NSURL fileURLWithPath:path.stringByExpandingTildeInPath isDirectory:YES relativeToURL:relativeTo].URLByStandardizingPath.absoluteURL;
}

@interface TMCompiler ()
@property (nonatomic, assign) BOOL isCompiling;
@property (nonatomic) NSUInteger activeCompilationCount;
@property (nonatomic, assign) BOOL wasCancelled;
@property (nonatomic, strong) NSTask *currentTask;
@property (nonatomic, strong) NSCache<NSArray *, NSArray *> *engineDecisionCache;
@property (nonatomic, strong) NSCache<NSString *, NSArray *> *dependencyFeatureCache;
@end

/// 解码 data 中完整的 UTF-8 前缀并从 data 中移除；末尾被截断的多字节字符留在 data 里。
/// 整块都不是合法 UTF-8 时按 Latin-1 解码（老式 8 位编码的日志）。
static NSString *TMDecodeCompleteUTF8Prefix(NSMutableData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger keep = 0;
    // 从末尾往回找最后一个起始字节，判断它的多字节序列是否完整
    for (NSUInteger i = 1; i <= MIN((NSUInteger)3, length); i++) {
        uint8_t b = bytes[length - i];
        if ((b & 0xC0) == 0x80) continue;   // 续字节
        NSUInteger need = (b & 0xE0) == 0xC0 ? 2 : (b & 0xF0) == 0xE0 ? 3 : (b & 0xF8) == 0xF0 ? 4 : 1;
        if (need > i) keep = i;
        break;
    }
    NSUInteger usable = length - keep;
    if (usable == 0) return nil;
    NSData *head = [data subdataWithRange:NSMakeRange(0, usable)];
    NSString *text = [[NSString alloc] initWithData:head encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:head encoding:NSISOLatin1StringEncoding];
    [data replaceBytesInRange:NSMakeRange(0, usable) withBytes:NULL length:0];
    return text;
}

/// 去掉每行第一个未转义 % 之后的内容（\% 是字面百分号，保留）。
static NSString *TMStripTeXComments(NSString *content) {
    if (![content containsString:@"%"]) return content;
    NSMutableString *result = [NSMutableString stringWithCapacity:content.length];
    [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSUInteger cut = line.length;
        for (NSUInteger i = 0; i < line.length; i++) {
            unichar c = [line characterAtIndex:i];
            if (c == '\\') { i++; continue; }
            if (c == '%') { cut = i; break; }
        }
        [result appendString:[line substringToIndex:cut]];
        [result appendString:@"\n"];
    }];
    return result;
}

/// 这些关键词出现（去掉注释后）即需要 XeLaTeX；fontspec 的字体命令可能经 unicode-math 等间接加载。
static BOOL TMNeedsXeTeXKeyword(NSString *code) {
    return [code containsString:@"ctex"] || [code containsString:@"xeCJK"] || [code containsString:@"fontspec"] ||
           [code containsString:@"\\setmainfont"] || [code containsString:@"\\setCJKmainfont"];
}

static BOOL TMContainsCJK(NSString *code) {
    static NSCharacterSet *cjk;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(0x4E00, 0x9FFF - 0x4E00 + 1)]; // 基本汉字
        [set addCharactersInRange:NSMakeRange(0x3400, 0x4DBF - 0x3400 + 1)];  // 扩展 A
        [set addCharactersInRange:NSMakeRange(0x3000, 0x303F - 0x3000 + 1)];  // 中文标点
        [set addCharactersInRange:NSMakeRange(0xFF00, 0xFFEF - 0xFF00 + 1)];  // 全角字符
        cjk = [set copy];
    });
    return [code rangeOfCharacterFromSet:cjk].location != NSNotFound;
}

/// 代码里 \documentclass / \LoadClass（.cls）和 \usepackage / \RequirePackage（.sty）引用的名字，形如 "thuthesis.cls"。
static NSArray<NSString *> *TMDependencyFileNames(NSString *code) {
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:
              @"\\\\(documentclass|LoadClass|usepackage|RequirePackage)\\s*(?:\\[[^\\]]*\\])?\\s*\\{([^}]*)\\}" options:0 error:nil];
    });
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    [re enumerateMatchesInString:code options:0 range:NSMakeRange(0, code.length)
                      usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *kind = [code substringWithRange:[m rangeAtIndex:1]];
        NSString *ext = [kind hasSuffix:@"Class"] || [kind isEqualToString:@"documentclass"] ? @"cls" : @"sty";
        for (NSString *part in [[code substringWithRange:[m rangeAtIndex:2]] componentsSeparatedByString:@","]) {
            NSString *name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length) [names addObject:[name stringByAppendingPathExtension:ext]];
        }
    }];
    return names.array;
}

/// 标准文档类：一定不含 ctex，不必去 texmf 里找。
static BOOL TMIsStandardClass(NSString *fileName) {
    static NSSet *standard;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        standard = [NSSet setWithArray:@[@"article", @"report", @"book", @"letter", @"slides", @"minimal", @"proc",
                                         @"amsart", @"amsbook", @"amsproc", @"beamer", @"memoir", @"standalone",
                                         @"scrartcl", @"scrreprt", @"scrbook", @"scrlttr2", @"IEEEtran", @"llncs",
                                         @"elsarticle", @"acmart", @"revtex4-1", @"revtex4-2", @"svjour3", @"moderncv"]];
    });
    return [standard containsObject:fileName.stringByDeletingPathExtension];
}

/// 装在 TeX 发行版里的文件路径（kpsewhich）；结果按文件名缓存，同一会话只查一次。
static NSString *TMKpsewhich(NSString *fileName) {
    static NSMutableDictionary<NSString *, id> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    @synchronized (cache) {
        id hit = cache[fileName];
        if (hit) return hit == [NSNull null] ? nil : hit;
    }
    NSString *path = nil;
    NSString *kpsewhich = [TMCompiler findExecutableNamed:@"kpsewhich"];
    if (kpsewhich) {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:kpsewhich];
        task.arguments = @[fileName];
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        if ([task launchAndReturnError:nil]) {
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            NSString *out = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (task.terminationStatus == 0 && out.length) path = out;
        }
    }
    @synchronized (cache) { cache[fileName] = path ?: [NSNull null]; }
    return path;
}

/// 空数组也缓存：不存在的本地依赖之后出现时必须使决策失效。
static NSArray *TMEngineFileFingerprint(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0) return @[];
    return @[@(info.st_dev), @(info.st_ino), @(info.st_size),
             @(info.st_mtimespec.tv_sec), @(info.st_mtimespec.tv_nsec),
             @(info.st_ctimespec.tv_sec), @(info.st_ctimespec.tv_nsec)];
}

static BOOL TMEngineFingerprintsUnchanged(NSDictionary<NSString *, id> *fingerprints) {
    for (NSString *path in fingerprints) {
        if (![fingerprints[path] isEqual:TMEngineFileFingerprint(path)]) return NO;
    }
    return YES;
}

/// 同一路径若在一次遍历中变化，或读取失败，用 NSNull 保留“不稳定”状态，后续不能覆盖它。
static void TMRecordEngineFingerprint(NSMutableDictionary *fingerprints, NSString *path, NSArray *fingerprint) {
    id previous = fingerprints[path];
    if (!previous) fingerprints[path] = fingerprint;
    else if (![previous isEqual:fingerprint]) fingerprints[path] = NSNull.null;
}

/// 先结束子孙进程再结束自身（SIGTERM）。
static void TMTerminateProcessTree(pid_t pid) {
    if (pid <= 0) return;
    pid_t children[256];
    int count = proc_listchildpids(pid, children, sizeof(children));
    for (int i = 0; i < count && i < 256; i++) TMTerminateProcessTree(children[i]);
    kill(pid, SIGTERM);
}

@implementation TMCompiler

+ (instancetype)sharedCompiler {
    static TMCompiler *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[TMCompiler alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _engine = TMTeXEngineLatexmk;
        _isCompiling = NO;
        _shellEscapeEnabled = NO;
        _extraArguments = @[];
        _engineDecisionCache = [NSCache new];
        _engineDecisionCache.countLimit = 64;
        _dependencyFeatureCache = [NSCache new];
        _dependencyFeatureCache.countLimit = 256;
    }
    return self;
}

#pragma mark - 可执行文件查找

+ (NSArray<NSString *> *)searchDirectories {
    return @[
        @"/Library/TeX/texbin",
        @"/usr/local/bin",
        @"/opt/homebrew/bin",
        @"/usr/bin",
        @"/bin"
    ];
}

+ (nullable NSString *)findExecutableNamed:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in [self searchDirectories]) {
        NSString *candidate = [dir stringByAppendingPathComponent:name];
        if ([fm isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

+ (nullable NSString *)findExecutablePathForEngine:(TMTeXEngine)engine {
    switch (engine) {
        case TMTeXEngineLatexmk: return [self findExecutableNamed:@"latexmk"];
        case TMTeXEngineXeLaTeX: return [self findExecutableNamed:@"xelatex"];
        case TMTeXEnginePDFLaTeX: return [self findExecutableNamed:@"pdflatex"];
        case TMTeXEngineLuaLaTeX: return [self findExecutableNamed:@"lualatex"];
    }
    return nil;
}

+ (BOOL)isMacTeXInstalled {
    return [self findExecutableNamed:@"latexmk"] != nil ||
           [self findExecutableNamed:@"pdflatex"] != nil ||
           [self findExecutableNamed:@"xelatex"] != nil;
}

#pragma mark - 引擎决策

/// 依赖只保留与引擎有关的特征，不长期保留整个 .cls/.sty 正文。
- (NSArray *)engineDependencyFeaturesForText:(NSString *)text {
    NSString *code = TMStripTeXComments(text);
    return @[@(TMNeedsXeTeXKeyword(code)), TMDependencyFileNames(code)];
}

- (NSArray *)dependencyFeaturesAtPath:(NSString *)path fingerprint:(NSArray *)fingerprint {
    if (fingerprint.count == 0) return nil;
    NSArray *entry = [self.dependencyFeatureCache objectForKey:path];
    if (entry && [entry[0] isEqual:fingerprint]) return entry[1];
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
                  ?: [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:nil];
    if (!text) return nil;
    NSArray *features = [self engineDependencyFeaturesForText:text];
    // 外部程序可能在读盘/解析期间改写文件；这样的快照不进入缓存。
    if ([fingerprint isEqual:TMEngineFileFingerprint(path)]) {
        [self.dependencyFeatureCache setObject:@[fingerprint, features] forKey:path];
    }
    return features;
}

/// 与原行为一样，按出现顺序最多查两层，命中后立即停止。
- (NSString *)dependencyNeedingXeTeX:(NSArray<NSString *> *)names directoryURL:(NSURL *)directoryURL
                              depth:(NSUInteger)depth fingerprints:(NSMutableDictionary *)fingerprints {
    if (depth == 0) return nil;
    for (NSString *fileName in names) {
        NSString *path = nil;
        NSArray *fingerprint = nil;
        if (directoryURL) {
            NSString *local = [[directoryURL.path stringByAppendingPathComponent:fileName] stringByStandardizingPath];
            fingerprint = TMEngineFileFingerprint(local);
            TMRecordEngineFingerprint(fingerprints, local, fingerprint);
            if (fingerprint.count) path = local;
        }
        if (!path && [fileName.pathExtension isEqualToString:@"cls"] && !TMIsStandardClass(fileName)) {
            path = TMKpsewhich(fileName);
            if (path) {
                fingerprint = TMEngineFileFingerprint(path);
                TMRecordEngineFingerprint(fingerprints, path, fingerprint);
            }
        }
        NSArray *features = path ? [self dependencyFeaturesAtPath:path fingerprint:fingerprint] : nil;
        if (!features) {
            if (path && fingerprint.count) fingerprints[path] = NSNull.null;
            continue;
        }
        if ([features[0] boolValue]) return fileName;
        NSString *nested = [self dependencyNeedingXeTeX:features[1]
                                          directoryURL:[NSURL fileURLWithPath:path.stringByDeletingLastPathComponent]
                                                 depth:depth - 1 fingerprints:fingerprints];
        if (nested) return [NSString stringWithFormat:@"%@ → %@", fileName, nested];
    }
    return nil;
}

/// 返回 xelatex / pdflatex / lualatex 之一。
- (NSString *)effectiveEngineNameForContent:(NSString *)content {
    return [self effectiveEngineNameForContent:content directoryURL:nil reason:NULL];
}

- (NSString *)effectiveEngineNameForContent:(NSString *)content
                               directoryURL:(nullable NSURL *)directoryURL
                                     reason:(NSString **)reason {
    return [self effectiveEngineNameForContent:content directoryURL:directoryURL preferredEngine:self.engine reason:reason];
}

- (NSString *)effectiveEngineNameForContent:(NSString *)content
                               directoryURL:(nullable NSURL *)directoryURL
                            preferredEngine:(TMTeXEngine)preferredEngine
                                     reason:(NSString **)reason {
    NSString *why = nil;
    NSString *engine = [self decideEngineForContent:content ?: @"" directoryURL:directoryURL preferredEngine:preferredEngine reason:&why];
    if (reason) *reason = why;
    return engine;
}

- (NSString *)decideEngineForContent:(NSString *)content directoryURL:(nullable NSURL *)directoryURL preferredEngine:(TMTeXEngine)preferredEngine reason:(NSString **)reason {
    if (preferredEngine != TMTeXEngineLatexmk) {
        *reason = @"手动选择的引擎";
        if (preferredEngine == TMTeXEngineXeLaTeX) return @"xelatex";
        if (preferredEngine == TMTeXEngineLuaLaTeX) return @"lualatex";
        return @"pdflatex";
    }

    NSString *program = [[TMMagicComments magicCommentsInString:content][@"program"] lowercaseString];
    if ([program isEqualToString:@"xelatex"] || [program isEqualToString:@"pdflatex"] || [program isEqualToString:@"lualatex"]) {
        *reason = @"文件里的魔法注释 % !TEX program 指定";
        return program;
    }

    // 先去掉注释：注释掉的 %\usepackage{ctex} 不应让整篇改用更慢的 XeLaTeX
    NSString *code = TMStripTeXComments(content);
    if (TMNeedsXeTeXKeyword(code)) {
        *reason = @"自动：检测到 ctex / xeCJK / fontspec 等需要 XeLaTeX 的宏包";
        return @"xelatex";
    }

    NSArray *dependencies = TMDependencyFileNames(code);
    BOOL hasCJK = TMContainsCJK(code);
    BOOL wrapsCJK = [code containsString:@"{CJK"] || [code containsString:@"CJKutf8"];
    NSURL *directory = directoryURL.URLByStandardizingPath;
    NSArray *key = @[directory.path ?: @"", dependencies, @(hasCJK), @(wrapsCJK)];
    // NSCache 支持并发访问；不把磁盘/kpsewhich 包在锁里，实际编译不等后台预览的慢目录。
    NSArray *entry = [self.engineDecisionCache objectForKey:key];
    if (entry && TMEngineFingerprintsUnchanged(entry[2])) { *reason = entry[1]; return entry[0]; }

    NSMutableDictionary *fingerprints = [NSMutableDictionary dictionary];
    NSString *culprit = [self dependencyNeedingXeTeX:dependencies directoryURL:directory depth:2 fingerprints:fingerprints];
    NSString *engine = @"pdflatex";
    NSString *why = @"自动：未检测到中文或字体宏包，使用 pdfLaTeX";
    if (culprit) {
        engine = @"xelatex";
        why = [NSString stringWithFormat:@"自动：%@ 里加载了 ctex / xeCJK / fontspec 等需要 XeLaTeX 的宏包", culprit];
    } else if (hasCJK && !wrapsCJK) {
        engine = @"xelatex";
        why = @"自动：正文含中文字符";
    }
    if (TMEngineFingerprintsUnchanged(fingerprints)) {
        [self.engineDecisionCache setObject:@[engine, why, [fingerprints copy]] forKey:key];
    }
    *reason = why;
    return engine;
}

+ (NSString *)latexmkFlagForEngineName:(NSString *)name {
    if ([name isEqualToString:@"xelatex"]) return @"-xelatex";
    if ([name isEqualToString:@"lualatex"]) return @"-lualatex";
    return @"-pdf";
}

+ (NSURL *)auxiliaryDirectoryForTeXFileURL:(NSURL *)texFileURL {
    NSString *path = texFileURL.URLByStandardizingPath.path ?: @"";
    const char *utf8 = path.UTF8String;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8, (CC_LONG)strlen(utf8), digest);
    NSMutableString *hash = [NSMutableString string];
    for (int i = 0; i < 6; i++) [hash appendFormat:@"%02x", digest[i]];
    NSString *name = [NSString stringWithFormat:@"%@-%@", texFileURL.URLByDeletingPathExtension.lastPathComponent, hash];

    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject
                    ?: [NSURL fileURLWithPath:NSTemporaryDirectory()];
    return [[[caches URLByAppendingPathComponent:@"TeXMini"] URLByAppendingPathComponent:@"build"] URLByAppendingPathComponent:name isDirectory:YES];
}

+ (TMCompilerOutputPaths *)outputPathsForTeXFileURL:(NSURL *)texFileURL
                               auxFilesBesideSource:(BOOL)auxFilesBesideSource
                                     extraArguments:(NSArray<NSString *> *)extraArguments {
    NSDictionary *options = TMOutputOptions(extraArguments, nil);
    NSURL *sourceDirectory = texFileURL.URLByDeletingLastPathComponent.URLByStandardizingPath;
    TMCompilerOutputPaths *paths = [TMCompilerOutputPaths new];
    paths.outputDirectoryURL = TMOutputDirectoryURL(options[@"output"], sourceDirectory);
    paths.usesManagedAuxiliaryDirectory = !auxFilesBesideSource && !options[@"auxiliary"];
    paths.auxiliaryDirectoryURL = options[@"auxiliary"]
        ? TMOutputDirectoryURL(options[@"auxiliary"], [options[@"auxiliary"] length] ? sourceDirectory : paths.outputDirectoryURL)
        : auxFilesBesideSource ? paths.outputDirectoryURL : [self auxiliaryDirectoryForTeXFileURL:texFileURL];
    NSString *baseName = texFileURL.URLByDeletingPathExtension.lastPathComponent;
    NSString *jobName = [options[@"job"] stringByReplacingOccurrencesOfString:@"%A" withString:baseName];
    paths.jobName = jobName.length ? jobName : baseName;
    return paths;
}

+ (NSArray<NSString *> *)argumentsForEngineName:(NSString *)engineName
                                     useLatexmk:(BOOL)useLatexmk
                                      outputDir:(NSString *)outputDir
                                         auxDir:(nullable NSString *)auxDir
                                       fileName:(NSString *)fileName
                                    shellEscape:(BOOL)shellEscape
                                 extraArguments:(nullable NSArray<NSString *> *)extra {
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    if (useLatexmk) [args addObject:[self latexmkFlagForEngineName:engineName]];
    [args addObjectsFromArray:@[
        @"-synctex=1",
        @"-interaction=nonstopmode",
        @"-halt-on-error",
        @"-file-line-error"
    ]];
    if (shellEscape) [args addObject:@"-shell-escape"];
    BOOL separateAux = auxDir.length > 0 && ![auxDir isEqualToString:outputDir];
    if (useLatexmk) {
        [args addObject:[NSString stringWithFormat:@"-outdir=%@", outputDir]];
        if (separateAux) [args addObject:[NSString stringWithFormat:@"-auxdir=%@", auxDir]];
    } else {
        [args addObject:[NSString stringWithFormat:@"-output-directory=%@", separateAux ? auxDir : outputDir]];
    }
    for (NSString *a in extra) {
        if (a.length) [args addObject:a];
    }
    [args addObject:fileName];
    return args;
}

#pragma mark - 编译

- (BOOL)hasActiveCompilationWork {
    return self.activeCompilationCount > 0;
}

- (void)cancelCompilation {
    if (self.isCompiling && self.currentTask) {
        self.wasCancelled = YES;
        // 只 terminate latexmk 的话，它拉起的 xelatex / bibtex 会变孤儿继续写 aux，连子进程一起结束
        if (self.currentTask.running) TMTerminateProcessTree(self.currentTask.processIdentifier);
    }
}

- (void)cancelCompilationAndDiscardResults {
    NSTask *task = self.currentTask;
    // 先让主队列上尚未执行的回调失效；终止进程和排空管道仍由原任务后台完成。
    self.currentTask = nil;
    self.isCompiling = NO;
    self.wasCancelled = NO;
    if (task.running) TMTerminateProcessTree(task.processIdentifier);
}

/// 独立创建任务，便于不依赖 TeX 安装的生命周期测试注入可控子进程。
- (NSTask *)newCompilationTask {
    return [NSTask new];
}

- (void)compileFileAtURL:(NSURL *)texFileURL {
    if (self.isCompiling) {
        [self cancelCompilationAndDiscardResults];
    }

    NSString *content = [TMDocument documentWithContentsOfURL:texFileURL error:nil].content ?: @"";

    // 1. 魔法注释 root：改为编译主文件
    NSURL *rootURL = [TMMagicComments rootFileURLForDocumentURL:texFileURL content:content];
    if (rootURL && [[NSFileManager defaultManager] fileExistsAtPath:rootURL.path]) {
        texFileURL = rootURL;
        content = [TMDocument documentWithContentsOfURL:texFileURL error:nil].content ?: content;
    }

    // 2. 决定引擎与命令行
    NSString *engineName = [self effectiveEngineNameForContent:content directoryURL:texFileURL.URLByDeletingLastPathComponent reason:NULL];
    NSString *latexmkPath = [self.class findExecutableNamed:@"latexmk"];
    NSString *enginePath = [self.class findExecutableNamed:engineName];

    NSString *workingDir = [texFileURL URLByDeletingLastPathComponent].path;
    TMCompilerOutputPaths *paths = [self.class outputPathsForTeXFileURL:texFileURL
                                                   auxFilesBesideSource:self.auxFilesBesideSource
                                                         extraArguments:self.extraArguments];
    NSString *fileName = texFileURL.lastPathComponent;
    NSURL *expectedPDFURL = paths.pdfURL;
    NSMutableArray<NSString *> *extraArguments = [NSMutableArray array];
    TMOutputOptions(self.extraArguments, extraArguments);
    [extraArguments addObject:[@"-jobname=" stringByAppendingString:paths.jobName]];
    BOOL shellEscape = self.shellEscapeEnabled;

    NSString *execPath = latexmkPath ?: enginePath;

    if (!execPath) {
        if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
            [self.delegate compilerDidFailWithError:@"LaTeX 引擎未找到，请确认 MacTeX 已正确安装并位于 /Library/TeX/texbin。" line:0 fullLog:@"" issues:@[]];
        }
        return;
    }

    self.isCompiling = YES;
    self.wasCancelled = NO;
    NSDate *startTime = [NSDate date];

    if ([self.delegate respondsToSelector:@selector(compilerDidStartCompilingDocument:engineName:useLatexmk:)]) {
        [self.delegate compilerDidStartCompilingDocument:texFileURL engineName:engineName useLatexmk:(latexmkPath != nil)];
    } else if ([self.delegate respondsToSelector:@selector(compilerDidStartCompilingDocument:)]) {
        [self.delegate compilerDidStartCompilingDocument:texFileURL];
    }

    NSTask *task = [self newCompilationTask];
    task.executableURL = [NSURL fileURLWithPath:execPath];
    task.currentDirectoryURL = [NSURL fileURLWithPath:workingDir];

    // 关键：注入 TeX PATH，GUI App 默认拿不到 shell 的环境
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[NSProcessInfo processInfo].environment];
    NSString *currentPath = env[@"PATH"] ?: @"";
    NSString *texPath = [[TMCompiler searchDirectories] componentsJoinedByString:@":"];
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@:/usr/sbin:/sbin", texPath, currentPath];
    task.environment = env;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    self.currentTask = task;
    self.activeCompilationCount++;

    NSMutableString *fullOutput = [NSMutableString string];
    NSFileHandle *readHandle = pipe.fileHandleForReading;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *launchError = nil;
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *auxDir = paths.auxiliaryDirectoryURL.path;
        BOOL outputReady = [fm createDirectoryAtURL:paths.outputDirectoryURL withIntermediateDirectories:YES attributes:nil error:&launchError];
        if (outputReady && ![fm createDirectoryAtURL:paths.auxiliaryDirectoryURL withIntermediateDirectories:YES attributes:nil error:&launchError]) {
            if (paths.usesManagedAuxiliaryDirectory) {
                // 系统缓存不可写时仍可编译；用户显式指定的目录失败则报告实际错误。
                auxDir = paths.outputDirectoryURL.path;
                launchError = nil;
            }
        }
        if (!launchError) {
            task.arguments = [TMCompiler argumentsForEngineName:engineName useLatexmk:(latexmkPath != nil)
                                                      outputDir:paths.outputDirectoryURL.path auxDir:auxDir fileName:fileName
                                                   shellEscape:shellEscape extraArguments:extraArguments];
            [task launchAndReturnError:&launchError];
        }
        if (launchError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.activeCompilationCount--;
                if (self.currentTask != task) return;
                self.isCompiling = NO;
                self.currentTask = nil;
                if (self.wasCancelled) {
                    self.wasCancelled = NO;
                    if ([self.delegate respondsToSelector:@selector(compilerDidCancel)]) [self.delegate compilerDidCancel];
                } else if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
                    [self.delegate compilerDidFailWithError:launchError.localizedDescription line:0 fullLog:@"" issues:@[]];
                }
            });
            return;
        }

        // 取消可能早于后台 launch，此时尚无 PID；启动后再检查，避免留下继续写文件的旧进程。
        dispatch_async(dispatch_get_main_queue(), ^{
            if ((self.currentTask != task || self.wasCancelled) && task.running) {
                TMTerminateProcessTree(task.processIdentifier);
            }
        });

        // 在后台读管道：末尾不完整的 UTF-8 字节留到下一块再解码，
        // 日志每 0.15 秒合并推一次主线程（latexmk 多遍输出上万行时不再逐块刷 UI）
        NSMutableData *pending = [NSMutableData data];
        NSMutableString *batch = [NSMutableString string];
        CFAbsoluteTime lastFlush = CFAbsoluteTimeGetCurrent();
        void (^flush)(void) = ^{
            if (batch.length == 0) return;
            NSString *text = [batch copy];
            [batch setString:@""];
            dispatch_async(dispatch_get_main_queue(), ^{
                [fullOutput appendString:text];
                if (self.currentTask == task && [self.delegate respondsToSelector:@selector(compilerDidOutputLog:)]) {
                    [self.delegate compilerDidOutputLog:text];
                }
            });
        };
        while (YES) {
            NSData *data = [readHandle availableData];
            if (data.length == 0) break;
            [pending appendData:data];
            NSString *chunk = TMDecodeCompleteUTF8Prefix(pending);
            if (chunk) [batch appendString:chunk];
            if (CFAbsoluteTimeGetCurrent() - lastFlush >= 0.15) {
                flush();
                lastFlush = CFAbsoluteTimeGetCurrent();
            }
        }
        if (pending.length > 0) {
            NSString *tail = [[NSString alloc] initWithData:pending encoding:NSUTF8StringEncoding]
                          ?: [[NSString alloc] initWithData:pending encoding:NSISOLatin1StringEncoding];
            if (tail) [batch appendString:tail];
        }
        flush();

        [task waitUntilExit];

        int exitCode = task.terminationStatus;
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.activeCompilationCount--;
            // 这个回调属于已被取消/替换的旧任务
            if (self.currentTask != task) return;

            self.isCompiling = NO;
            self.currentTask = nil;

            if (self.wasCancelled) {
                self.wasCancelled = NO;
                if ([self.delegate respondsToSelector:@selector(compilerDidCancel)]) {
                    [self.delegate compilerDidCancel];
                }
                return;
            }

            // 没有 latexmk 时引擎只能用一个目录；成功后把 PDF/SyncTeX 放到实际输出目录。
            NSError *outputError = nil;
            if (exitCode == 0 && !latexmkPath && ![auxDir isEqualToString:paths.outputDirectoryURL.path]) {
                for (NSString *ext in @[@"pdf", @"synctex.gz"]) {
                    NSString *name = [paths.jobName stringByAppendingPathExtension:ext];
                    NSURL *from = [NSURL fileURLWithPath:[auxDir stringByAppendingPathComponent:name]];
                    NSURL *to = [paths outputFileURLWithExtension:ext];
                    if (![fm fileExistsAtPath:from.path] && ![ext isEqualToString:@"pdf"]) continue;
                    if ([fm fileExistsAtPath:to.path]) {
                        [fm replaceItemAtURL:to withItemAtURL:from backupItemName:nil options:0 resultingItemURL:nil error:&outputError];
                    } else {
                        [fm moveItemAtURL:from toURL:to error:&outputError];
                    }
                    if (outputError) break;
                }
            }

            NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:fullOutput];
            BOOL pdfExists = [[NSFileManager defaultManager] fileExistsAtPath:expectedPDFURL.path];

            if (exitCode == 0 && pdfExists && !outputError) {
                if ([self.delegate respondsToSelector:@selector(compilerDidFinishSuccess:pdfURL:issues:)]) {
                    [self.delegate compilerDidFinishSuccess:elapsed pdfURL:expectedPDFURL issues:issues];
                }
            } else {
                TMLogIssue *firstError = [TMLogParser firstErrorInIssues:issues];
                NSString *summary = outputError ? [NSString stringWithFormat:@"无法保存编译产物：%@", outputError.localizedDescription]
                                                : firstError.message ?: @"编译未成功，请检查语法日志。";
                NSInteger line = firstError ? firstError.line : 0;
                if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
                    [self.delegate compilerDidFailWithError:summary line:line fullLog:fullOutput issues:issues];
                }
            }
        });
    });
}

@end
