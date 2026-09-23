#import "TMCompiler.h"
#import "TMMagicComments.h"

@interface TMCompiler ()
@property (nonatomic, assign) BOOL isCompiling;
@property (nonatomic, assign) BOOL wasCancelled;
@property (nonatomic, strong) NSTask *currentTask;
@end

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
    BOOL looksChinese = [content containsString:@"ctex"] || [content containsString:@"xeCJK"] || [content containsString:@"fontspec"];
    return looksChinese ? @"xelatex" : @"pdflatex";
}

+ (NSString *)latexmkFlagForEngineName:(NSString *)name {
    if ([name isEqualToString:@"xelatex"]) return @"-xelatex";
    if ([name isEqualToString:@"lualatex"]) return @"-lualatex";
    return @"-pdf";
}

+ (NSArray<NSString *> *)argumentsForEngineName:(NSString *)engineName
                                     useLatexmk:(BOOL)useLatexmk
                                     workingDir:(NSString *)workingDir
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
    [args addObject:[NSString stringWithFormat:@"-output-directory=%@", workingDir]];
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
        [self.currentTask terminate];
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
    NSString *fileName = texFileURL.lastPathComponent;
    NSString *baseName = [texFileURL.URLByDeletingPathExtension lastPathComponent];
    NSURL *expectedPDFURL = [[texFileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"pdf"]];

    NSString *execPath = latexmkPath ?: enginePath;
    NSArray<NSString *> *args = execPath
        ? [TMCompiler argumentsForEngineName:engineName
                                  useLatexmk:(latexmkPath != nil)
                                  workingDir:workingDir
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

    readHandle.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = [handle availableData];
        if (data.length == 0) return;
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                       ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        if (!chunk) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [fullOutput appendString:chunk];
            if ([self.delegate respondsToSelector:@selector(compilerDidOutputLog:)]) {
                [self.delegate compilerDidOutputLog:chunk];
            }
        });
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
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

        [task waitUntilExit];
        readHandle.readabilityHandler = nil;

        NSData *rest = [readHandle readDataToEndOfFile];
        NSString *restChunk = rest.length > 0 ? [[NSString alloc] initWithData:rest encoding:NSUTF8StringEncoding] : nil;

        int exitCode = task.terminationStatus;
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (restChunk) [fullOutput appendString:restChunk];

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
