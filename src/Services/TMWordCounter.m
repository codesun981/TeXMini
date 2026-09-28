#import "TMWordCounter.h"

@interface TMWordCounter ()
// 原子属性仅用于 worker 的取消检查；其余调度状态只在主线程访问。
@property (atomic) NSUInteger requestID;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy, nullable) NSString *pendingText;
@property (nonatomic, copy, nullable) void (^pendingCompletion)(NSUInteger);
@end

@implementation TMWordCounter

- (instancetype)init {
    if ((self = [super init])) {
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        _workerQueue = dispatch_queue_create("com.texmini.word-count", attributes);
    }
    return self;
}

- (void)countText:(NSString *)text completion:(void (^)(NSUInteger))completion {
    NSAssert([NSThread isMainThread], @"字数统计请求必须在主线程提交");
    self.requestID++;
    self.pendingText = text;
    self.pendingCompletion = completion;
    [self startPendingRequest];
}

- (void)cancel {
    NSAssert([NSThread isMainThread], @"字数统计取消必须在主线程调用");
    self.requestID++;
    self.pendingText = nil;
    self.pendingCompletion = nil;
}

- (void)startPendingRequest {
    if (self.busy || !self.pendingText) return;
    NSString *text = self.pendingText;
    void (^completion)(NSUInteger) = self.pendingCompletion;
    NSUInteger requestID = self.requestID;
    self.pendingText = nil;
    self.pendingCompletion = nil;
    self.busy = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.workerQueue, ^{
        @autoreleasepool {
            typeof(self) self = weakSelf;
            if (!self) return;
            NSUInteger count = [self countWordsInText:text shouldCancel:^BOOL{
                return weakSelf.requestID != requestID;
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                if (self.requestID == requestID && completion) completion(count);
                [self startPendingRequest];
            });
        }
    });
}

/// 保留 Foundation 的完整文本分词边界；可在测试中覆写以控制 worker 时序。
- (NSUInteger)countWordsInText:(NSString *)text shouldCancel:(BOOL (^)(void))shouldCancel {
    if (shouldCancel()) return 0;
    __block NSUInteger count = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                            options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
                         usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
        if (shouldCancel()) {
            *stop = YES;
            return;
        }
        count++;
    }];
    return count;
}

@end
