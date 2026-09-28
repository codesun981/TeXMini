#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TMEditorTextView;

/// 字体功能需要主窗口提供的能力。
@protocol TMFontFixHost <NSObject>
- (nullable NSWindow *)window;
- (TMEditorTextView *)editorTextView;
- (nullable NSURL *)currentDocumentFileURL;
- (nullable NSURL *)mainFileURLForCompile;
- (nullable NSURL *)projectRootURL;
- (void)showInfoMessage:(NSString *)message;
- (void)openDocumentAtURL:(NSURL *)url;
- (void)compileCurrentDocument;
@end

/// 编辑 › 文档字体… 面板，以及编译报“找不到字体”时的一键替换。
/// 从主窗口控制器拆出，首次用到时才创建（字体目录也是那时才加载）。
@interface TMFontFixController : NSObject

- (instancetype)initWithHost:(id<TMFontFixHost>)host;
- (void)showDocumentFontsSheet;
/// 编译失败后调用：日志里有缺失字体时提示替换。
- (void)offerFontFixForLog:(NSString *)log;
/// 文档/项目切换或重新编译时，废弃旧请求并收起本控制器的面板；不触发字体目录加载。
- (void)cancelPendingRequests;

@end

NS_ASSUME_NONNULL_END
