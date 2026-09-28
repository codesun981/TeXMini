TM_TEST(test_engine_cache_explicit_preference_snapshot) {
    TMCompiler *compiler = [TMCompiler new];
    compiler.engine = TMTeXEngineLuaLaTeX;
    NSString *reason = nil;
    NSString *content = @"% !TEX program = xelatex\n\\documentclass{article}\n";
    TM_ASSERT_EQ_STR([compiler effectiveEngineNameForContent:content directoryURL:nil preferredEngine:TMTeXEnginePDFLaTeX reason:&reason], @"pdflatex");
    TM_ASSERT_EQ_STR(reason, @"手动选择的引擎");
    TM_ASSERT_EQ_STR([compiler effectiveEngineNameForContent:content directoryURL:nil preferredEngine:TMTeXEngineLatexmk reason:&reason], @"xelatex");
    TM_ASSERT_EQ_STR([compiler effectiveEngineNameForContent:content], @"lualatex");
}

// 只观察真正的依赖解析/遍历；不靠耗时断言判断缓存是否命中。
@interface TMCompiler (TMEngineCacheTesting)
- (NSArray *)engineDependencyFeaturesForText:(NSString *)text;
- (NSArray *)dependencyFeaturesAtPath:(NSString *)path fingerprint:(NSArray *)fingerprint;
- (NSString *)dependencyNeedingXeTeX:(NSArray<NSString *> *)names directoryURL:(NSURL *)directoryURL
                              depth:(NSUInteger)depth fingerprints:(NSMutableDictionary *)fingerprints;
@end

@interface TMEngineTransientReadCompiler : TMCompiler
@property (nonatomic) BOOL failNextRead;
@property (nonatomic) BOOL rewriteAfterNextRead;
@end
@implementation TMEngineTransientReadCompiler
- (NSArray *)dependencyFeaturesAtPath:(NSString *)path fingerprint:(NSArray *)fingerprint {
    if (self.failNextRead) { self.failNextRead = NO; return nil; }
    NSArray *features = [super dependencyFeaturesAtPath:path fingerprint:fingerprint];
    if (self.rewriteAfterNextRead) {
        self.rewriteAfterNextRead = NO;
        [@"\\RequirePackage{ctex}" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return features;
}
@end
@interface TMEngineCountingCompiler : TMCompiler
@property (nonatomic) NSUInteger parseCount;
@property (nonatomic) NSUInteger traversalCount;
@end
@implementation TMEngineCountingCompiler
- (NSArray *)engineDependencyFeaturesForText:(NSString *)text {
    @synchronized (self) { self.parseCount++; }
    return [super engineDependencyFeaturesForText:text];
}
- (NSString *)dependencyNeedingXeTeX:(NSArray<NSString *> *)names directoryURL:(NSURL *)directoryURL
                              depth:(NSUInteger)depth fingerprints:(NSMutableDictionary *)fingerprints {
    @synchronized (self) { self.traversalCount++; }
    return [super dependencyNeedingXeTeX:names directoryURL:directoryURL depth:depth fingerprints:fingerprints];
}
@end

static NSURL *tm_engineRoot(void) {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}
static NSURL *tm_engineWrite(NSURL *root, NSString *name, NSString *text) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

TM_TEST(test_engine_cache_body_edits_reuse_dependency_decision) {
    NSURL *root = tm_engineRoot();
    tm_engineWrite(root, @"article.cls", @"\\LoadClass{book}");
    tm_engineWrite(root, @"book.cls", @"plain class");
    TMEngineCountingCompiler *c = [TMEngineCountingCompiler new];
    NSString *reason = nil;
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\nHello" directoryURL:root reason:&reason], @"pdflatex");
    TM_ASSERT_EQ_INT(c.parseCount, 2);
    NSUInteger traversals = c.traversalCount;
    NSString *firstReason = reason;
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\nA different paragraph" directoryURL:root reason:&reason], @"pdflatex");
    TM_ASSERT_EQ_INT(c.parseCount, 2);
    TM_ASSERT_EQ_INT(c.traversalCount, traversals);
    TM_ASSERT_EQ_STR(reason, firstReason);
    // 注释里的宏包与中文不改变特征。
    [c effectiveEngineNameForContent:@"\\documentclass{article}\n% 中文 \\usepackage{ctex}\nEdited" directoryURL:root reason:nil];
    TM_ASSERT_EQ_INT(c.traversalCount, traversals);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_engine_cache_dependency_creation_deletion_atomic_change) {
    NSURL *root = tm_engineRoot();
    TMEngineCountingCompiler *c = [TMEngineCountingCompiler new];
    NSString *source = @"\\documentclass{article}\n\\usepackage{local}";
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"pdflatex");
    NSURL *file = tm_engineWrite(root, @"local.sty", @"\\RequirePackage{ctex}");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"xelatex");
    NSDate *mtime = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:nil][NSFileModificationDate];
    tm_engineWrite(root, @"local.sty", @"\\RequirePackage{xxxx}"); // 同长度，恢复 mtime
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate:mtime} ofItemAtPath:file.path error:nil];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"pdflatex");
    tm_engineWrite(root, @"article.cls", @"\\RequirePackage{xeCJK}");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"xelatex");
    [[NSFileManager defaultManager] removeItemAtURL:[root URLByAppendingPathComponent:@"article.cls"] error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:file error:nil];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"pdflatex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_engine_cache_dependency_chain_remains_two_levels) {
    NSURL *root = tm_engineRoot();
    tm_engineWrite(root, @"article.cls", @"\\RequirePackage{leveltwo}");
    tm_engineWrite(root, @"leveltwo.sty", @"\\RequirePackage{levelthree}");
    tm_engineWrite(root, @"levelthree.sty", @"\\RequirePackage{ctex}");
    TMEngineCountingCompiler *c = [TMEngineCountingCompiler new];
    NSString *source = @"\\documentclass{article}";
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"pdflatex");
    TM_ASSERT_EQ_INT(c.parseCount, 2);
    tm_engineWrite(root, @"leveltwo.sty", @"\\RequirePackage{xeCJK}");
    NSString *reason = nil;
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:&reason], @"xelatex");
    TM_ASSERT_TRUE([reason containsString:@"article.cls → leveltwo.sty"]);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_engine_cache_features_and_project_roots_do_not_collide) {
    NSURL *first = tm_engineRoot(), *second = tm_engineRoot();
    tm_engineWrite(first, @"article.cls", @"\\RequirePackage{ctex}");
    TMEngineCountingCompiler *c = [TMEngineCountingCompiler new];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}" directoryURL:first reason:nil], @"xelatex");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}" directoryURL:second reason:nil], @"pdflatex");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n中文" directoryURL:second reason:nil], @"xelatex");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n\\usepackage{CJKutf8}\n中文" directoryURL:second reason:nil], @"pdflatex");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n\\setmainfont{Georgia}" directoryURL:second reason:nil], @"xelatex");
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"% !TEX program = pdflatex\n\\documentclass{article}" directoryURL:first reason:nil], @"pdflatex");
    [[NSFileManager defaultManager] removeItemAtURL:first error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:second error:nil];
}

