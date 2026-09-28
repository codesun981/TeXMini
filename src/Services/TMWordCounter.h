#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 全文分词：一个后台任务，以及一个可被新请求替换的待处理快照。
/// 在主线程调用；只有最新且未取消的请求会在主线程回调。
@interface TMWordCounter : NSObject
- (void)countText:(NSString *)text completion:(void (^)(NSUInteger count))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
