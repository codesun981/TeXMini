#import "TMFileWatcher.h"
#import <fcntl.h>
#import <unistd.h>

@interface TMFileWatcher ()
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) void (^handler)(void);
@property (nonatomic, strong, nullable) dispatch_source_t source;
@property (nonatomic, assign) int fd;
@property (nonatomic, assign) BOOL pending;
@property (nonatomic, assign) BOOL stopped;
@end

@implementation TMFileWatcher

- (instancetype)initWithFileURL:(NSURL *)url handler:(void (^)(void))handler {
    self = [super init];
    if (self) {
        _url = url;
        _handler = [handler copy];
        _fd = -1;
        [self arm];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)arm {
    if (self.stopped) return;
    int fd = open(self.url.path.fileSystemRepresentation, O_EVTONLY);
    if (fd < 0) {
        // 文件暂时不存在（原子写入中间态）：稍后重试
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf arm];
        });
        return;
    }
    self.fd = fd;
    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd,
                                                   DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_EXTEND,
                                                   dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(src, ^{
        typeof(self) self = weakSelf;
        if (!self) return;
        unsigned long flags = dispatch_source_get_data(src);
        if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) {
            // 文件被替换：丢掉旧 fd，重新挂到新文件上
            [self disarm];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf arm];
            });
        }
        [self fireDebounced];
    });
    dispatch_source_set_cancel_handler(src, ^{
        close(fd);
    });
    self.source = src;
    dispatch_resume(src);
}

- (void)disarm {
    if (self.source) {
        dispatch_source_cancel(self.source); // cancel handler 会 close(fd)
        self.source = nil;
        self.fd = -1;
    }
}

- (void)fireDebounced {
    if (self.pending) return;
    self.pending = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (!self || self.stopped) return;
        self.pending = NO;
        if (self.handler) self.handler();
    });
}

- (void)stop {
    self.stopped = YES;
    [self disarm];
}

@end
