#import "TMSyncTeX.h"
#include "synctex_parser.h"

@implementation TMSyncTeXResult
@end

@implementation TMSyncTeX

+ (nullable TMSyncTeXResult *)forwardSearchLine:(NSInteger)line
                                         column:(NSInteger)column
                                     sourceFile:(NSString *)sourceFilePath
                                        pdfPath:(NSString *)pdfPath
                                       pdfView:(nullable PDFView *)pdfView {
    if (![[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) {
        return nil;
    }

    synctex_scanner_p scanner = synctex_scanner_new_with_output_file(pdfPath.UTF8String, NULL, 1);
    if (!scanner) {
        return nil;
    }

    TMSyncTeXResult *result = nil;
    int searchLine = (int)line;
    if (synctex_display_query(scanner, sourceFilePath.UTF8String, searchLine, (int)column, -1) > 0) {
        synctex_node_p node = synctex_scanner_next_result(scanner);
        if (node) {
            int page1Based = synctex_node_page(node);
            NSInteger pageIndex = page1Based - 1;

            float h = synctex_node_box_h(node);
            float v = synctex_node_box_v(node);
            float width = synctex_node_box_width(node);
            float height = synctex_node_box_height(node);

            NSRect pageBounds = NSZeroRect;
            if (pdfView && pdfView.document && pageIndex < (NSInteger)pdfView.document.pageCount) {
                PDFPage *pageObj = [pdfView.document pageAtIndex:pageIndex];
                pageBounds = [pageObj boundsForBox:kPDFDisplayBoxCropBox];
            } else {
                pageBounds = NSMakeRect(0, 0, 595.28, 841.89); // Default A4
            }

            CGFloat x = (CGFloat)h;
            CGFloat y = pageBounds.origin.y + pageBounds.size.height - (CGFloat)v - (CGFloat)height;
            CGFloat w = width > 0 ? (CGFloat)width : pageBounds.size.width - 2 * x;
            CGFloat hBox = height > 0 ? (CGFloat)height : 14.0;

            result = [[TMSyncTeXResult alloc] init];
            result.pageIndex = pageIndex;
            result.targetRect = NSMakeRect(x, y, w, hBox);
            result.sourceLine = line;
            result.sourceColumn = column;
            result.sourceFilePath = sourceFilePath;
        }
    }

    synctex_scanner_free(scanner);
    return result;
}

+ (nullable TMSyncTeXResult *)inverseSearchPoint:(NSPoint)pointOnPage
                                       pageIndex:(NSInteger)pageIndex
                                      pageBounds:(NSRect)pageBounds
                                         pdfPath:(NSString *)pdfPath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) {
        return nil;
    }

    synctex_scanner_p scanner = synctex_scanner_new_with_output_file(pdfPath.UTF8String, NULL, 1);
    if (!scanner) {
        return nil;
    }

    TMSyncTeXResult *result = nil;
    float synctexY = (float)(pageBounds.origin.y + pageBounds.size.height - pointOnPage.y);
    int targetPage = (int)(pageIndex + 1);

    if (synctex_edit_query(scanner, targetPage, (float)pointOnPage.x, synctexY) > 0) {
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

    synctex_scanner_free(scanner);
    return result;
}

@end
