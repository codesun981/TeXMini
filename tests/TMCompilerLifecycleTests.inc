// 可控真实子进程：信号量把启动、完成固定在切换文档前后，不需要 TeX 或 GUI。
@interface TMCompiler (LifecycleTesting)
- (NSTask *)newCompilationTask;
- (void)cancelCompilationAndDiscardResults;
@end

@interface TMLifecycleTask : NSObject
@property (nonatomic, strong) NSTask *task;
@property (nonatomic, strong) dispatch_semaphore_t launchEntered;
@property (nonatomic, strong) dispatch_semaphore_t launchGate;
@property (nonatomic, strong) dispatch_semaphore_t waitEntered;
@property (nonatomic, strong) dispatch_semaphore_t finishGate;
@property BOOL failsToLaunch;
@property BOOL launchReturned;
@property BOOL exitStatusRead;
- (instancetype)initWithScript:(NSString *)script delayLaunch:(BOOL)delayLaunch delayFinish:(BOOL)delayFinish;
@end

@implementation TMLifecycleTask
- (instancetype)initWithScript:(NSString *)script delayLaunch:(BOOL)delayLaunch delayFinish:(BOOL)delayFinish {
    if ((self = [super init])) {
        _task = [NSTask new];
        _task.executableURL = [NSURL fileURLWithPath:@"/bin/sh"];
        _task.arguments = @[@"-c", script];
        _launchEntered = dispatch_semaphore_create(0);
        _launchGate = dispatch_semaphore_create(0);
        if (!delayLaunch) dispatch_semaphore_signal(_launchGate);
        _waitEntered = dispatch_semaphore_create(0);
        _finishGate = dispatch_semaphore_create(0);
        if (!delayFinish) dispatch_semaphore_signal(_finishGate);
    }
    return self;
}
- (id)forwardingTargetForSelector:(SEL)selector { return self.task; }
- (void)setExecutableURL:(NSURL *)url {}
- (void)setArguments:(NSArray *)arguments {}
- (BOOL)launchAndReturnError:(NSError **)error {
    dispatch_semaphore_signal(self.launchEntered);
    dispatch_semaphore_wait(self.launchGate, DISPATCH_TIME_FOREVER);
    BOOL launched;
    if (self.failsToLaunch) {
        if (error) *error = [NSError errorWithDomain:@"TMLifecycleTest" code:1 userInfo:@{NSLocalizedDescriptionKey: @"旧任务启动失败"}];
        launched = NO;
    } else {
        launched = [self.task launchAndReturnError:error];
    }
    self.launchReturned = YES;
    return launched;
}
- (void)waitUntilExit {
    [self.task waitUntilExit];
    dispatch_semaphore_signal(self.waitEntered);
    dispatch_semaphore_wait(self.finishGate, DISPATCH_TIME_FOREVER);
}
- (int)terminationStatus {
    self.exitStatusRead = YES;
    return self.task.terminationStatus;
}
@end

@interface TMLifecycleCompiler : TMCompiler
@property (nonatomic, strong) NSMutableArray<TMLifecycleTask *> *tasks;
@end
@implementation TMLifecycleCompiler
+ (NSString *)findExecutableNamed:(NSString *)name { return @"/bin/sh"; }
- (NSTask *)newCompilationTask {
    TMLifecycleTask *task = self.tasks.firstObject;
    [self.tasks removeObjectAtIndex:0];
    return (NSTask *)(id)task;
}
@end

@interface TMLifecycleProbe : NSObject <TMCompilerDelegate>
@property (nonatomic, strong) NSMutableString *log;
@property NSUInteger successes;
@property NSUInteger failures;
@property NSUInteger cancellations;
@end
@implementation TMLifecycleProbe
- (instancetype)init { if ((self = [super init])) _log = [NSMutableString string]; return self; }
- (void)compilerDidOutputLog:(NSString *)text { [self.log appendString:text]; }
- (void)compilerDidFinishSuccess:(double)duration pdfURL:(NSURL *)url issues:(NSArray *)issues { self.successes++; }
- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)line fullLog:(NSString *)log issues:(NSArray *)issues { self.failures++; }
- (void)compilerDidCancel { self.cancellations++; }
@end

static BOOL TMLifecycleWait(dispatch_semaphore_t semaphore) {
    return dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0;
}

static BOOL TMLifecyclePumpUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    // 退出状态/启动返回标记在 delegate block 入队前设置，继续排空该批主队列回调。
    NSDate *drain = [NSDate dateWithTimeIntervalSinceNow:0.05];
    while (drain.timeIntervalSinceNow > 0) {
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:drain];
    }
    return condition();
}

