#import "TMPDFView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>

@interface TMHighlightOverlayView : NSView
@end

/// 荧光笔样式：只铺一层黄色、不描边。图层用 multiply 混合，纸面变黄、字仍是黑的，
/// 就像用记号笔划过；反色阅读时整块一起被取反，效果是深底上一条黄带。
@implementation TMHighlightOverlayView
- (void)drawRect:(NSRect)dirtyRect {
    // alpha 留一点，即使混合模式失效也不会把字盖住
    [[NSColor colorWithSRGBRed:1.0 green:0.90 blue:0.20 alpha:0.55] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:2.0 yRadius:2.0] fill];
}
@end

@interface TMPDFView ()
/// 当前文档加载时 PDF 文件的修改时间：判断同一份 PDF 是否重新生成过。
@property (nonatomic, strong, nullable) NSDate *loadedModificationDate;
@end

@implementation TMPDFView {
    TMHighlightOverlayView *_currentOverlay;
}

- (void)setupPDFView {
    self.displayMode = kPDFDisplaySinglePageContinuous;
    self.displaysPageBreaks = YES;
    self.fitMode = TMPDFFitPage;
    self.backgroundColor = [NSColor windowBackgroundColor];
    self.wantsLayer = YES;
}

#pragma mark - 缩放方式

- (void)setFitMode:(TMPDFFitMode)fitMode {
    _fitMode = fitMode;
    [self applyFitMode];
}

