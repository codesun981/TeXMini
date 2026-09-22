#import <Cocoa/Cocoa.h>
#import "TMDocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMMainWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong) TMDocument *documentModel;

- (instancetype)initWithDocument:(TMDocument *)document;
- (void)newDocumentAction:(nullable id)sender;
- (void)openDocumentAtURL:(NSURL *)url;
- (void)compileCurrentDocument;
/// 返回 YES 表示保存成功（或已是最新）。未命名 / 暂存文档会弹出存储面板。
- (BOOL)saveCurrentDocument;
- (BOOL)saveDocumentAs;
- (BOOL)hasUnsavedChanges;
/// 有未保存更改时弹出 保存 / 不保存 / 取消；返回 YES 表示可以继续丢弃当前文档。
- (BOOL)confirmDiscardChangesWithTitle:(NSString *)title;
- (void)forwardSyncToPDF;
- (void)toggleLogDrawer;
- (void)toggleOutlineSidebar;
- (void)zoomIn;
- (void)zoomOut;

@end

NS_ASSUME_NONNULL_END
