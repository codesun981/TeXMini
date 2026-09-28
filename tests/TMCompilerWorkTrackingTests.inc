// 复用生命周期测试中的可控真实任务；清理必须等已丢弃任务也退出并读完管道。
@interface TMCompiler (WorkTrackingTestAPI)
- (BOOL)hasActiveCompilationWork;
@end

TM_TEST(test_compiler_discard_keeps_work_active_until_process_finishes) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(hasActiveCompilationWork)]);
    TMLifecycleTask *task = [[TMLifecycleTask alloc] initWithScript:@"printf OLD" delayLaunch:NO delayFinish:YES];
    TMLifecycleProbe *probe = [TMLifecycleProbe new];
    NSURL *url;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[task], probe, &url);
    [compiler compileFileAtURL:url];
    BOOL queuedActive = compiler.hasActiveCompilationWork;
    BOOL waiting = TMLifecycleWait(task.waitEntered);
    [compiler cancelCompilationAndDiscardResults];
    BOOL discardedStillActive = !compiler.isCompiling && compiler.hasActiveCompilationWork;
    dispatch_semaphore_signal(task.finishGate);
    BOOL drained = TMLifecyclePumpUntil(^BOOL { return !compiler.hasActiveCompilationWork; });
    [NSFileManager.defaultManager removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(queuedActive && waiting && discardedStillActive && drained);
    TM_ASSERT_EQ_INT(probe.successes + probe.failures + probe.cancellations, 0);
}

TM_TEST(test_compiler_work_tracks_discarded_launch_failure_and_new_task) {
    TM_ASSERT_TRUE([TMCompiler instancesRespondToSelector:@selector(hasActiveCompilationWork)]);
    TMLifecycleTask *old = [[TMLifecycleTask alloc] initWithScript:@"" delayLaunch:YES delayFinish:NO];
    old.failsToLaunch = YES;
    TMLifecycleTask *next = [[TMLifecycleTask alloc] initWithScript:@"printf NEW" delayLaunch:NO delayFinish:YES];
    TMLifecycleProbe *probe = [TMLifecycleProbe new];
    NSURL *url;
    TMLifecycleCompiler *compiler = TMLifecycleSetup(@[old, next], probe, &url);
    [compiler compileFileAtURL:url];
    BOOL oldStarted = TMLifecycleWait(old.launchEntered);
    [compiler cancelCompilationAndDiscardResults];
    [compiler compileFileAtURL:url];
    BOOL newStarted = TMLifecycleWait(next.waitEntered);
    dispatch_semaphore_signal(old.launchGate);
    BOOL oldDone = TMLifecyclePumpUntil(^BOOL { return old.launchReturned; });
    BOOL newerStillActive = compiler.hasActiveCompilationWork;
    dispatch_semaphore_signal(next.finishGate);
    BOOL drained = TMLifecyclePumpUntil(^BOOL { return !compiler.hasActiveCompilationWork; });
    [NSFileManager.defaultManager removeItemAtURL:url.URLByDeletingLastPathComponent error:nil];
    TM_ASSERT_TRUE(oldStarted && newStarted && oldDone && newerStillActive && drained);
    TM_ASSERT_EQ_INT(probe.successes, 1);
    TM_ASSERT_EQ_INT(probe.failures + probe.cancellations, 0);
}
