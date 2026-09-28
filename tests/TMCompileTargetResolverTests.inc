#import "TMCompileTargetResolver.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMCompileTargetResolver (Testing)
@property (nonatomic, readonly) BOOL busy;
- (nullable TMCompileTargetResult *)resolveDocumentURL:(nullable NSURL *)url content:(NSString *)content
                                            isScratch:(BOOL)scratch preferredEngine:(TMTeXEngine)engine
                                         shouldCancel:(BOOL (^)(void))shouldCancel;
@end

@interface TMControlledTargetResolver : TMCompileTargetResolver
@property (nonatomic, strong) dispatch_semaphore_t started;
@property (nonatomic, strong) dispatch_semaphore_t releaseFirst;
@property (nonatomic, strong) NSMutableArray<NSString *> *executedTexts;
@property NSUInteger activeCount;
@property NSUInteger maximumActiveCount;
@property BOOL observedCancellation;
@property BOOL resolvedOnMainThread;
@end

@implementation TMControlledTargetResolver
- (instancetype)init {
    if ((self = [super init])) {
        _started = dispatch_semaphore_create(0);
        _releaseFirst = dispatch_semaphore_create(0);
        _executedTexts = [NSMutableArray array];
    }
    return self;
}
- (nullable TMCompileTargetResult *)resolveDocumentURL:(nullable NSURL *)url content:(NSString *)content isScratch:(BOOL)scratch
                              preferredEngine:(TMTeXEngine)engine shouldCancel:(BOOL (^)(void))shouldCancel {
    BOOL first;
    @synchronized (self) {
        first = self.executedTexts.count == 0;
        [self.executedTexts addObject:content];
        self.activeCount++;
        self.maximumActiveCount = MAX(self.maximumActiveCount, self.activeCount);
        self.resolvedOnMainThread |= NSThread.isMainThread;
    }
    dispatch_semaphore_signal(self.started);
    if (first) dispatch_semaphore_wait(self.releaseFirst, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    BOOL cancelled = shouldCancel();
    TMCompileTargetResult *result = [super resolveDocumentURL:url content:content isScratch:scratch
                                            preferredEngine:engine shouldCancel:shouldCancel];
    @synchronized (self) {
        self.observedCancellation |= cancelled;
        self.activeCount--;
    }
    return result;
}
@end

static BOOL TMWaitForTargetResolver(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!finished() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    return finished();
}

TM_TEST(test_target_resolver_keeps_latest_snapshot_and_runs_serially) {
    TMControlledTargetResolver *resolver = [[TMControlledTargetResolver alloc] init];
    __block NSUInteger callbacks = 0;
    __block TMCompileTargetResult *lastResult = nil;
    __block BOOL onMain = NO;
    [resolver resolveDocumentURL:nil content:@"first" isScratch:NO preferredEngine:TMTeXEnginePDFLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; }];
    TM_ASSERT_EQ_INT(dispatch_semaphore_wait(resolver.started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [resolver resolveDocumentURL:nil content:@"intermediate" isScratch:NO preferredEngine:TMTeXEngineXeLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; }];
    NSMutableString *latest = [@"\\documentclass{book}" mutableCopy];
    [resolver resolveDocumentURL:nil content:latest isScratch:NO preferredEngine:TMTeXEngineLuaLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; lastResult = r; onMain = NSThread.isMainThread; }];
    [latest setString:@"changed after submission"];
    dispatch_semaphore_signal(resolver.releaseFirst);
    TM_ASSERT_TRUE(TMWaitForTargetResolver(^BOOL{ return lastResult != nil; }));
    TM_ASSERT_EQ_INT(callbacks, 1);
    TM_ASSERT_TRUE(onMain);
    TM_ASSERT_EQ_STR(lastResult.engineName, @"lualatex");
    TM_ASSERT_TRUE(lastResult.usesChapters);
    TM_ASSERT_NIL(lastResult.mainFileURL);
    @synchronized (resolver) {
        TM_ASSERT_EQ_INT(resolver.maximumActiveCount, 1);
        TM_ASSERT_EQ_INT(resolver.executedTexts.count, 2);
        TM_ASSERT_EQ_STR(resolver.executedTexts[1], @"\\documentclass{book}");
        TM_ASSERT_TRUE(resolver.observedCancellation);
        TM_ASSERT_TRUE(!resolver.resolvedOnMainThread);
    }
}

