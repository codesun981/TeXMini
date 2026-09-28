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
/// 优先调用此接口，将本次已决定的引擎传给 UI；旧接口作为兼容后备。
- (void)compilerDidStartCompilingDocument:(NSURL *)fileURL engineName:(NSString *)engineName useLatexmk:(BOOL)useLatexmk;
- (void)compilerDidOutputLog:(NSString *)text;
- (void)compilerDidFinishSuccess:(double)durationSeconds pdfURL:(NSURL *)pdfURL issues:(NSArray<TMLogIssue *> *)issues;
- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues;
- (void)compilerDidCancel;
@end

/// 编译产物的确定路径；不访问磁盘，供编译、预览与按文件名清理共同使用。
@interface TMCompilerOutputPaths : NSObject
@property (nonatomic, readonly) NSURL *outputDirectoryURL;
@property (nonatomic, readonly) NSURL *auxiliaryDirectoryURL;
@property (nonatomic, readonly) NSString *jobName;
@property (nonatomic, readonly) NSURL *pdfURL;
@property (nonatomic, readonly) NSURL *synctexURL;
/// 只有 TeXMini 默认的专用缓存目录为 YES；用户指定的目录必须按产物文件逐个清理。
@property (nonatomic, readonly) BOOL usesManagedAuxiliaryDirectory;
- (NSURL *)outputFileURLWithExtension:(NSString *)extension;
- (NSURL *)auxiliaryFileURLWithExtension:(NSString *)extension;
@end

@interface TMCompiler : NSObject

@property (nonatomic, weak) id<TMCompilerDelegate> delegate;
@property (nonatomic, assign) TMTeXEngine engine;
/// 传 -shell-escape（minted / TikZ externalize 需要）。默认 NO。
@property (nonatomic, assign) BOOL shellEscapeEnabled;
/// YES：中间文件留在源文件旁（老行为）。NO（默认）：放进 auxiliaryDirectoryForTeXFileURL: 给出的缓存目录。
@property (nonatomic, assign) BOOL auxFilesBesideSource;
/// 追加到命令行末尾（文件名之前）的额外参数，例如 @[@"-outdir=build"]。
@property (nonatomic, copy) NSArray<NSString *> *extraArguments;
@property (nonatomic, readonly) BOOL isCompiling;
/// 包括已丢弃但仍在启动、运行或排空管道的旧任务；清理辅助文件前必须等它为 NO。
@property (nonatomic, readonly) BOOL hasActiveCompilationWork;

+ (instancetype)sharedCompiler;
+ (nullable NSString *)findExecutablePathForEngine:(TMTeXEngine)engine;
+ (nullable NSString *)findExecutableNamed:(NSString *)name;
+ (BOOL)isMacTeXInstalled;

/// 某个主文件的中间文件目录：~/Library/Caches/TeXMini/build/<文件名>-<路径哈希>/。
/// 按完整路径区分，同名的 main.tex 在不同项目里互不干扰。不负责创建目录。
+ (NSURL *)auxiliaryDirectoryForTeXFileURL:(NSURL *)texFileURL;

/// texFileURL 应已解析到主文件。支持 outdir/output-directory、auxdir/aux-directory、jobname，
/// 接受 -/--、= 或分离的值，同类选项最后一次出现生效；jobname 的 %A 展开为主文件名。
+ (TMCompilerOutputPaths *)outputPathsForTeXFileURL:(NSURL *)texFileURL
                               auxFilesBesideSource:(BOOL)auxFilesBesideSource
                                     extraArguments:(nullable NSArray<NSString *> *)extraArguments;

/// 组装命令行参数（不含可执行文件本身）。useLatexmk=YES 时第一个参数是 -pdf / -xelatex / -lualatex。
/// PDF 与 .synctex.gz 写到 outputDir；auxDir 非空且与 outputDir 不同时，其余中间文件写到 auxDir。
/// 不用 latexmk 时引擎只认一个 -output-directory，这时全部写进 auxDir，由调用方再把 PDF 拷出来。
+ (NSArray<NSString *> *)argumentsForEngineName:(NSString *)engineName
                                     useLatexmk:(BOOL)useLatexmk
                                      outputDir:(NSString *)outputDir
                                         auxDir:(nullable NSString *)auxDir
                                       fileName:(NSString *)fileName
                                    shellEscape:(BOOL)shellEscape
                                 extraArguments:(nullable NSArray<NSString *> *)extra;

/// 编译 texFileURL。若文件声明了 `% !TEX root`，实际编译 root 文件，回调里的 pdfURL 也对应 root。
/// 只要 latexmk 可用就统一走 latexmk（自动跑够遍数），显式选择的引擎映射为 -xelatex / -pdf；
/// 没有 latexmk 时才直接调用引擎单遍。
- (void)compileFileAtURL:(NSURL *)texFileURL;
- (void)cancelCompilation;
/// 切换文档/项目时取消并立即丢弃旧任务的所有回调（包括已排队的日志和结果）。
/// 不发送 compilerDidCancel，新文档可以立即开始编译。
- (void)cancelCompilationAndDiscardResults;

/// 根据用户选择 + 魔法注释 + 内容启发式，得出实际使用的引擎名（不看依赖的 .cls / .sty）。
- (NSString *)effectiveEngineNameForContent:(NSString *)content;
/// 同上，并在 directoryURL（主文件所在目录）里顺着 \documentclass / \usepackage 查看 .cls / .sty（最多两层），
/// 找不到的非标准文档类再问 kpsewhich。reason 返回判断依据（状态栏 tooltip 用）。
- (NSString *)effectiveEngineNameForContent:(NSString *)content
                               directoryURL:(nullable NSURL *)directoryURL
                                     reason:(NSString * _Nullable * _Nullable)reason;
/// 后台预览传入偏好快照，判断期间不再读取可变的 self.engine。
- (NSString *)effectiveEngineNameForContent:(NSString *)content
                               directoryURL:(nullable NSURL *)directoryURL
                            preferredEngine:(TMTeXEngine)preferredEngine
                                     reason:(NSString * _Nullable * _Nullable)reason;

@end

NS_ASSUME_NONNULL_END
