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
    BOOL wantsInverseSearch = (event.modifierFlags & NSEventModifierFlagCommand) || event.clickCount == 2;
    if (wantsInverseSearch) {
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
            return; // 双击不再交给 PDFKit 选词
        }
    }

    [super mouseDown:event];
}

- (void)flashHighlightRect:(NSRect)pageRect onPageAtIndex:(NSInteger)pageIndex {
    if (!self.document || pageIndex >= (NSInteger)self.document.pageCount) return;

    PDFPage *page = [self.document pageAtIndex:pageIndex];
    if (!page) return;

    [self removeOverlayIfAny];
    [self scrollToCenterPageRect:pageRect onPage:page];

    // 等这一轮布局结束再画高亮，convertRect:fromPage: 才是滚动后的坐标
    dispatch_async(dispatch_get_main_queue(), ^{
        [self removeOverlayIfAny]; // 同一轮里若有多次请求，只保留最后一个
        NSRect viewRect = NSInsetRect([self convertRect:pageRect fromPage:page], -4, -2);
        TMHighlightOverlayView *overlay = [[TMHighlightOverlayView alloc] initWithFrame:viewRect];
        overlay.wantsLayer = YES;
        overlay.alphaValue = 1.0;
        [self addSubview:overlay];
        self->_currentOverlay = overlay;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 无论它是否还是“当前”高亮，到点都必须淡出移除，否则会残留
            if (overlay.superview == nil) return;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.duration = 0.5;
                overlay.animator.alphaValue = 0.0;
            } completionHandler:^{
                [overlay removeFromSuperview];
                if (self->_currentOverlay == overlay) {
                    self->_currentOverlay = nil;
                }
            }];
        });
    });
}

/// 把页面上的矩形滚到视口正中（水平方向只在超出可见范围时才调整）。
- (void)scrollToCenterPageRect:(NSRect)pageRect onPage:(PDFPage *)page {
    NSView *docView = self.documentView;
    NSScrollView *scrollView = docView.enclosingScrollView;
    if (!docView || !scrollView) {
        [self goToRect:pageRect onPage:page];
        return;
    }

    NSRect inSelf = [self convertRect:pageRect fromPage:page];
    NSRect inDoc = [docView convertRect:inSelf fromView:self];
    NSClipView *clip = scrollView.contentView;
    NSRect visible = clip.bounds;
    NSRect docBounds = docView.bounds;

    NSPoint origin = visible.origin;
    origin.y = NSMidY(inDoc) - NSHeight(visible) / 2.0;
    if (NSMinX(inDoc) < NSMinX(visible) || NSMaxX(inDoc) > NSMaxX(visible)) {
        origin.x = NSMidX(inDoc) - NSWidth(visible) / 2.0;
    }
    origin.x = MAX(NSMinX(docBounds), MIN(origin.x, NSMaxX(docBounds) - NSWidth(visible)));
    origin.y = MAX(NSMinY(docBounds), MIN(origin.y, NSMaxY(docBounds) - NSHeight(visible)));

    [clip scrollToPoint:origin];
    [scrollView reflectScrolledClipView:clip];
}

/// 滚动或缩放后叠加层位置就不对了，直接撤掉，避免高亮飘在错误的地方。
- (void)scrollWheel:(NSEvent *)event {
    [self removeOverlayIfAny];
    [super scrollWheel:event];
}

- (void)removeOverlayIfAny {
    if (_currentOverlay) {
        [_currentOverlay removeFromSuperview];
        _currentOverlay = nil;
    }
}

@end
