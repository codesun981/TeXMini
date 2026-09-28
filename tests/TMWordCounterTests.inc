#import "TMWordCounter.h"

@interface TMWordCounter (Testing)
- (NSUInteger)countWordsInText:(NSString *)text shouldCancel:(BOOL (^)(void))shouldCancel;
@property (nonatomic, readonly) BOOL busy;
@end

@interface TMControlledWordCounter : TMWordCounter
@property (nonatomic, strong) dispatch_semaphore_t started;
@property (nonatomic, strong) dispatch_semaphore_t releaseFirst;
@property (nonatomic, strong) NSMutableArray<NSString *> *executedTexts;
@property NSUInteger activeCount;
@property NSUInteger maximumActiveCount;
@property BOOL observedCancellation;
@end

@implementation TMControlledWordCounter
- (instancetype)init {
    if ((self = [super init])) {
        _started = dispatch_semaphore_create(0);
        _releaseFirst = dispatch_semaphore_create(0);
        _executedTexts = [NSMutableArray array];
    }
    return self;
}
- (NSUInteger)countWordsInText:(NSString *)text shouldCancel:(BOOL (^)(void))shouldCancel {
    BOOL first;
    @synchronized (self) {
        first = self.executedTexts.count == 0;
        [self.executedTexts addObject:text];
        self.activeCount++;
        self.maximumActiveCount = MAX(self.maximumActiveCount, self.activeCount);
    }
    dispatch_semaphore_signal(self.started);
    if (first) dispatch_semaphore_wait(self.releaseFirst, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    BOOL cancelled = shouldCancel();
    NSUInteger count = [super countWordsInText:text shouldCancel:shouldCancel];
    @synchronized (self) {
        self.observedCancellation |= cancelled;
        self.activeCount--;
    }
    return count;
}
@end

static BOOL TMWaitForWordCounter(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!finished() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    }
    return finished();
}

TM_TEST(test_word_counter_keeps_only_latest_pending_and_runs_serially) {
    TMControlledWordCounter *counter = [[TMControlledWordCounter alloc] init];
    __block NSUInteger callbacks = 0, result = 0;
    __block BOOL onMain = NO;
    [counter countText:@"first request" completion:^(NSUInteger count) { callbacks++; }];
    TM_ASSERT_EQ_INT(dispatch_semaphore_wait(counter.started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [counter countText:@"discard intermediate" completion:^(NSUInteger count) { callbacks++; }];
    [counter countText:@"last" completion:^(NSUInteger count) {
        callbacks++;
        result = count;
        onMain = [NSThread isMainThread];
    }];
    dispatch_semaphore_signal(counter.releaseFirst);
    TM_ASSERT_TRUE(TMWaitForWordCounter(^BOOL{ return callbacks > 0; }));
    TM_ASSERT_EQ_INT(callbacks, 1);
    TM_ASSERT_EQ_INT(result, 1);
    TM_ASSERT_TRUE(onMain);
    @synchronized (counter) {
        TM_ASSERT_EQ_INT(counter.maximumActiveCount, 1);
        TM_ASSERT_EQ_INT(counter.executedTexts.count, 2);
        TM_ASSERT_EQ_STR(counter.executedTexts[0], @"first request");
        TM_ASSERT_EQ_STR(counter.executedTexts[1], @"last");
        TM_ASSERT_TRUE(counter.observedCancellation);
    }
}

TM_TEST(test_word_counter_cancel_suppresses_running_and_pending_results) {
    TMControlledWordCounter *counter = [[TMControlledWordCounter alloc] init];
    __block NSUInteger callbacks = 0;
    [counter countText:@"running" completion:^(NSUInteger count) { callbacks++; }];
    TM_ASSERT_EQ_INT(dispatch_semaphore_wait(counter.started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    [counter countText:@"pending" completion:^(NSUInteger count) { callbacks++; }];
    [counter cancel];
    dispatch_semaphore_signal(counter.releaseFirst);
    TM_ASSERT_TRUE(TMWaitForWordCounter(^BOOL{ return !counter.busy; }));
    TM_ASSERT_EQ_INT(callbacks, 0);
    @synchronized (counter) {
        TM_ASSERT_EQ_INT(counter.executedTexts.count, 1);
        TM_ASSERT_TRUE(counter.observedCancellation);
    }
}

TM_TEST(test_word_counter_stops_foundation_enumeration_when_cancelled) {
    TMWordCounter *counter = [[TMWordCounter alloc] init];
    __block NSUInteger checks = 0;
    NSUInteger result = [counter countWordsInText:@"one two three four five" shouldCancel:^BOOL{ return ++checks >= 4; }];
    TM_ASSERT_EQ_INT(result, 2);
    TM_ASSERT_EQ_INT(checks, 4);
}

TM_TEST(test_word_counter_matches_foundation_and_snapshots_mutable_text) {
    TMWordCounter *counter = [[TMWordCounter alloc] init];
    for (NSString *text in @[@"", @"hello world", @"中文分词与 English 混排。👩🏽‍💻 emoji 😀\r\n下一行", @"\\section{Methods}\n$x_i+y_i$ \\cite{paper}"]) {
        __block NSUInteger expected = 0, actual = NSNotFound;
        [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                                options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
                             usingBlock:^(NSString *s, NSRange r, NSRange e, BOOL *stop) { expected++; }];
        NSMutableString *mutableText = [text mutableCopy];
        [counter countText:mutableText completion:^(NSUInteger count) { actual = count; }];
        [mutableText appendString:@" extra extra"];
        TM_ASSERT_TRUE(TMWaitForWordCounter(^BOOL{ return actual != NSNotFound; }));
        TM_ASSERT_EQ_INT(actual, expected);
    }
}
