#import "TMPDFView.h"

@interface TMHighlightOverlayView : NSView
@end

@implementation TMHighlightOverlayView
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:3.0 yRadius:3.0];
    [[[NSColor systemYellowColor] colorWithAlphaComponent:0.35] setFill];
    [path fill];
    [[[NSColor systemOrangeColor] colorWithAlphaComponent:0.8] setStroke];
    path.lineWidth = 1.5;
    [path stroke];
}
@end

@implementation TMPDFView {
    TMHighlightOverlayView *_currentOverlay;
}

- (void)setupPDFView {
    self.displayMode = kPDFDisplaySinglePageContinuous;
    self.displaysPageBreaks = YES;
    self.autoScales = YES;
    self.backgroundColor = [NSColor windowBackgroundColor];
}

- (void)loadPDFFromURL:(NSURL *)url {
    [self loadPDFFromURL:url preservingViewport:NO];
}

- (void)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve {
    PDFDocument *newDoc = [[PDFDocument alloc] initWithURL:url];
    if (!newDoc) return;

    self.currentPDFURL = url;

    if (!preserve || !self.document) {
        self.document = newDoc;
        return;
    }

    // 记录旧视口：当前页索引 + 滚动偏移，必须在替换 document 之前取。
    PDFPage *currentPage = self.currentPage;
    NSInteger pageIndex = currentPage ? [self.document indexForPage:currentPage] : 0;
    NSScrollView *scrollView = self.enclosingScrollView;
    NSPoint scrollPoint = scrollView ? scrollView.contentView.bounds.origin : NSZeroPoint;
    CGFloat scale = self.scaleFactor;
    BOOL wasAutoScaling = self.autoScales;

    self.document = newDoc;

    void (^restore)(void) = ^{
        if (!wasAutoScaling) {
            self.autoScales = NO;
            self.scaleFactor = scale;
        }
        if (pageIndex < (NSInteger)self.document.pageCount) {
            [self goToPage:[self.document pageAtIndex:pageIndex]];
        }
        if (scrollView) {
            [scrollView.contentView scrollPoint:scrollPoint];
            [scrollView reflectScrolledClipView:scrollView.contentView];
        }
    };
    restore();
    // PDFView 替换文档后会异步重新布局并回到首页，下一轮 runloop 再恢复一次。
    dispatch_async(dispatch_get_main_queue(), restore);
}

- (void)mouseDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagCommand) {
        NSPoint locationInView = [self convertPoint:event.locationInWindow fromView:nil];
        PDFPage *page = [self pageForPoint:locationInView nearest:YES];
        if (page && self.document) {
            NSInteger pageIndex = [self.document indexForPage:page];
            NSPoint pointOnPage = [self convertPoint:locationInView toPage:page];
            NSRect bounds = [page boundsForBox:kPDFDisplayBoxCropBox];

            if ([self.syncDelegate respondsToSelector:@selector(pdfViewDidRequestInverseSearchAtPoint:pageIndex:pageBounds:)]) {
                [self.syncDelegate pdfViewDidRequestInverseSearchAtPoint:pointOnPage
                                                              pageIndex:pageIndex
                                                             pageBounds:bounds];
            }
            return;
        }
    }

    [super mouseDown:event];
}

- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex {
    if (!self.document || pageIndex >= (NSInteger)self.document.pageCount) return;

    PDFPage *page = [self.document pageAtIndex:pageIndex];
    if (!page) return;

    [self goToPage:page];

    NSRect viewRect = [self convertRect:pageRect fromPage:page];

    // 扩大一点点边缘，更清晰
    viewRect = NSInsetRect(viewRect, -4, -2);

    if (_currentOverlay) {
        [_currentOverlay removeFromSuperview];
        _currentOverlay = nil;
    }

    TMHighlightOverlayView *overlay = [[TMHighlightOverlayView alloc] initWithFrame:viewRect];
    overlay.wantsLayer = YES;
    overlay.alphaValue = 1.0;
    [self addSubview:overlay];
    _currentOverlay = overlay;

    // 滚动至可见
    [self scrollRectToVisible:viewRect];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_currentOverlay == overlay) {
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.duration = 0.5;
                overlay.animator.alphaValue = 0.0;
            } completionHandler:^{
                [overlay removeFromSuperview];
                if (self->_currentOverlay == overlay) {
                    self->_currentOverlay = nil;
                }
            }];
        }
    });
}

@end
