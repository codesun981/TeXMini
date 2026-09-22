#import "TMSyncTeX.h"
#include "synctex_parser.h"

@implementation TMSyncTeXResult
@end

#pragma mark - Scanner 缓存

/// 解析 .synctex.gz 对大文档要几十到几百毫秒；同一份 PDF 反复查询时复用 scanner。
/// 以 synctex 文件的修改时间为失效依据（每次编译都会重写它）。
static synctex_scanner_p gCachedScanner = NULL;
static NSString *gCachedPDFPath = nil;
static NSDate *gCachedSyncDate = nil;

static NSDate *TMSyncTeXFileDate(NSString *pdfPath) {
    NSString *base = pdfPath.stringByDeletingPathExtension;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *candidate in @[[base stringByAppendingPathExtension:@"synctex.gz"],
                                  [base stringByAppendingPathExtension:@"synctex"]]) {
        NSDate *d = [fm attributesOfItemAtPath:candidate error:nil][NSFileModificationDate];
        if (d) return d;
    }
    return nil;
}

static synctex_scanner_p TMSyncTeXScanner(NSString *pdfPath) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) return NULL;
    NSDate *syncDate = TMSyncTeXFileDate(pdfPath);
    if (!syncDate) return NULL;

    if (gCachedScanner && [gCachedPDFPath isEqualToString:pdfPath] && [gCachedSyncDate isEqualToDate:syncDate]) {
        return gCachedScanner;
    }
    if (gCachedScanner) {
        synctex_scanner_free(gCachedScanner);
        gCachedScanner = NULL;
    }
    gCachedScanner = synctex_scanner_new_with_output_file(pdfPath.UTF8String, NULL, 1);
    gCachedPDFPath = gCachedScanner ? [pdfPath copy] : nil;
    gCachedSyncDate = gCachedScanner ? syncDate : nil;
    return gCachedScanner;
}

@implementation TMSyncTeX

+ (void)invalidateCache {
    if (gCachedScanner) {
        synctex_scanner_free(gCachedScanner);
        gCachedScanner = NULL;
    }
    gCachedPDFPath = nil;
    gCachedSyncDate = nil;
}

#pragma mark - 正向：源码 → PDF

+ (nullable TMSyncTeXResult *)forwardSearchLine:(NSInteger)line
                                         column:(NSInteger)column
                                     sourceFile:(NSString *)sourceFilePath
                                        pdfPath:(NSString *)pdfPath
                                       pdfView:(nullable PDFView *)pdfView {
    synctex_scanner_p scanner = TMSyncTeXScanner(pdfPath);
    if (!scanner) return nil;

    // page_hint：让库把离当前可见页最近的结果排在前面（同一行出现在多页时，比如脚注/浮动体）
    int pageHint = 1;
    if (pdfView && pdfView.document && pdfView.currentPage) {
        pageHint = (int)[pdfView.document indexForPage:pdfView.currentPage] + 1;
    }

    // 库内部会在找不到该行时向前后各试最多 100 行；column 未被使用，传 -1 即可。
    if (synctex_display_query(scanner, sourceFilePath.UTF8String, (int)line, -1, pageHint) <= 0) {
        return nil;
    }

    // 取第一页的所有结果，合并成一个矩形：整行文字都会被高亮，而不只是第一个盒子
    synctex_node_p node = synctex_scanner_next_result(scanner);
    if (!node) return nil;
    int page1Based = synctex_node_page(node);
    NSInteger pageIndex = page1Based - 1;

    NSRect pageBounds = NSMakeRect(0, 0, 595.28, 841.89); // 缺省 A4
    if (pdfView && pdfView.document && pageIndex >= 0 && pageIndex < (NSInteger)pdfView.document.pageCount) {
        pageBounds = [[pdfView.document pageAtIndex:pageIndex] boundsForBox:kPDFDisplayBoxCropBox];
    }

    NSRect unionRect = NSZeroRect;
    NSUInteger count = 0;
    while (node) {
        if (synctex_node_page(node) == page1Based) {
            // *_visible_* 一族返回的是已乘 magnification 的 PDF 点，v 是从页面顶部量起的基线位置
            CGFloat h = synctex_node_box_visible_h(node);
            CGFloat v = synctex_node_box_visible_v(node);
            CGFloat w = synctex_node_box_visible_width(node);
            CGFloat height = synctex_node_box_visible_height(node);
            CGFloat depth = synctex_node_box_visible_depth(node);
            if (height + depth <= 0) { height = 10; depth = 2; }
            if (w <= 0) w = 2;

            NSRect r = NSMakeRect(NSMinX(pageBounds) + h,
                                  NSMaxY(pageBounds) - v - depth,
                                  w,
                                  height + depth);
            unionRect = count == 0 ? r : NSUnionRect(unionRect, r);
            count++;
            if (count >= 24) break; // 极长的行没必要全部合并
        }
        node = synctex_scanner_next_result(scanner);
    }
    if (count == 0) return nil;

    // 页面级盒子（例如整页的 vbox）没意义，退化成一条横跨版心的细带
    if (NSHeight(unionRect) > NSHeight(pageBounds) * 0.6) {
        unionRect = NSMakeRect(NSMinX(unionRect), NSMaxY(unionRect) - 14, NSWidth(unionRect), 14);
    }

    TMSyncTeXResult *result = [[TMSyncTeXResult alloc] init];
    result.pageIndex = pageIndex;
    result.targetRect = unionRect;
    result.sourceLine = line;
    result.sourceColumn = column;
    result.sourceFilePath = sourceFilePath;
    return result;
}

#pragma mark - 反向：PDF → 源码

+ (nullable TMSyncTeXResult *)inverseSearchPoint:(NSPoint)pointOnPage
                                       pageIndex:(NSInteger)pageIndex
                                      pageBounds:(NSRect)pageBounds
                                         pdfPath:(NSString *)pdfPath {
    synctex_scanner_p scanner = TMSyncTeXScanner(pdfPath);
    if (!scanner) return nil;

    TMSyncTeXResult *result = nil;
    float synctexX = (float)(pointOnPage.x - NSMinX(pageBounds));
    float synctexY = (float)(NSMaxY(pageBounds) - pointOnPage.y);
    int targetPage = (int)(pageIndex + 1);

    if (synctex_edit_query(scanner, targetPage, synctexX, synctexY) > 0) {
        synctex_node_p node = synctex_scanner_next_result(scanner);
        if (node) {
            int tag = synctex_node_tag(node);
            const char *cName = synctex_scanner_get_name(scanner, tag);
            int line = synctex_node_line(node);
            int col = synctex_node_column(node);

            result = [[TMSyncTeXResult alloc] init];
            result.pageIndex = pageIndex;
            result.sourceLine = line;
            result.sourceColumn = col > 0 ? col : 1;
            if (cName) {
                result.sourceFilePath = [NSString stringWithUTF8String:cName];
            }
        }
    }
    return result;
}

@end
