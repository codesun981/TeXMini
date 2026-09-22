#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TMFileBrowserView;

@protocol TMFileBrowserViewDelegate <NSObject>
@optional
/// 用户单击了一个文件（目录的展开/折叠不会触发）。
- (void)fileBrowserView:(TMFileBrowserView *)browser didSelectFileURL:(NSURL *)url;
@end

/// 侧边栏“文件”页：以项目根目录为根的轻量文件树。
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
