#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const TMDocumentErrorDomain;
typedef NS_ERROR_ENUM(TMDocumentErrorDomain, TMDocumentError) {
    TMDocumentErrorExternalChange = 1,
    TMDocumentErrorUnknownEncoding,
    TMDocumentErrorUnrepresentableEncoding,
};

@interface TMDocument : NSObject

@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) BOOL isDirty;
/// YES 表示 fileURL 指向临时目录里的暂存文件（用于编译未命名文档），不算用户的正式文件。
@property (nonatomic, assign) BOOL isScratch;
/// 原文件编码；新文档默认 UTF-8。保存保持编码，不能无损表示的字符会报错。
@property (nonatomic, readonly) NSStringEncoding textEncoding;

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
/// 相对于读入 / 成功保存时的磁盘基线，检测替换、修改和删除（不只比较修改时间）。
- (BOOL)hasExternalChanges;
/// 用户明确选择保留本地内容，或应用内重命名完成后，接受当前磁盘状态。
- (void)acknowledgeExternalChanges;
/// 只接受冲突提示所展示的同路径磁盘快照，保留本地正文与编码；之后的新变更仍会被检测到。
- (void)acknowledgeDiskStateFromDocument:(TMDocument *)diskDocument;
/// 删除自身同名的辅助文件（.aux/.log/.bbl/… 见 auxiliaryExtensions），保留 PDF。
- (void)cleanAuxiliaryFiles;
/// 删除 texURL 同名的辅助文件；编译主文件与当前文件不同时应传主文件。
+ (void)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL;
/// 同上；keepBibliography 为 YES 时保留 .bbl（自动清理且 .bbl 无法重新生成时用）。
/// 各章 \include 生成的 .aux 按主 .aux 里的 \@input 列表一起删掉。
+ (void)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL keepingBibliography:(BOOL)keepBibliography;
+ (NSArray<NSString *> *)auxiliaryExtensions;

@end

NS_ASSUME_NONNULL_END
