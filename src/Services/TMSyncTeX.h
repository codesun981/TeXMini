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

+ (nullable TMSyncTeXResult *)forwardSearchLine:(NSInteger)line
                                         column:(NSInteger)column
                                     sourceFile:(NSString *)sourceFilePath
                                        pdfPath:(NSString *)pdfPath
                                       pdfView:(nullable PDFView *)pdfView;

+ (nullable TMSyncTeXResult *)inverseSearchPoint:(NSPoint)pointOnPage
                                       pageIndex:(NSInteger)pageIndex
                                      pageBounds:(NSRect)pageBounds
                                         pdfPath:(NSString *)pdfPath;

@end

NS_ASSUME_NONNULL_END
