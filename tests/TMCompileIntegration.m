// 集成测试：真实调用 latexmk 编译 sample 文件，验证 TMCompiler 端到端链路。
// 需要 MacTeX；tests/run_tests.sh 会在找不到 latexmk 时跳过。
#import <Foundation/Foundation.h>
#import "TMCompiler.h"

@interface TMCompileProbe : NSObject <TMCompilerDelegate>
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSURL *pdfURL;
@property (nonatomic, strong) NSURL *startedURL;
@property (nonatomic, copy) NSString *errorSummary;
@property (nonatomic, assign) NSInteger errorLine;
@property (nonatomic, strong) NSArray<TMLogIssue *> *issues;
@end

@implementation TMCompileProbe
- (void)compilerDidStartCompilingDocument:(NSURL *)fileURL { self.startedURL = fileURL; }
- (void)compilerDidFinishSuccess:(double)d pdfURL:(NSURL *)pdfURL issues:(NSArray<TMLogIssue *> *)issues {
    self.success = YES; self.pdfURL = pdfURL; self.issues = issues; self.finished = YES;
}
- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)line fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues {
    self.success = NO; self.errorSummary = summary; self.errorLine = line; self.issues = issues; self.finished = YES;
}
@end

static BOOL waitFor(TMCompileProbe *probe, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!probe.finished && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return probe.finished;
}

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { failures++; fprintf(stderr, "  ✗ %s\n", msg); } } while (0)

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmtest_integration"];
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"ch"] withIntermediateDirectories:YES attributes:nil error:nil];

        // 1. 主文件 + 子文件（子文件用 root 魔法注释指回主文件），未定义引用触发一条警告
        NSString *main = @"\\documentclass{article}\n\\begin{document}\nHello \\ref{nope}.\n\\input{ch/part}\n\\end{document}\n";
        NSString *part = @"% !TEX root = ../main.tex\nPart text.\n";
        [main writeToFile:[dir stringByAppendingPathComponent:@"main.tex"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [part writeToFile:[dir stringByAppendingPathComponent:@"ch/part.tex"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

        TMCompiler *compiler = [TMCompiler sharedCompiler];
        TMCompileProbe *probe = [[TMCompileProbe alloc] init];
        compiler.delegate = probe;
        [compiler compileFileAtURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"ch/part.tex"]]];
        CHECK(waitFor(probe, 120), "compile of sub-file timed out");
        CHECK(probe.success, "compile via root magic comment should succeed");
        CHECK([probe.startedURL.lastPathComponent isEqualToString:@"main.tex"], "should compile root main.tex, not part.tex");
        CHECK([probe.pdfURL.lastPathComponent isEqualToString:@"main.pdf"], "pdf should be main.pdf");
        CHECK([[NSFileManager defaultManager] fileExistsAtPath:probe.pdfURL.path], "main.pdf should exist");
        CHECK([TMLogParser countOfKind:TMLogIssueWarning inIssues:probe.issues] >= 1, "undefined \\ref should yield a warning");

        // 中间文件进缓存目录，源文件夹只留 PDF 与 synctex
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *auxDir = [TMCompiler auxiliaryDirectoryForTeXFileURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"main.tex"]]];
        CHECK(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.aux"]], "main.aux must not be written next to the source");
        CHECK(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.log"]], "main.log must not be written next to the source");
        CHECK([fm fileExistsAtPath:[auxDir.path stringByAppendingPathComponent:@"main.aux"]], "main.aux should be in the cache directory");
        CHECK([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.synctex.gz"]], "main.synctex.gz should sit next to main.pdf");

        // 2. 语法错误：应失败并给出行号
        NSString *broken = @"\\documentclass{article}\n\\begin{document}\nok\n\\undefinedmacro\n\\end{document}\n";
        [broken writeToFile:[dir stringByAppendingPathComponent:@"broken.tex"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        TMCompileProbe *probe2 = [[TMCompileProbe alloc] init];
        compiler.delegate = probe2;
        [compiler compileFileAtURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"broken.tex"]]];
        CHECK(waitFor(probe2, 120), "compile of broken file timed out");
        CHECK(!probe2.success, "broken file must fail");
        CHECK(probe2.errorLine == 4, "error line should be 4");
        CHECK([probe2.errorSummary containsString:@"Undefined control sequence"], "summary should mention undefined control sequence");

        // 3. 显式选 xelatex：仍通过 latexmk，且成功
        compiler.engine = TMTeXEngineXeLaTeX;
        TMCompileProbe *probe3 = [[TMCompileProbe alloc] init];
        compiler.delegate = probe3;
        [compiler compileFileAtURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"main.tex"]]];
        CHECK(waitFor(probe3, 120), "xelatex compile timed out");
        CHECK(probe3.success, "xelatex compile should succeed");

        for (NSString *name in @[@"main.tex", @"broken.tex"]) {
            [[NSFileManager defaultManager] removeItemAtURL:[TMCompiler auxiliaryDirectoryForTeXFileURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]] error:nil];
        }
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
        printf("integration: %s (%d failures)\n", failures == 0 ? "OK" : "FAILED", failures);
    }
    return failures == 0 ? 0 : 1;
}
