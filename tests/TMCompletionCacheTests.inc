// 文件缓存与异步补全的回归测试，由 TMTests.m 引入。
@interface TMCountingCompletionProvider : TMCompletionProvider
@property (nonatomic) NSUInteger readCount;
@end
static NSUInteger tmCompletionCommandScans;
@implementation TMCountingCompletionProvider
- (NSString *)readCompletionTextAtURL:(NSURL *)url {
    self.readCount++;
    return [super readCompletionTextAtURL:url];
}
+ (NSArray<NSString *> *)commandsInText:(NSString *)text {
    tmCompletionCommandScans++;
    return [super commandsInText:text];
}
@end

static NSURL *tm_completionRoot(void) {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root;
}
static NSURL *tm_completionWrite(NSURL *root, NSString *name, NSString *text) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}
static TMCompletionContext *tm_completionContext(TMCompletionKind kind, NSString *partial) {
    TMCompletionContext *context = [TMCompletionContext new];
    context.kind = kind;
    context.partial = partial;
    return context;
}

TM_TEST(test_completion_cache_reuses_unchanged_files) {
    NSURL *root = tm_completionRoot();
    NSURL *a = tm_completionWrite(root, @"a.tex", @"\\label{first}");
    tm_completionWrite(root, @"b.tex", @"\\label{other}");
    TMCountingCompletionProvider *p = [TMCountingCompletionProvider new];
    p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_INT(p.readCount, 2);
    [p completionsForContext:ctx currentText:@""];
    [p invalidate];
    [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_INT(p.readCount, 2);
    tm_completionWrite(root, @"a.tex", @"\\label{newer}"); // 等长修改
    [p invalidateFileAtURL:a];
    NSArray *out = [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_INT(p.readCount, 3);
    TM_ASSERT_TRUE([out containsObject:@"newer"] && ![out containsObject:@"first"]);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_completion_cache_fingerprints_atomic_same_size_changes) {
    NSURL *root = tm_completionRoot();
    NSURL *url = tm_completionWrite(root, @"a.tex", @"\\label{alpha}");
    TMCountingCompletionProvider *p = [TMCountingCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    [p completionsForContext:ctx currentText:@""];
    NSDate *date = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil][NSFileModificationDate];
    tm_completionWrite(root, @"a.tex", @"\\label{bravo}");
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:date} ofItemAtPath:url.path error:nil];
    [p invalidate];
    NSArray *out = [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_INT(p.readCount, 2);
    TM_ASSERT_TRUE([out containsObject:@"bravo"] && ![out containsObject:@"alpha"]);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_completion_cache_tracks_create_delete_rename_and_root) {
    NSURL *root = tm_completionRoot(), *other = tm_completionRoot();
    NSURL *old = tm_completionWrite(root, @"a.tex", @"\\label{old}");
    tm_completionWrite(other, @"b.tex", @"\\label{different}");
    TMCountingCompletionProvider *p = [TMCountingCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    [p completionsForContext:ctx currentText:@""];
    NSURL *added = tm_completionWrite(root, @"new.tex", @"\\label{added}");
    [p invalidateFileAtURL:added];
    TM_ASSERT_TRUE([[p completionsForContext:ctx currentText:@""] containsObject:@"added"]);
    TM_ASSERT_EQ_INT(p.readCount, 2);
    [[NSFileManager defaultManager] moveItemAtURL:old toURL:[root URLByAppendingPathComponent:@"renamed.tex"] error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:added error:nil];
    [p invalidate];
    NSArray *out = [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"old");
    TM_ASSERT_EQ_INT(p.readCount, 3);
    p.projectRootURL = other;
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@""] componentsJoinedByString:@","], @"different");
    p.projectRootURL = nil;
    TM_ASSERT_EQ_INT([p completionsForContext:ctx currentText:@""].count, 0);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:other error:nil];
}

TM_TEST(test_completion_current_revision_and_unsaved_overlay) {
    NSURL *root = tm_completionRoot();
    NSURL *file = tm_completionWrite(root, @"main.tex", @"\\label{saved}");
    TMCountingCompletionProvider *p = [TMCountingCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    tmCompletionCommandScans = 0;
    NSArray *out = [p completionsForContext:ctx currentText:@"\\label{draft}" documentKey:file.path revision:1];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"draft");
    NSUInteger scans = tmCompletionCommandScans;
    ctx.partial = @"dr";
    [p completionsForContext:ctx currentText:@"\\label{draft}" documentKey:file.path revision:1];
    TM_ASSERT_EQ_INT(tmCompletionCommandScans, scans);
    ctx.partial = @"";
    out = [p completionsForContext:ctx currentText:@"\\label{fresh}" documentKey:file.path revision:2];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"fresh");
    TM_ASSERT_EQ_INT(tmCompletionCommandScans, scans + 1);
    out = [p completionsForContext:ctx currentText:@"\\label{other}" documentKey:@"untitled-other" revision:2];
    TM_ASSERT_EQ_STR(out.firstObject, @"other");
    TM_ASSERT_TRUE([out containsObject:@"saved"]);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_completion_legacy_text_cache_detects_equal_length_edit) {
    TMCountingCompletionProvider *p = [TMCountingCompletionProvider new];
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    tmCompletionCommandScans = 0;
    [p completionsForContext:ctx currentText:@"\\label{alpha}"];
    NSUInteger scans = tmCompletionCommandScans;
    [p completionsForContext:ctx currentText:[@"\\label{alpha}" mutableCopy]];
    TM_ASSERT_EQ_INT(tmCompletionCommandScans, scans);
    NSArray *out = [p completionsForContext:ctx currentText:@"\\label{bravo}"];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"bravo");
    TM_ASSERT_EQ_INT(tmCompletionCommandScans, scans + 1);
}

