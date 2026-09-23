#import <Cocoa/Cocoa.h>
#import "TMDocument.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMMainWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, strong) TMDocument *documentModel;
/// 最近一次编译成功（或打开文档时已存在）的 PDF。使用 `% !TEX root` 时指向主文件的 PDF，
/// 与 documentModel.expectedPDFURL 可能不同；导出 / 显示 / 打印都应以此为准。
@property (nonatomic, strong, readonly, nullable) NSURL *currentPDFURL;

- (instancetype)initWithDocument:(TMDocument *)document;
- (void)newDocumentAction:(nullable id)sender;
/// 打开文件或文件夹：目录 → 设为项目根并打开推断出的主文件；可编辑文本 → 载入编辑器；其他 → 交给系统。
- (void)openDocumentAtURL:(NSURL *)url;
- (void)openFolderAtURL:(NSURL *)folderURL;
- (void)openFileAction:(nullable id)sender;
- (void)openFolderAction:(nullable id)sender;
/// 当前项目根目录（文件浏览器的根）。
@property (nonatomic, strong, readonly, nullable) NSURL *projectRootURL;
- (void)compileCurrentDocument;
- (void)cancelCompilation;
- (BOOL)isCompiling;
/// 弹出存储面板，把 currentPDFURL 复制到用户选定位置。返回 YES 表示已导出。
- (BOOL)exportPDF;
/// 在访达中选中 currentPDFURL。
- (void)revealPDFInFinder;
/// 停止输入 1.5 秒后自动保存并编译；持久化到 NSUserDefaults(TMAutoCompile)。
@property (nonatomic, assign) BOOL autoCompileEnabled;
/// 返回 YES 表示保存成功（或已是最新）。未命名 / 暂存文档会弹出存储面板。
- (BOOL)saveCurrentDocument;
- (BOOL)saveDocumentAs;
- (BOOL)hasUnsavedChanges;
/// 有未保存更改时弹出 保存 / 不保存 / 取消；返回 YES 表示可以继续丢弃当前文档。
- (BOOL)confirmDiscardChangesWithTitle:(NSString *)title;
- (void)forwardSyncToPDF;
/// 弹出输入框询问行号并跳转。
- (void)promptGotoLine;
- (void)toggleLogDrawer;
- (void)toggleOutlineSidebar;
- (void)zoomIn;
- (void)zoomOut;
- (void)pdfNextPage;
- (void)pdfPreviousPage;
- (void)pdfFitWidth;
- (void)pdfActualSize;
- (BOOL)hasPDF;
- (void)printPDF;
- (void)increaseEditorFontSize;
- (void)decreaseEditorFontSize;
- (void)resetEditorFontSize;
/// 从 TMPreferences 重新应用全部偏好（字体、换行、引擎、编译参数、自动编译）。
- (void)applyPreferences;

@end

NS_ASSUME_NONNULL_END
