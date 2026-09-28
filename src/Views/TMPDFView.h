#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TMPDFViewDelegate <NSObject>
@optional
- (void)pdfViewDidRequestInverseSearchAtPoint:(NSPoint)pointOnPage
                                    pageIndex:(NSInteger)pageIndex
                                   pageBounds:(NSRect)pageBounds;
/// PDF 有焦点时用户按了 ⌘F（或菜单 查找…）。
- (void)pdfViewDidRequestFindInterface;
/// PDF 有焦点时用户按了 ⌘G / ⇧⌘G。
- (void)pdfViewDidRequestFindNext:(BOOL)forward;
@end

typedef NS_ENUM(NSInteger, TMPDFFitMode) {
    TMPDFFitPage = 0,   // 整页可见（默认），窗口大小变化时跟着重新适配
    TMPDFFitWidth,      // 适合宽度（PDFKit 的 autoScales）
    TMPDFFitManual      // 用户手动缩放过：保持当前比例
};

@interface TMPDFView : PDFView

@property (nonatomic, weak) id<TMPDFViewDelegate> syncDelegate;
@property (nonatomic, strong, nullable) NSURL *currentPDFURL;
/// 反色显示（深色阅读）：颜色取反再把色相转回来，黑字白纸变白字黑纸而彩色图基本保持原色。
@property (nonatomic, assign) BOOL inverted;
/// 缩放方式。放大 / 缩小 / 捏合会自动切成 Manual。
@property (nonatomic, assign) TMPDFFitMode fitMode;

- (void)setupPDFView;
/// 加载成功返回 YES；失败时清空旧 PDF 并返回 NO。
- (BOOL)loadPDFFromURL:(NSURL *)url;
/// preserve=YES 时为同一 PDF 保留当前页与滚动位置（用于重新编译后刷新）。
- (BOOL)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve;
/// 清空文档、选区和高亮，同时使旧文档尚未执行的界面更新失效。
- (void)clearPDF;
- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex;

@end

NS_ASSUME_NONNULL_END