TM_TEST(test_completion_unsaved_bibliography_replaces_disk_keys) {
    NSURL *root = tm_completionRoot();
    NSURL *file = tm_completionWrite(root, @"refs.bib", @"@article{saved,}");
    TMCompletionProvider *p = [TMCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindCitation, @"");
    NSArray *out = [p completionsForContext:ctx currentText:@"@article{draft,}" documentKey:file.path revision:1];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"draft");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_completion_cache_keeps_four_kinds_order_and_fallback) {
    NSURL *root = tm_completionRoot();
    tm_completionWrite(root, @"refs.bib", @"@article{figPaper,}\n@book{otherfig,}");
    NSURL *latin = [root URLByAppendingPathComponent:@"latin.tex"];
    [@"café \\label{fig:disk}" writeToURL:latin atomically:YES encoding:NSISOLatin1StringEncoding error:nil];
    TMCompletionProvider *p = [TMCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindCitation, @"fig");
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@""] componentsJoinedByString:@","], @"figPaper,otherfig");
    ctx.kind = TMCompletionKindReference;
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@"\\label{otherfig}\\label{fig:local}"] componentsJoinedByString:@","], @"fig:local,fig:disk,otherfig");
    ctx.kind = TMCompletionKindEnvironment; ctx.partial = @"ali";
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@""] componentsJoinedByString:@","], @"align,align*");
    ctx.kind = TMCompletionKindCommand; ctx.partial = @"\\zz";
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@"\\zzBeta \\zzAlpha \\zz"] componentsJoinedByString:@","], @"\\zzAlpha,\\zzBeta");
    ctx.kind = TMCompletionKindNone;
    TM_ASSERT_EQ_INT([p completionsForContext:ctx currentText:@""].count, 0);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_completion_async_snapshot_and_main_thread_callback) {
    TMCompletionProvider *p = [TMCompletionProvider new];
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"al");
    NSMutableString *text = [@"\\label{alpha}" mutableCopy];
    __block BOOL finished = NO, mainThread = NO;
    __block NSArray *received = nil;
    [p requestCompletionsForContext:ctx currentText:text documentKey:@"draft" revision:1 completion:^(NSArray<NSString *> *items) {
        received = items; mainThread = NSThread.isMainThread; finished = YES;
    }];
    ctx.partial = @"different"; [text setString:@"\\label{changed}"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!finished && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    TM_ASSERT_TRUE(finished && mainThread);
    TM_ASSERT_EQ_STR([received componentsJoinedByString:@","], @"alpha");
}

TM_TEST(test_completion_async_only_latest_request_calls_back) {
    TMCompletionProvider *p = [TMCompletionProvider new];
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    __block NSUInteger callbacks = 0;
    __block NSString *received = nil;
    for (NSUInteger revision = 1; revision <= 20; revision++) {
        NSString *text = [NSString stringWithFormat:@"\\label{item%lu}", (unsigned long)revision];
        [p requestCompletionsForContext:ctx currentText:text documentKey:@"draft" revision:revision completion:^(NSArray<NSString *> *items) {
            callbacks++; received = items.firstObject;
        }];
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!received && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    TM_ASSERT_EQ_STR(received, @"item20");
    TM_ASSERT_EQ_INT(callbacks, 1);
}

TM_TEST(test_completion_root_switch_cancels_old_root_callback) {
    NSURL *oldRoot = tm_completionRoot(), *newRoot = tm_completionRoot();
    tm_completionWrite(oldRoot, @"a.tex", @"\\label{oldRoot}");
    tm_completionWrite(newRoot, @"a.tex", @"\\label{newRoot}");
    TMCompletionProvider *p = [TMCompletionProvider new]; p.projectRootURL = oldRoot;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    __block NSUInteger callbacks = 0;
    [p requestCompletionsForContext:ctx currentText:@"" documentKey:@"draft" revision:1 completion:^(NSArray<NSString *> *items) {
        callbacks++;
    }];
    p.projectRootURL = newRoot;
    // 同步查询也充当队列屏障，确保旧请求若生成回调，已经排到主线程上。
    NSArray *fresh = [p completionsForContext:ctx currentText:@""];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    TM_ASSERT_EQ_INT(callbacks, 0);
    TM_ASSERT_EQ_STR([fresh componentsJoinedByString:@","], @"newRoot");
    [[NSFileManager defaultManager] removeItemAtURL:oldRoot error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:newRoot error:nil];
}

TM_TEST(test_completion_invalidation_cancels_queued_callback) {
    NSURL *root = tm_completionRoot();
    NSURL *file = tm_completionWrite(root, @"a.tex", @"\\label{before}");
    TMCompletionProvider *p = [TMCompletionProvider new]; p.projectRootURL = root;
    TMCompletionContext *ctx = tm_completionContext(TMCompletionKindReference, @"");
    for (NSUInteger round = 0; round < 2; round++) {
        __block NSUInteger callbacks = 0;
        [p requestCompletionsForContext:ctx currentText:@"" documentKey:@"draft" revision:1 completion:^(NSArray<NSString *> *items) {
            callbacks++;
        }];
        [p completionsForContext:ctx currentText:@""]; // 让异步旧结果排队，但还不交付
        tm_completionWrite(root, @"a.tex", @"\\label{after}");
        if (round == 0) [p invalidateFileAtURL:file];
        else [p invalidate];
        NSArray *fresh = [p completionsForContext:ctx currentText:@""];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        TM_ASSERT_EQ_INT(callbacks, 0);
        TM_ASSERT_EQ_STR([fresh componentsJoinedByString:@","], @"after");
    }
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}
