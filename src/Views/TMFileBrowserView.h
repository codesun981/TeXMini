#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TMFileBrowserView;

@protocol TMFileBrowserViewDelegate <NSObject>
@optional
/// 用户单击了一个文件（目录的展开/折叠不会触发）。
- (void)fileBrowserView:(TMFileBrowserView *)browser didSelectFileURL:(NSURL *)url;
/// 右键「新建」创建了一个文件；控制器一般直接打开它。
- (void)fileBrowserView:(TMFileBrowserView *)browser didCreateFileURL:(NSURL *)url;
/// 右键重命名 / 移动了文件或目录；正在编辑的文件若受影响，控制器需更新自己的路径。
- (void)fileBrowserView:(TMFileBrowserView *)browser didRenameItemAtURL:(NSURL *)oldURL toURL:(NSURL *)newURL;
/// 右键把文件或目录移到了废纸篓。
- (void)fileBrowserView:(TMFileBrowserView *)browser didTrashItemAtURL:(NSURL *)url;
@end

/// 侧边栏“文件”页：以项目根目录为根的轻量文件树。右键可新建 / 重命名 / 显示 / 移到废纸篓。
@interface TMFileBrowserView : NSView

@property (nonatomic, weak, nullable) id<TMFileBrowserViewDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) NSURL *rootDirectoryURL;

/// 设置根目录并重新扫描；传 nil 显示空态。
- (void)setRootDirectoryURL:(nullable NSURL *)url;
/// 重新扫描磁盘（保存 / 编译后有新文件时调用）。保留展开状态与选中项。
- (void)reload;
/// 高亮当前正在编辑的文件（不触发回调）。
- (void)selectFileURL:(nullable NSURL *)url;

@end

NS_ASSUME_NONNULL_END
