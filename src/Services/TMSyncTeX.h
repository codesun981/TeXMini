#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMSyncTeXResult : NSObject
@property (nonatomic, assign) NSInteger pageIndex; // 0-based page index
@property (nonatomic, assign) NSRect targetRect;   // in PDF page coordinates
@property (nonatomic, copy, nullable) NSString *sourceFilePath;
@property (nonatomic, assign) NSInteger sourceLine;
@property (nonatomic, assign) NSInteger sourceColumn;
@end

@interface TMSyncTeX : NSObject

/// 源码行 → PDF 位置。找不到该行时库会自动向前后就近查找；结果矩形为该行所有盒子的并集（PDF 页坐标，原点左下）。
+ (nullable TMSyncTeXResult *)forwardSearchLine:(NSInteger)line
                                         column:(NSInteger)column
                                     sourceFile:(NSString *)sourceFilePath
                                        pdfPath:(NSString *)pdfPath
                                       pdfView:(nullable PDFView *)pdfView;

+ (nullable TMSyncTeXResult *)inverseSearchPoint:(NSPoint)pointOnPage
                                       pageIndex:(NSInteger)pageIndex
                                      pageBounds:(NSRect)pageBounds
                                         pdfPath:(NSString *)pdfPath;

/// 释放缓存的 synctex scanner（正常情况下按 .synctex.gz 修改时间自动失效，无需手动调用）。
+ (void)invalidateCache;

@end

NS_ASSUME_NONNULL_END
