#import <Cocoa/Cocoa.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol TMPDFViewDelegate <NSObject>
@optional
- (void)pdfViewDidRequestInverseSearchAtPoint:(NSPoint)pointOnPage
                                    pageIndex:(NSInteger)pageIndex
                                   pageBounds:(NSRect)pageBounds;
@end

@interface TMPDFView : PDFView

@property (nonatomic, weak) id<TMPDFViewDelegate> syncDelegate;
@property (nonatomic, strong, nullable) NSURL *currentPDFURL;

- (void)setupPDFView;
- (void)loadPDFFromURL:(NSURL *)url;
/// preserve=YES 时保留当前页与滚动位置（用于重新编译后刷新）。
- (void)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve;
- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex;

@end

NS_ASSUME_NONNULL_END
