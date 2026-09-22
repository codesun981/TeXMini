#import "TMCompiler.h"

@interface TMCompiler ()
@property (nonatomic, assign) BOOL isCompiling;
@property (nonatomic, strong) NSTask *currentTask;
@property (nonatomic, strong) NSURL *compilingFileURL;
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
    }
    return self;
}

+ (BOOL)isMacTeXInstalled {
    return [self findExecutablePathForEngine:TMTeXEngineLatexmk] != nil ||
           [self findExecutablePathForEngine:TMTeXEnginePDFLaTeX] != nil;
}

+ (nullable NSString *)findExecutablePathForEngine:(TMTeXEngine)engine {
    NSString *binaryName = @"latexmk";
    switch (engine) {
        case TMTeXEngineLatexmk: binaryName = @"latexmk"; break;
        case TMTeXEngineXeLaTeX: binaryName = @"xelatex"; break;
        case TMTeXEnginePDFLaTeX: binaryName = @"pdflatex"; break;
    }

    NSArray<NSString *> *searchDirs = @[
        @"/Library/TeX/texbin",
        @"/usr/local/bin",
        @"/opt/homebrew/bin",
        @"/usr/bin",
        @"/bin"
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in searchDirs) {
        NSString *candidate = [dir stringByAppendingPathComponent:binaryName];
        if ([fm isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (void)cancelCompilation {
    if (self.isCompiling && self.currentTask) {
        [self.currentTask terminate];
        self.isCompiling = NO;
    }
}

- (void)compileFileAtURL:(NSURL *)texFileURL {
    if (self.isCompiling) {
        [self cancelCompilation];
    }

    NSString *execPath = [TMCompiler findExecutablePathForEngine:self.engine];
    if (!execPath) {
        if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:)]) {
            [self.delegate compilerDidFailWithError:@"LaTeX 引擎未找到，请确认 MacTeX 已正确安装并位于 /Library/TeX/texbin。" line:0 fullLog:@""];
        }
        return;
    }

    self.isCompiling = YES;
    self.compilingFileURL = texFileURL;
    NSDate *startTime = [NSDate date];

    if ([self.delegate respondsToSelector:@selector(compilerDidStartCompilingDocument:)]) {
        [self.delegate compilerDidStartCompilingDocument:texFileURL];
    }

    NSString *workingDir = [texFileURL URLByDeletingLastPathComponent].path;
    NSString *fileName = texFileURL.lastPathComponent;
    NSString *baseName = [texFileURL.URLByDeletingPathExtension lastPathComponent];
    NSURL *expectedPDFURL = [[texFileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"pdf"]];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:execPath];
    task.currentDirectoryURL = [NSURL fileURLWithPath:workingDir];

    // 关键：注入系统 PATH 环境变量，防止 GUI App 丢失环境
    NSMutableDictionary *env = [NSMutableDictionary dictionaryWithDictionary:[NSProcessInfo processInfo].environment];
    NSString *currentPath = env[@"PATH"] ?: @"";
    NSString *texPath = @"/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    env[@"PATH"] = [NSString stringWithFormat:@"%@:%@", texPath, currentPath];
    task.environment = env;

    NSMutableArray<NSString *> *args = [NSMutableArray array];
    switch (self.engine) {
        case TMTeXEngineLatexmk: {
            NSString *content = [NSString stringWithContentsOfURL:texFileURL encoding:NSUTF8StringEncoding error:nil];
            BOOL isChineseOrXeTeX = [content containsString:@"ctex"] || [content containsString:@"UTF8"] || [content containsString:@"xeCJK"];
            NSString *pdfFlag = isChineseOrXeTeX ? @"-xelatex" : @"-pdf";
            [args addObjectsFromArray:@[
                pdfFlag,
                @"-synctex=1",
                @"-interaction=nonstopmode",
                @"-halt-on-error",
                [NSString stringWithFormat:@"-output-directory=%@", workingDir],
                fileName
            ]];
            break;
        }
        case TMTeXEngineXeLaTeX:
            [args addObjectsFromArray:@[
                @"-synctex=1",
                @"-interaction=nonstopmode",
                @"-halt-on-error",
                [NSString stringWithFormat:@"-output-directory=%@", workingDir],
                fileName
            ]];
            break;
        case TMTeXEnginePDFLaTeX:
            [args addObjectsFromArray:@[
                @"-synctex=1",
                @"-interaction=nonstopmode",
                @"-halt-on-error",
                [NSString stringWithFormat:@"-output-directory=%@", workingDir],
                fileName
            ]];
            break;
    }
    task.arguments = args;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    self.currentTask = task;

    NSMutableString *fullOutput = [NSMutableString string];
    NSFileHandle *readHandle = pipe.fileHandleForReading;

    readHandle.readabilityHandler = ^(NSFileHandle *handle) {
        NSData *data = [handle availableData];
        if (data.length > 0) {
            NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!chunk) {
                chunk = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
            }
            if (chunk) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [fullOutput appendString:chunk];
                    if ([self.delegate respondsToSelector:@selector(compilerDidOutputLog:)]) {
                        [self.delegate compilerDidOutputLog:chunk];
                    }
                });
            }
        }
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *launchError = nil;
        [task launchAndReturnError:&launchError];
        if (launchError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isCompiling = NO;
                if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:)]) {
                    [self.delegate compilerDidFailWithError:launchError.localizedDescription line:0 fullLog:@""];
                }
            });
            return;
        }

        [task waitUntilExit];
        readHandle.readabilityHandler = nil;

        // 读取剩余数据
        NSData *rest = [readHandle readDataToEndOfFile];
        if (rest.length > 0) {
            NSString *chunk = [[NSString alloc] initWithData:rest encoding:NSUTF8StringEncoding];
            if (chunk) [fullOutput appendString:chunk];
        }

        int exitCode = task.terminationStatus;
        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.isCompiling = NO;
            self.currentTask = nil;

            if (exitCode == 0 && [[NSFileManager defaultManager] fileExistsAtPath:expectedPDFURL.path]) {
                if ([self.delegate respondsToSelector:@selector(compilerDidFinishSuccess:pdfURL:)]) {
                    [self.delegate compilerDidFinishSuccess:elapsed pdfURL:expectedPDFURL];
                }
            } else {
                // 分析日志获取错误行和错误摘要
                NSInteger errorLine = 0;
                NSString *errorSummary = [self parseErrorFromLog:fullOutput detectedLine:&errorLine];
                if ([self.delegate respondsToSelector:@selector(compilerDidFailWithError:line:fullLog:)]) {
                    [self.delegate compilerDidFailWithError:errorSummary line:errorLine fullLog:fullOutput];
                }
            }
        });
    });
}

- (NSString *)parseErrorFromLog:(NSString *)log detectedLine:(NSInteger *)outLine {
    NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
    NSString *firstError = @"编译未成功，请检查语法日志。";
    NSInteger detectedLine = 0;

    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *l = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([l hasPrefix:@"! "]) {
            firstError = [l substringFromIndex:2];
            // 往后找 line number
            for (NSUInteger j = i + 1; j < MIN(i + 15, lines.count); j++) {
                NSString *next = lines[j];
                NSRange r = [next rangeOfString:@"l." options:0];
                if (r.location != NSNotFound) {
                    NSString *numStr = [next substringFromIndex:r.location + 2];
                    NSScanner *scanner = [NSScanner scannerWithString:numStr];
                    int foundNum = 0;
                    if ([scanner scanInt:&foundNum]) {
                        detectedLine = foundNum;
                        break;
                    }
                }
            }
            break;
        }
    }

    if (outLine) {
        *outLine = detectedLine;
    }
    return firstError;
}

@end
