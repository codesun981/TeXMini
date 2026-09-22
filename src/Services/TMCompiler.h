#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMTeXEngine) {
    TMTeXEngineLatexmk = 0,
    TMTeXEngineXeLaTeX,
    TMTeXEnginePDFLaTeX
};

@protocol TMCompilerDelegate <NSObject>
@optional
- (void)compilerDidStartCompilingDocument:(NSURL *)fileURL;
- (void)compilerDidOutputLog:(NSString *)text;
- (void)compilerDidFinishSuccess:(double)durationSeconds pdfURL:(NSURL *)pdfURL;
- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log;
@end

@interface TMCompiler : NSObject

@property (nonatomic, weak) id<TMCompilerDelegate> delegate;
@property (nonatomic, assign) TMTeXEngine engine;
@property (nonatomic, readonly) BOOL isCompiling;

+ (instancetype)sharedCompiler;
+ (nullable NSString *)findExecutablePathForEngine:(TMTeXEngine)engine;
+ (BOOL)isMacTeXInstalled;

- (void)compileFileAtURL:(NSURL *)texFileURL;
- (void)cancelCompilation;

@end

NS_ASSUME_NONNULL_END
