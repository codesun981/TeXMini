#import "TMCompileTargetResolver.h"
@interface TMEncodingCompileProbe : TMLifecycleProbe
@property NSURL *startedURL;
@property NSString *engineName;
@end
@implementation TMEncodingCompileProbe
- (void)compilerDidStartCompilingDocument:(NSURL *)url engineName:(NSString *)engineName useLatexmk:(BOOL)usesLatexmk {
    self.startedURL = url;
    self.engineName = engineName;
}
@end

TM_TEST(test_compiler_decodes_declared_gbk_root_and_latin1_engine) {
    TMLifecycleTask *task = [[TMLifecycleTask alloc] initWithScript:@"printf OK" delayLaunch:NO delayFinish:NO];
    TMEncodingCompileProbe *probe = [TMEncodingCompileProbe new];
    NSURL *main;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[task], probe, &main);
    compiler.engine = TMTeXEngineLatexmk;
    NSString *mainText = @"% !TEX encoding = ISO-8859-1\n% !TEX program = lualatex\n\\documentclass{article}\n% café\n";
    [[mainText dataUsingEncoding:NSISOLatin1StringEncoding] writeToURL:main atomically:YES];
    NSURL *chapter = [main.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"chapter.tex"];
    NSStringEncoding gbk = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    [[@"% !TEX encoding = GBK\n% !TEX root = main.tex\n% 中文\n" dataUsingEncoding:gbk] writeToURL:chapter atomically:YES];
    [compiler compileFileAtURL:chapter];
    BOOL done = TMLifecyclePumpUntil(^BOOL { return probe.successes + probe.failures > 0; });
    [NSFileManager.defaultManager removeItemAtURL:main.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(done);
    TM_ASSERT_EQ_STR(probe.startedURL.path, main.path);
    TM_ASSERT_EQ_STR(probe.engineName, @"lualatex");
    TM_ASSERT_EQ_INT(probe.successes, 1);
}

TM_TEST(test_project_and_target_resolver_decode_declared_encoding) {
    NSURL *root = tm_resolutionProject();
    NSURL *chapter = tm_resolutionWrite(root, @"chapters/chapter.tex", @"chapter");
    NSURL *main = [root URLByAppendingPathComponent:@"main.tex"];
    NSString *mainText = @"% !TEX encoding = ISO-8859-1\n% !TEX program = lualatex\n\\documentclass{article}\n\\input{chapters/chapter}\n% café\n";
    [[mainText dataUsingEncoding:NSISOLatin1StringEncoding] writeToURL:main atomically:YES];
    NSURL *guessed = [TMProject guessMainFileInDirectory:root];
    NSURL *inferred = [TMProject mainFileURLForDocumentURL:chapter content:@"chapter"];
    TMCompileTargetResolver *resolver = [TMCompileTargetResolver new];
    __block TMCompileTargetResult *resolved;
    [resolver resolveDocumentURL:chapter content:@"% !TEX root = ../main.tex\nchapter" isScratch:NO preferredEngine:TMTeXEngineLatexmk
                        completion:^(TMCompileTargetResult *result) { resolved = result; }];
    BOOL done = TMLifecyclePumpUntil(^BOOL { return resolved != nil; });
    NSString *bibText = @"% !TEX encoding = ISO-8859-1\n\\bibliography{refs}\n% café\n";
    [[bibText dataUsingEncoding:NSISOLatin1StringEncoding] writeToURL:main atomically:YES];
    tm_resolutionWrite(root, @"refs.bib", @"@article{a,}");
    BOOL bibliographyFound = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    TM_ASSERT_EQ_STR(guessed.URLByResolvingSymlinksInPath.path, main.URLByResolvingSymlinksInPath.path);
    TM_ASSERT_EQ_STR(inferred.URLByResolvingSymlinksInPath.path, main.URLByResolvingSymlinksInPath.path);
    TM_ASSERT_TRUE(done && bibliographyFound);
    TM_ASSERT_EQ_STR(resolved.engineName, @"lualatex");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
