#import "TMDocument.h"
#import "TMCompileTargetResolver.h"
#import "TMProject.h"
#import "TMFormatActions.h"

@interface TMCompileTargetResult ()
@property (nonatomic, strong, readwrite, nullable) NSURL *mainFileURL;
@property (nonatomic, copy, readwrite) NSString *engineName;
@property (nonatomic, copy, readwrite) NSString *reason;
@property (nonatomic, readwrite) BOOL usesChapters;
@property (nonatomic, readwrite) BOOL usesLatexmk;
@end
@implementation TMCompileTargetResult
@end

@interface TMCompileTargetResolver ()
@property (atomic) NSUInteger requestID;
@property (nonatomic, strong) dispatch_queue_t workerQueue;
@property (nonatomic) BOOL busy;
@property (nonatomic, copy, nullable) dispatch_block_t pendingWork;
@end

@implementation TMCompileTargetResolver

- (instancetype)init {
    if ((self = [super init])) {
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
        _workerQueue = dispatch_queue_create("com.texmini.compile-target", attr);
    }
    return self;
}

- (void)resolveDocumentURL:(NSURL *)documentURL content:(NSString *)content
                 isScratch:(BOOL)isScratch preferredEngine:(TMTeXEngine)preferredEngine
                completion:(void (^)(TMCompileTargetResult *))completion {
    NSAssert(NSThread.isMainThread, @"编译目标请求必须在主线程提交");
    NSUInteger requestID = ++self.requestID;
    NSString *snapshot = [content copy];
    NSURL *url = [documentURL copy];
    __weak typeof(self) weakSelf = self;
    self.pendingWork = ^{
        @autoreleasepool {
            typeof(self) self = weakSelf;
            if (!self) return;
            TMCompileTargetResult *result = [self resolveDocumentURL:url content:snapshot isScratch:isScratch
                                                    preferredEngine:preferredEngine shouldCancel:^BOOL{
                return weakSelf.requestID != requestID;
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                if (self.requestID == requestID && result) completion(result);
                [self startPendingRequest];
            });
        }
    };
    [self startPendingRequest];
}

- (void)cancel {
    NSAssert(NSThread.isMainThread, @"编译目标取消必须在主线程调用");
    self.requestID++;
    self.pendingWork = nil;
}

- (void)startPendingRequest {
    if (self.busy || !self.pendingWork) return;
    dispatch_block_t work = self.pendingWork;
    self.pendingWork = nil;
    self.busy = YES;
    dispatch_async(self.workerQueue, work);
}

/// 每个耗时阶段之间检查取消；无论是否取消，调度层都会清理 busy 并处理最新请求。
- (nullable TMCompileTargetResult *)resolveDocumentURL:(nullable NSURL *)url content:(NSString *)content
                                            isScratch:(BOOL)scratch preferredEngine:(TMTeXEngine)engine
                                         shouldCancel:(BOOL (^)(void))shouldCancel {
    if (shouldCancel()) return nil;
    NSURL *main = url;
    if (url && !scratch) main = [TMProject mainFileURLForDocumentURL:url content:content] ?: url;
    if (shouldCancel()) return nil;
    BOOL editingMain = !main || [main.URLByStandardizingPath.path isEqualToString:url.URLByStandardizingPath.path];
    NSString *mainContent = editingMain ? content : ([TMDocument documentWithContentsOfURL:main error:nil].content ?: @"");
    if (shouldCancel()) return nil;
    BOOL usesChapters = [TMFormatActions usesChaptersForMainContent:mainContent currentContent:content];
    if (shouldCancel()) return nil;
    NSString *reason = nil;
    NSString *engineName = [[TMCompiler sharedCompiler] effectiveEngineNameForContent:mainContent
                                                                        directoryURL:main.URLByDeletingLastPathComponent
                                                                     preferredEngine:engine reason:&reason];
    if (shouldCancel()) return nil;
    BOOL usesLatexmk = [TMCompiler findExecutableNamed:@"latexmk"] != nil;
    if (shouldCancel()) return nil;
    TMCompileTargetResult *result = [[TMCompileTargetResult alloc] init];
    result.mainFileURL = main;
    result.engineName = engineName;
    result.reason = reason ?: @"";
    result.usesChapters = usesChapters;
    result.usesLatexmk = usesLatexmk;
    return result;
}

@end
