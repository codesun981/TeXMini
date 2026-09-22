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
- (void)reloadPreservingViewport;
- (void)loadPDFFromURL:(NSURL *)url;
- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex;

@end

NS_ASSUME_NONNULL_END
