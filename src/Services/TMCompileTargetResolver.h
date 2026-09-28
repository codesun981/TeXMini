#import <Foundation/Foundation.h>
#import "TMCompiler.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMCompileTargetResult : NSObject
@property (nonatomic, strong, readonly, nullable) NSURL *mainFileURL;
@property (nonatomic, copy, readonly) NSString *engineName;
@property (nonatomic, copy, readonly) NSString *reason;
@property (nonatomic, readonly) BOOL usesChapters;
@property (nonatomic, readonly) BOOL usesLatexmk;
@end

/// 主线程提交和回调；后台至多处理一个请求，只保留最新待处理快照。
@interface TMCompileTargetResolver : NSObject
- (void)resolveDocumentURL:(nullable NSURL *)documentURL content:(NSString *)content
                 isScratch:(BOOL)isScratch preferredEngine:(TMTeXEngine)preferredEngine
                completion:(void (^)(TMCompileTargetResult *result))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
