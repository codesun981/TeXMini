#import "TMCompiler.h"
#import "TMMagicComments.h"
#import <CommonCrypto/CommonDigest.h>
#import <libproc.h>
#import <signal.h>

@interface TMCompiler ()
@property (nonatomic, assign) BOOL isCompiling;
@property (nonatomic, assign) BOOL wasCancelled;
@property (nonatomic, strong) NSTask *currentTask;
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

/// 返回 xelatex / pdflatex / lualatex 之一。
- (NSString *)effectiveEngineNameForContent:(NSString *)content {
    if (self.engine == TMTeXEngineXeLaTeX) return @"xelatex";
    if (self.engine == TMTeXEnginePDFLaTeX) return @"pdflatex";
    if (self.engine == TMTeXEngineLuaLaTeX) return @"lualatex";

    NSString *program = [[TMMagicComments magicCommentsInString:content ?: @""][@"program"] lowercaseString];
    if ([program isEqualToString:@"xelatex"] || [program isEqualToString:@"pdflatex"] || [program isEqualToString:@"lualatex"]) {
        return program;
    }
    // ctex / xeCJK / fontspec，或直接用了 fontspec 的字体命令（可能经 unicode-math 等间接加载），都需要 XeLaTeX
    // 先去掉注释：注释掉的 %\usepackage{ctex} 不应让整篇改用更慢的 XeLaTeX
    content = TMStripTeXComments(content ?: @"");
    BOOL needsXeTeX = [content containsString:@"ctex"] || [content containsString:@"xeCJK"] || [content containsString:@"fontspec"] ||
                      [content containsString:@"\\setmainfont"] || [content containsString:@"\\setCJKmainfont"];
    return needsXeTeX ? @"xelatex" : @"pdflatex";
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

- (void)cancelCompilation {
    if (self.isCompiling && self.currentTask) {
        self.wasCancelled = YES;
        // 只 terminate latexmk 的话，它拉起的 xelatex / bibtex 会变孤儿继续写 aux，连子进程一起结束
        TMTerminateProcessTree(self.currentTask.processIdentifier);
    }
}

- (void)compileFileAtURL:(NSURL *)texFileURL {
    if (self.isCompiling) {
        // 正在编译时再次触发：先杀掉旧任务，旧任务结束回调会被 wasCancelled 吞掉
        [self cancelCompilation];
    }

    NSString *content = [NSString stringWithContentsOfURL:texFileURL encoding:NSUTF8StringEncoding error:nil] ?: @"";

    // 1. 魔法注释 root：改为编译主文件
    NSURL *rootURL = [TMMagicComments rootFileURLForDocumentURL:texFileURL content:content];
    if (rootURL && [[NSFileManager defaultManager] fileExistsAtPath:rootURL.path]) {
        texFileURL = rootURL;
        content = [NSString stringWithContentsOfURL:texFileURL encoding:NSUTF8StringEncoding error:nil] ?: content;
    }

    // 2. 决定引擎与命令行
    NSString *engineName = [self effectiveEngineNameForContent:content];
    NSString *latexmkPath = [TMCompiler findExecutableNamed:@"latexmk"];
    NSString *enginePath = [TMCompiler findExecutableNamed:engineName];

    NSString *workingDir = [texFileURL URLByDeletingLastPathComponent].path;
    NSString *auxDir = nil;
    if (!self.auxFilesBesideSource) {
        NSURL *auxURL = [TMCompiler auxiliaryDirectoryForTeXFileURL:texFileURL];
        // 建不出缓存目录就退回老行为，总比编译不了好
        if ([[NSFileManager defaultManager] createDirectoryAtURL:auxURL withIntermediateDirectories:YES attributes:nil error:nil]) {
            auxDir = auxURL.path;
        }
    }
    NSString *fileName = texFileURL.lastPathComponent;
    NSString *baseName = [texFileURL.URLByDeletingPathExtension lastPathComponent];
    NSURL *expectedPDFURL = [[texFileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"pdf"]];

    NSString *execPath = latexmkPath ?: enginePath;
    NSArray<NSString *> *args = execPath
        ? [TMCompiler argumentsForEngineName:engineName
                                  useLatexmk:(latexmkPath != nil)
                                   outputDir:workingDir
                                      auxDir:auxDir
                                    fileName:fileName
                                 shellEscape:self.shellEscapeEnabled
                              extraArguments:self.extraArguments]
        : @[];

    if (!execPath) {
        if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
            [self.delegate compilerDidFailWithError:@"LaTeX 引擎未找到，请确认 MacTeX 已正确安装并位于 /Library/TeX/texbin。" line:0 fullLog:@"" issues:@[]];
        }
        return;
    }

    self.isCompiling = YES;
    self.wasCancelled = NO;
    NSDate *startTime = [NSDate date];

    if ([self.delegate respondsToSelector:@selector(compilerDidStartCompilingDocument:)]) {
        [self.delegate compilerDidStartCompilingDocument:texFileURL];
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:execPath];
    task.currentDirectoryURL = [NSURL fileURLWithPath:workingDir];
    task.arguments = args;

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

    NSMutableString *fullOutput = [NSMutableString string];
    NSFileHandle *readHandle = pipe.fileHandleForReading;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *launchError = nil;
        [task launchAndReturnError:&launchError];
        if (launchError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isCompiling = NO;
                self.currentTask = nil;
                if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
                    [self.delegate compilerDidFailWithError:launchError.localizedDescription line:0 fullLog:@"" issues:@[]];
                }
            });
            return;
        }

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

            // 没有 latexmk 时引擎把 PDF 也写进了缓存目录，拷回源文件旁
            if (!latexmkPath && auxDir) {
                for (NSString *ext in @[@"pdf", @"synctex.gz"]) {
                    NSString *name = [baseName stringByAppendingPathExtension:ext];
                    NSURL *from = [NSURL fileURLWithPath:[auxDir stringByAppendingPathComponent:name]];
                    NSURL *to = [NSURL fileURLWithPath:[workingDir stringByAppendingPathComponent:name]];
                    if (![[NSFileManager defaultManager] fileExistsAtPath:from.path]) continue;
                    [[NSFileManager defaultManager] removeItemAtURL:to error:nil];
                    [[NSFileManager defaultManager] moveItemAtURL:from toURL:to error:nil];
                }
            }

            NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:fullOutput];
            BOOL pdfExists = [[NSFileManager defaultManager] fileExistsAtPath:expectedPDFURL.path];

            if (exitCode == 0 && pdfExists) {
                if ([self.delegate respondsToSelector:@selector(compilerDidFinishSuccess:pdfURL:issues:)]) {
                    [self.delegate compilerDidFinishSuccess:elapsed pdfURL:expectedPDFURL issues:issues];
                }
            } else {
                TMLogIssue *firstError = [TMLogParser firstErrorInIssues:issues];
                NSString *summary = firstError.message ?: @"编译未成功，请检查语法日志。";
                NSInteger line = firstError ? firstError.line : 0;
                if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:issues:)]) {
                    [self.delegate compilerDidFailWithError:summary line:line fullLog:fullOutput issues:issues];
                }
            }
        });
    });
}

@end