static TMLifecycleCompiler *TMLifecycleSetup(NSArray<TMLifecycleTask *> *tasks, TMLifecycleProbe *probe, NSURL **fileURL) {
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    *fileURL = [directory URLByAppendingPathComponent:@"main.tex"];
    [@"\\documentclass{article}" writeToURL:*fileURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"test PDF" writeToURL:[directory URLByAppendingPathComponent:@"main.pdf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMLifecycleCompiler *compiler = [TMLifecycleCompiler new];
    compiler.engine = TMTeXEnginePDFLaTeX;
    compiler.auxFilesBesideSource = YES;
    compiler.delegate = probe;
    compiler.tasks = [tasks mutableCopy];
    return compiler;
}

TM_TEST(test_compiler_discard_suppresses_queued_log_and_completion) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(cancelCompilationAndDiscardResults)]);
    TMLifecycleTask *old = [[TMLifecycleTask alloc] initWithScript:@"printf OLD; exit 1" delayLaunch:NO delayFinish:YES];
    TMLifecycleProbe *probe = [TMLifecycleProbe new];
    NSURL *url;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[old], probe, &url);
    [compiler compileFileAtURL:url];
    BOOL logQueued = TMLifecycleWait(old.waitEntered);
    [compiler cancelCompilationAndDiscardResults];
    BOOL immediatelyIdle = !compiler.isCompiling;
    dispatch_semaphore_signal(old.finishGate);
    BOOL completed = TMLifecyclePumpUntil(^BOOL { return old.exitStatusRead; });
    [[NSFileManager defaultManager] removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(logQueued && completed && immediatelyIdle);
    TM_ASSERT_EQ_STR(probe.log, @"");
    TM_ASSERT_EQ_INT(probe.failures + probe.successes + probe.cancellations, 0);
}

TM_TEST(test_compiler_replacement_ignores_old_finish_and_keeps_new_results) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(cancelCompilationAndDiscardResults)]);
    TMLifecycleTask *old = [[TMLifecycleTask alloc] initWithScript:@"printf OLD; exit 1" delayLaunch:NO delayFinish:YES];
    TMLifecycleTask *next = [[TMLifecycleTask alloc] initWithScript:@"printf NEW" delayLaunch:NO delayFinish:YES];
    TMLifecycleProbe *probe = [TMLifecycleProbe new];
    NSURL *url;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[old, next], probe, &url);
    [compiler compileFileAtURL:url];
    BOOL oldReady = TMLifecycleWait(old.waitEntered);
    [compiler compileFileAtURL:url];
    BOOL nextReady = TMLifecycleWait(next.waitEntered);
    dispatch_semaphore_signal(old.finishGate);
    BOOL oldDone = TMLifecyclePumpUntil(^BOOL { return old.exitStatusRead; });
    BOOL newStillCompiling = compiler.isCompiling;
    dispatch_semaphore_signal(next.finishGate);
    BOOL nextDone = TMLifecyclePumpUntil(^BOOL { return probe.successes > 0; });
    [[NSFileManager defaultManager] removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(oldReady && nextReady && oldDone && nextDone && newStillCompiling);
    TM_ASSERT_EQ_STR(probe.log, @"NEW");
    TM_ASSERT_EQ_INT(probe.successes, 1);
    TM_ASSERT_EQ_INT(probe.failures + probe.cancellations, 0);
}

TM_TEST(test_compiler_discarded_launch_failure_cannot_clear_new_task) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(cancelCompilationAndDiscardResults)]);
    TMLifecycleTask *old = [[TMLifecycleTask alloc] initWithScript:@"" delayLaunch:YES delayFinish:NO];
    old.failsToLaunch = YES;
    TMLifecycleTask *next = [[TMLifecycleTask alloc] initWithScript:@"printf NEW" delayLaunch:NO delayFinish:YES];
    TMLifecycleProbe *probe = [TMLifecycleProbe new];
    NSURL *url;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[old, next], probe, &url);
    [compiler compileFileAtURL:url];
    BOOL oldReady = TMLifecycleWait(old.launchEntered);
    [compiler cancelCompilationAndDiscardResults];
    [compiler compileFileAtURL:url];
    BOOL nextReady = TMLifecycleWait(next.waitEntered);
    dispatch_semaphore_signal(old.launchGate);
    BOOL oldDone = TMLifecyclePumpUntil(^BOOL { return old.launchReturned; });
    BOOL newStillCompiling = compiler.isCompiling;
    dispatch_semaphore_signal(next.finishGate);
    BOOL nextDone = TMLifecyclePumpUntil(^BOOL { return probe.successes > 0; });
    [[NSFileManager defaultManager] removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(oldReady && nextReady && oldDone && nextDone && newStillCompiling);
    TM_ASSERT_EQ_STR(probe.log, @"NEW");
    TM_ASSERT_EQ_INT(probe.successes, 1);
    TM_ASSERT_EQ_INT(probe.failures + probe.cancellations, 0);
}

TM_TEST(test_compiler_cancel_before_launch_terminates_process_and_preserves_cancel_semantics) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(cancelCompilationAndDiscardResults)]);
    for (NSNumber *discardValue in @[@YES, @NO]) {
        BOOL discard = discardValue.boolValue;
        TMLifecycleTask *task = [[TMLifecycleTask alloc] initWithScript:@"exec /bin/sleep 30" delayLaunch:YES delayFinish:NO];
        TMLifecycleProbe *probe = [TMLifecycleProbe new];
        NSURL *url;
        TMLifecycleCompiler *compiler = TMLifecycleSetup(@[task], probe, &url);
        [compiler compileFileAtURL:url];
        BOOL launchEntered = TMLifecycleWait(task.launchEntered);
        if (discard) [compiler cancelCompilationAndDiscardResults];
        else [compiler cancelCompilation];
        dispatch_semaphore_signal(task.launchGate);
        BOOL ended = TMLifecyclePumpUntil(^BOOL { return task.exitStatusRead; });
        if (task.task.running) [task.task terminate];
        [[NSFileManager defaultManager] removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
        TM_ASSERT_TRUE(launchEntered && ended);
        TM_ASSERT_TRUE(!compiler.isCompiling);
        TM_ASSERT_EQ_INT(probe.failures + probe.successes, 0);
        TM_ASSERT_EQ_INT(probe.cancellations, discard ? 0 : 1);
    }
}
