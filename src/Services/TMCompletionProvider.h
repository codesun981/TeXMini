#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMCompletionKind) {
    TMCompletionKindNone = 0,
    TMCompletionKindCitation,      // \cite{…}
    TMCompletionKindReference,     // \ref{…} \eqref{…} \autoref{…} …
    TMCompletionKindEnvironment,   // \begin{…} \end{…}
    TMCompletionKindCommand        // \foo
};

/// 描述光标处的补全上下文：补什么、被补的那段文字在哪。
@interface TMCompletionContext : NSObject
@property (nonatomic, assign) TMCompletionKind kind;
/// 需要被替换的部分（例如 `\cite{kn` 中的 `kn`；命令补全时包含反斜杠 `\sec`）。
@property (nonatomic, assign) NSRange partialRange;
@property (nonatomic, copy) NSString *partial;
@end

/// 从项目目录收集 \label、.bib 条目键、环境名和命令名，供编辑器补全使用。
/// 文件符号按指纹缓存；UI 使用异步接口，磁盘访问与提取均在内部串行队列上。
@interface TMCompletionProvider : NSObject

@property (nonatomic, strong, nullable) NSURL *projectRootURL;

/// 分析 text 在 cursor 处的上下文。没有可补全的上下文时 kind 为 None。
+ (TMCompletionContext *)contextInText:(NSString *)text cursorLocation:(NSUInteger)cursor;

/// 返回按前缀过滤、去重、排序后的候选。currentText 用来收集当前未保存文档里的 label / 环境。
- (NSArray<NSString *> *)completionsForContext:(TMCompletionContext *)context currentText:(NSString *)currentText;

/// documentKey 标识文档（正式文档传规范化绝对路径），revision 在每次内容变化时递增。
/// 同一 key + revision 只提取一次；正式文档的内存符号替代其磁盘符号。同步接口供测试/非 UI 使用。
- (NSArray<NSString *> *)completionsForContext:(TMCompletionContext *)context
                                 currentText:(NSString *)currentText
                                 documentKey:(nullable NSString *)documentKey
                                    revision:(NSUInteger)revision;

/// 参数在调用时快照；结果在主线程返回。同一 provider 仅处理最新异步请求，被取代的请求不回调。
/// 已开始的提取允许完成以温热缓存；尚未开始的旧请求跳过。调用方仍应检查编辑状态。
/// 项目根变化或调用任一 invalidate 接口也会取消尚未返回的请求，不回调。
- (void)requestCompletionsForContext:(TMCompletionContext *)context
                        currentText:(NSString *)currentText
                        documentKey:(nullable NSString *)documentKey
                           revision:(NSUInteger)revision
                         completion:(void (^)(NSArray<NSString *> *items))completion;

/// 刷新文件列表/指纹，仍复用未变化文件的提取结果。
- (void)invalidate;
/// 保存后只使这个文件的提取结果失效；兼顾新建/删除。
- (void)invalidateFileAtURL:(NSURL *)url;

// 供测试与内部使用
- (nullable NSString *)readCompletionTextAtURL:(NSURL *)url;
+ (NSArray<NSString *> *)labelsInText:(NSString *)text;
+ (NSArray<NSString *> *)citationKeysInBibText:(NSString *)text;
+ (NSArray<NSString *> *)environmentsInText:(NSString *)text;
+ (NSArray<NSString *> *)commandsInText:(NSString *)text;
+ (NSArray<NSString *> *)builtinCommands;
+ (NSArray<NSString *> *)builtinEnvironments;

@end

NS_ASSUME_NONNULL_END
