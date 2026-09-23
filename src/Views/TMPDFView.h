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

@interface TMPDFView : PDFView

@property (nonatomic, weak) id<TMPDFViewDelegate> syncDelegate;
@property (nonatomic, strong, nullable) NSURL *currentPDFURL;
/// 反色显示（深色阅读）：颜色取反再把色相转回来，黑字白纸变白字黑纸而彩色图基本保持原色。
@property (nonatomic, assign) BOOL inverted;

- (void)setupPDFView;
- (void)loadPDFFromURL:(NSURL *)url;
/// preserve=YES 时保留当前页与滚动位置（用于重新编译后刷新）。
- (void)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve;
- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex;

@end

NS_ASSUME_NONNULL_END
