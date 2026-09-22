#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 最近打开的文件列表，存于 NSUserDefaults（键 TMRecentFiles），最新在前，最多 10 条。
@interface TMRecentFiles : NSObject

+ (NSArray<NSURL *> *)recentFileURLs;
+ (void)noteFileURL:(NSURL *)url;
+ (void)removeFileURL:(NSURL *)url;
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
