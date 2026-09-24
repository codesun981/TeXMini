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

/// 清空文件与文件夹两个列表（连同上次会话）。
+ (void)clear;

#pragma mark - 上次会话（启动时恢复）

/// 记下当前会话：项目文件夹、正在编辑的文件（都可为 nil）与光标位置。键 TMSessionFolder / TMSessionFile / TMSessionSelection。
+ (void)noteSessionFolderURL:(nullable NSURL *)folder fileURL:(nullable NSURL *)file selection:(NSUInteger)selection;
/// 上次会话的文件夹 / 文件；已不在磁盘上（或类型不对）时返回 nil。
+ (nullable NSURL *)sessionFolderURL;
+ (nullable NSURL *)sessionFileURL;
+ (NSUInteger)sessionSelection;

@end

NS_ASSUME_NONNULL_END
