#import <Foundation/Foundation.h>
@class TMCompilerOutputPaths;

NS_ASSUME_NONNULL_BEGIN
/// 按明确的产物名清理；调用方在后台执行，并保证没有编译任务同时写入这些目录。
@interface TMAuxiliaryCleaner : NSObject
+ (BOOL)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL
                           outputPaths:(TMCompilerOutputPaths *)paths
           legacyAuxiliaryDirectoryURL:(nullable NSURL *)legacyDirectory
                   keepingBibliography:(BOOL)keepBibliography;
@end
NS_ASSUME_NONNULL_END
