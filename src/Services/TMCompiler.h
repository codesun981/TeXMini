#import <Foundation/Foundation.h>
#import "TMLogParser.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMTeXEngine) {
    TMTeXEngineLatexmk = 0,   // 自动：魔法注释 → ctex 启发式 → pdflatex
    TMTeXEngineXeLaTeX,
    TMTeXEnginePDFLaTeX,
    TMTeXEngineLuaLaTeX
};

@protocol TMCompilerDelegate <NSObject>
@optional
- (void)compilerDidStartCompilingDocument:(NSURL *)fileURL;
- (void)compilerDidOutputLog:(NSString *)text;
- (void)compilerDidFinishSuccess:(double)durationSeconds pdfURL:(NSURL *)pdfURL issues:(NSArray<TMLogIssue *> *)issues;
- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues;
- (void)compilerDidCancel;
@end

@interface TMCompiler : NSObject

@property (nonatomic, weak) id<TMCompilerDelegate> delegate;
@property (nonatomic, assign) TMTeXEngine engine;
/// 传 -shell-escape（minted / TikZ externalize 需要）。默认 NO。
@property (nonatomic, assign) BOOL shellEscapeEnabled;
/// 追加到命令行末尾（文件名之前）的额外参数，例如 @[@"-outdir=build"]。
@property (nonatomic, copy) NSArray<NSString *> *extraArguments;
@property (nonatomic, readonly) BOOL isCompiling;

+ (instancetype)sharedCompiler;
+ (nullable NSString *)findExecutablePathForEngine:(TMTeXEngine)engine;
+ (nullable NSString *)findExecutableNamed:(NSString *)name;
+ (BOOL)isMacTeXInstalled;

/// 组装命令行参数（不含可执行文件本身）。useLatexmk=YES 时第一个参数是 -pdf / -xelatex / -lualatex。
+ (NSArray<NSString *> *)argumentsForEngineName:(NSString *)engineName
                                     useLatexmk:(BOOL)useLatexmk
                                     workingDir:(NSString *)workingDir
                                       fileName:(NSString *)fileName
                                    shellEscape:(BOOL)shellEscape
                                 extraArguments:(nullable NSArray<NSString *> *)extra;

/// 编译 texFileURL。若文件声明了 `% !TEX root`，实际编译 root 文件���回调里的 pdfURL 也对应 root。
/// 只要 latexmk 可用就统一走 latexmk（自动跑够遍数），显式选择的引擎映射为 -xelatex / -pdf；
/// 没有 latexmk 时才直接调用引擎单遍。
- (void)compileFileAtURL:(NSURL *)texFileURL;
- (void)cancelCompilation;

/// 根据用户选择 + 魔法注释 + 内容启发式，得出实际使用的引擎名（用于状态栏显示）。
- (NSString *)effectiveEngineNameForContent:(NSString *)content;

@end

NS_ASSUME_NONNULL_END
