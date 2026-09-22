#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMDocument : NSObject

@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) BOOL isDirty;
/// YES 表示 fileURL 指向临时目录里的暂存文件（用于编译未命名文档），不算用户的正式文件。
@property (nonatomic, assign) BOOL isScratch;

@property (nonatomic, readonly, nullable) NSURL *expectedPDFURL;
@property (nonatomic, readonly, nullable) NSURL *expectedSyncTeXURL;
/// 用于窗口标题：未命名或暂存文档返回 "未命名文档.tex"。
@property (nonatomic, readonly) NSString *displayName;

+ (instancetype)documentWithDefaultTemplate;
+ (instancetype)documentWithChineseTemplate;
+ (instancetype)documentWithBlankTemplate;
+ (nullable instancetype)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error;

/// 正式保存：设置 fileURL，清除 isDirty 与 isScratch。
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
/// 暂存保存：写入临时文件以便编译，保留 isDirty，标记 isScratch。
- (BOOL)saveScratchToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveCurrentFileWithError:(NSError **)error;
- (void)cleanAuxiliaryFiles;

@end

NS_ASSUME_NONNULL_END
