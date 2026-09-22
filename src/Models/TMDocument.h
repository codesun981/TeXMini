#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMDocument : NSObject

@property (nonatomic, strong, nullable) NSURL *fileURL;
@property (nonatomic, copy) NSString *content;
@property (nonatomic, assign) BOOL isDirty;

@property (nonatomic, readonly, nullable) NSURL *expectedPDFURL;
@property (nonatomic, readonly, nullable) NSURL *expectedSyncTeXURL;

+ (instancetype)documentWithDefaultTemplate;
+ (instancetype)documentWithChineseTemplate;
+ (instancetype)documentWithBlankTemplate;
+ (nullable instancetype)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error;

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)saveCurrentFileWithError:(NSError **)error;
- (void)cleanAuxiliaryFiles;

@end

NS_ASSUME_NONNULL_END