- (void)applyFitMode {
    switch (self.fitMode) {
        case TMPDFFitWidth:
            self.autoScales = YES;
            break;
        case TMPDFFitPage: {
            // 连续滚动模式下 PDFKit 的 autoScales 只适配宽度，整页要自己算
            PDFPage *page = self.currentPage ?: [self.document pageAtIndex:0];
            if (!page) return;
            NSRect box = [page boundsForBox:self.displayBox];
            NSSize pageSize = (page.rotation % 180 == 0) ? box.size : NSMakeSize(box.size.height, box.size.width);
            if (pageSize.width <= 0 || pageSize.height <= 0) return;
            NSEdgeInsets m = self.pageBreakMargins;
            CGFloat w = NSWidth(self.bounds) - m.left - m.right - 8.0;
            CGFloat h = NSHeight(self.bounds) - m.top - m.bottom - 8.0;
            if (w <= 0 || h <= 0) return;
            self.autoScales = NO;
            self.scaleFactor = MIN(w / pageSize.width, h / pageSize.height);
            [self goToPage:page];
            break;
        }
        case TMPDFFitManual:
            self.autoScales = NO;
            break;
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (self.fitMode == TMPDFFitPage) [self applyFitMode];
}

- (void)zoomIn:(id)sender {
    self.fitMode = TMPDFFitManual;
    [super zoomIn:sender];
}

- (void)zoomOut:(id)sender {
    self.fitMode = TMPDFFitManual;
    [super zoomOut:sender];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (self.fitMode != TMPDFFitManual) self.fitMode = TMPDFFitManual;
    [super magnifyWithEvent:event];
}

#pragma mark - 反色

- (void)setInverted:(BOOL)inverted {
    if (_inverted == inverted) return;
    _inverted = inverted;
    if (inverted) {
        CIFilter *invert = [CIFilter filterWithName:@"CIColorInvert"];
        CIFilter *hue = [CIFilter filterWithName:@"CIHueAdjust"];
        [hue setValue:@(M_PI) forKey:kCIInputAngleKey];
        self.contentFilters = @[invert, hue];
        // 固定用浅灰做页间背景，取反后是深灰；不能用随系统变化的 windowBackgroundColor
        self.backgroundColor = [NSColor colorWithWhite:0.86 alpha:1.0];
    } else {
        self.contentFilters = @[];
        self.backgroundColor = [NSColor windowBackgroundColor];
    }
}

#pragma mark - 查找（交给控制器的搜索栏）

- (void)performTextFinderAction:(nullable id)sender {
    NSInteger tag = [sender respondsToSelector:@selector(tag)] ? [sender tag] : NSTextFinderActionShowFindInterface;
    if (tag == NSTextFinderActionNextMatch || tag == NSTextFinderActionPreviousMatch) {
        if ([self.syncDelegate respondsToSelector:@selector(pdfViewDidRequestFindNext:)]) {
            [self.syncDelegate pdfViewDidRequestFindNext:(tag == NSTextFinderActionNextMatch)];
        }
        return;
    }
    if ([self.syncDelegate respondsToSelector:@selector(pdfViewDidRequestFindInterface)]) {
        [self.syncDelegate pdfViewDidRequestFindInterface];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if (menuItem.action == @selector(performTextFinderAction:)) {
        NSInteger tag = menuItem.tag;
        return self.document != nil &&
               (tag == NSTextFinderActionShowFindInterface || tag == NSTextFinderActionNextMatch || tag == NSTextFinderActionPreviousMatch);
    }
    return [super validateMenuItem:menuItem];
}

static NSDate *TMFileModificationDate(NSURL *url) {
    return [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil][NSFileModificationDate];
}

- (void)loadPDFFromURL:(NSURL *)url {
    // 同一项目里切换 .tex 时预览的往往是同一份 main.pdf：没重新生成就不动它（避免闪烁、不跳回第一页），
    // 生成过就按保留视口的方式刷新
    if (self.document && [url.URLByStandardizingPath isEqual:self.currentPDFURL.URLByStandardizingPath]) {
        NSDate *modified = TMFileModificationDate(url);
        if (modified && [modified isEqualToDate:self.loadedModificationDate]) return;
        [self loadPDFFromURL:url preservingViewport:YES];
        return;
    }
    [self loadPDFFromURL:url preservingViewport:NO];
}

- (void)loadPDFFromURL:(NSURL *)url preservingViewport:(BOOL)preserve {
    NSDate *modified = TMFileModificationDate(url);
    PDFDocument *newDoc = [[PDFDocument alloc] initWithURL:url];
    if (!newDoc) return;

    self.currentPDFURL = url;
    self.loadedModificationDate = modified;

    if (!preserve || !self.document) {
        self.document = newDoc;
        [self applyFitMode];
        // 文档刚换上时 PDFKit 还没排版完，下一轮再适配一次
        dispatch_async(dispatch_get_main_queue(), ^{ [self applyFitMode]; });
        return;
    }

    // 记录旧视口：当前页索引 + 滚动偏移，必须在替换 document 之前取。
    PDFPage *currentPage = self.currentPage;
    NSInteger pageIndex = currentPage ? [self.document indexForPage:currentPage] : 0;
    NSScrollView *scrollView = self.enclosingScrollView;
    NSPoint scrollPoint = scrollView ? scrollView.contentView.bounds.origin : NSZeroPoint;
    CGFloat scale = self.scaleFactor;

    self.document = newDoc;

    void (^restore)(void) = ^{
        // 适配整页 / 宽度时按新文档重新算；手动缩放则保持原比例
        if (self.fitMode == TMPDFFitManual) {
            self.autoScales = NO;
            self.scaleFactor = scale;
        } else if (self.fitMode == TMPDFFitWidth) {
            self.autoScales = YES;
        } else {
            self.autoScales = NO;
            self.scaleFactor = scale; // 页面尺寸没变时就是原来的整页比例；变了等窗口调整时再算
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
        NSRect viewRect = NSInsetRect([self convertRect:pageRect fromPage:page], -3, -1);
        TMHighlightOverlayView *overlay = [[TMHighlightOverlayView alloc] initWithFrame:viewRect];
        overlay.wantsLayer = YES;
        overlay.alphaValue = 1.0;
        [self addSubview:overlay];
        overlay.layer.compositingFilter = @"multiplyBlendMode"; // 黄底黑字，而不是盖一层半透明色
        self->_currentOverlay = overlay;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 无论它是否还是“当前”高亮，到点都必须淡出移除，否则会残留
            if (overlay.superview == nil) return;
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
                context.duration = 0.6;
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

/// 把页面上的矩形滚到视口正中。
///
/// 不直接操作 PDFKit 内部的 clip view：页面比视口窄/短时 PDFKit 用负偏移把页面居中，
/// 自己算并夹到 (0,0) 会把页面顶到角落。这里把目标矩形上下扩到接近一屏高，
/// 交给 goToRect:onPage: 让整块可见，目标行自然落在正中。
- (void)scrollToCenterPageRect:(NSRect)pageRect onPage:(PDFPage *)page {
    NSRect viewportOnPage = [self convertRect:self.bounds toPage:page];
    CGFloat viewportHeight = NSHeight(viewportOnPage);
    if (viewportHeight <= 0) {
        [self goToRect:pageRect onPage:page];
        return;
    }

    // 略小于一屏：矩形能整块放进视口，PDFKit 就不会退化成“顶部对齐”
    CGFloat height = MAX(NSHeight(pageRect), viewportHeight * 0.96);
    NSRect target = NSMakeRect(NSMinX(pageRect),
                               NSMidY(pageRect) - height / 2.0,
                               NSWidth(pageRect),
                               height);
    [self goToRect:target onPage:page];
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
