#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 监视单个文件被外部程序修改 / 替换 / 删除。原子写入（rename）后会自动重新挂到新 inode 上。
/// 回调在主线程，且做了 0.3s 去抖。
@interface TMFileWatcher : NSObject

- (instancetype)initWithFileURL:(NSURL *)url handler:(void (^)(void))handler;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