TM_TEST(test_target_resolver_cancel_clears_pending_and_allows_later_requests) {
    TMControlledTargetResolver *resolver = [[TMControlledTargetResolver alloc] init];
    __block NSUInteger callbacks = 0;
    [resolver resolveDocumentURL:nil content:@"running" isScratch:NO preferredEngine:TMTeXEnginePDFLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; }];
    TM_ASSERT_EQ_INT(dispatch_semaphore_wait(resolver.started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [resolver resolveDocumentURL:nil content:@"pending" isScratch:NO preferredEngine:TMTeXEnginePDFLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; }];
    [resolver cancel];
    dispatch_semaphore_signal(resolver.releaseFirst);
    TM_ASSERT_TRUE(TMWaitForTargetResolver(^BOOL{ return !resolver.busy; }));
    TM_ASSERT_EQ_INT(callbacks, 0);
    @synchronized (resolver) { TM_ASSERT_EQ_INT(resolver.executedTexts.count, 1); }
    [resolver resolveDocumentURL:nil content:@"new" isScratch:NO preferredEngine:TMTeXEnginePDFLaTeX
                     completion:^(TMCompileTargetResult *r) { callbacks++; }];
    TM_ASSERT_TRUE(TMWaitForTargetResolver(^BOOL{ return callbacks == 1; }));
}

TM_TEST(test_target_resolver_uses_root_disk_content_and_scratch_snapshot) {
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main = [dir URLByAppendingPathComponent:@"main.tex"];
    NSURL *chapter = [dir URLByAppendingPathComponent:@"chapter.tex"];
    [@"% !TEX program = xelatex\n\\documentclass{book}\n\\input{chapter}" writeToURL:main atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"disk body" writeToURL:chapter atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMCompileTargetResolver *resolver = [[TMCompileTargetResolver alloc] init];
    __block TMCompileTargetResult *result = nil;
    [resolver resolveDocumentURL:chapter content:@"% !TEX root = main.tex\nunsaved body" isScratch:NO preferredEngine:TMTeXEngineLatexmk
                     completion:^(TMCompileTargetResult *r) { result = r; }];
    BOOL finished = TMWaitForTargetResolver(^BOOL{ return result != nil; });
    TMCompileTargetResult *rootResult = result;
    result = nil;
    [resolver resolveDocumentURL:chapter content:@"\\documentclass{article}" isScratch:YES preferredEngine:TMTeXEnginePDFLaTeX
                     completion:^(TMCompileTargetResult *r) { result = r; }];
    BOOL scratchFinished = TMWaitForTargetResolver(^BOOL{ return result != nil; });
    TMCompileTargetResult *scratchResult = result;
    result = nil;
    // 磁盘仍是章节片段；未保存的 documentclass 应让当前文件成为主文件，不能沿用旁边的 main.tex。
    [resolver resolveDocumentURL:chapter content:@"% !TEX program = lualatex\n\\documentclass{article}" isScratch:NO preferredEngine:TMTeXEngineLatexmk
                     completion:^(TMCompileTargetResult *r) { result = r; }];
    BOOL unsavedMainFinished = TMWaitForTargetResolver(^BOOL{ return result != nil; });
    [resolver cancel];
    [fm removeItemAtURL:dir error:nil];
    TM_ASSERT_TRUE(finished && scratchFinished && unsavedMainFinished);
    TM_ASSERT_EQ_STR(rootResult.mainFileURL.path, main.path);
    TM_ASSERT_EQ_STR(rootResult.engineName, @"xelatex");
    TM_ASSERT_TRUE(rootResult.usesChapters);
    TM_ASSERT_TRUE(rootResult.reason.length > 0);
    TM_ASSERT_EQ_INT(rootResult.usesLatexmk, [TMCompiler findExecutableNamed:@"latexmk"] != nil);
    TM_ASSERT_EQ_STR(scratchResult.mainFileURL.path, chapter.path);
    TM_ASSERT_EQ_STR(scratchResult.engineName, @"pdflatex");
    TM_ASSERT_TRUE(!scratchResult.usesChapters);
    TM_ASSERT_EQ_STR(result.mainFileURL.path, chapter.path);
    TM_ASSERT_EQ_STR(result.engineName, @"lualatex");
    TM_ASSERT_TRUE(!result.usesChapters);
}

NS_ASSUME_NONNULL_END
