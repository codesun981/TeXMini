#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 最近打开的文件与项目文件夹，存于 NSUserDefaults（键 TMRecentFiles / TMRecentFolders），最新在前，各最多 10 条。
@interface TMRecentFiles : NSObject

+ (NSArray<NSURL *> *)recentFileURLs;
+ (void)noteFileURL:(NSURL *)url;
+ (void)removeFileURL:(NSURL *)url;

+ (NSArray<NSURL *> *)recentFolderURLs;
+ (void)noteFolderURL:(NSURL *)url;
+ (void)removeFolderURL:(NSURL *)url;

/// 清空文件与文件夹两个列表。
+ (void)clear;

@end

NS_ASSUME_NONNULL_END