TM_TEST(test_engine_cache_parallel_explicit_preferences) {
    TMCompiler *c = [TMCompiler new];
    __block NSUInteger failures = 0;
    dispatch_apply(30, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
        TMTeXEngine preference = index % 2 ? TMTeXEnginePDFLaTeX : TMTeXEngineLuaLaTeX;
        NSString *expected = index % 2 ? @"pdflatex" : @"lualatex";
        NSString *result = [c effectiveEngineNameForContent:@"\\documentclass{article}\n中文" directoryURL:nil preferredEngine:preference reason:nil];
        if (![result isEqualToString:expected]) @synchronized (c) { failures++; }
    });
    TM_ASSERT_EQ_INT(failures, 0);
}

TM_TEST(test_engine_cache_parallel_automatic_results_remain_correct) {
    NSURL *root = tm_engineRoot();
    tm_engineWrite(root, @"article.cls", @"\\RequirePackage{plain}");
    tm_engineWrite(root, @"plain.sty", @"plain package");
    TMEngineCountingCompiler *c = [TMEngineCountingCompiler new];
    __block NSUInteger failures = 0;
    dispatch_apply(24, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
        NSString *source = [NSString stringWithFormat:@"\\documentclass{article}\nparagraph %zu", index];
        NSString *result = [c effectiveEngineNameForContent:source directoryURL:root preferredEngine:TMTeXEngineLatexmk reason:nil];
        if (![result isEqualToString:@"pdflatex"]) @synchronized (c) { failures++; }
    });
    TM_ASSERT_EQ_INT(failures, 0);
    TM_ASSERT_TRUE(c.parseCount >= 2);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_engine_cache_transient_dependency_read_failure_retries) {
    NSURL *root = tm_engineRoot();
    tm_engineWrite(root, @"article.cls", @"\\RequirePackage{ctex}");
    TMEngineTransientReadCompiler *c = [TMEngineTransientReadCompiler new]; c.failNextRead = YES;
    NSString *source = @"\\documentclass{article}";
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"pdflatex");
    // 文件没有发生任何改变；一次读取失败不得把降级结果永久缓存。
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:nil], @"xelatex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_engine_cache_repeated_path_change_does_not_cache_mixed_graph) {
    NSURL *root = tm_engineRoot();
    tm_engineWrite(root, @"article.cls", @"\\LoadClass{article}");
    TMEngineTransientReadCompiler *c = [TMEngineTransientReadCompiler new]; c.rewriteAfterNextRead = YES;
    NSString *source = @"\\documentclass{article}", *reason = nil;
    [c effectiveEngineNameForContent:source directoryURL:root reason:nil];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:source directoryURL:root reason:&reason], @"xelatex");
    // 第一次遍历途中形成 article→article；第二次必须按新图直接命中 article。
    TM_ASSERT_TRUE(![reason containsString:@"→"]);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}
