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
/// 扫描结果按文件修改时间缓存，项目不大时同步扫描足够快。
@interface TMCompletionProvider : NSObject

@property (nonatomic, strong, nullable) NSURL *projectRootURL;

/// 分析 text 在 cursor 处的上下文。没有可补全的上下文时 kind 为 None。
+ (TMCompletionContext *)contextInText:(NSString *)text cursorLocation:(NSUInteger)cursor;

/// 返回按前缀过滤、去重、排序后的候选。currentText 用来收集当前未保存文档里的 label / 环境。
- (NSArray<NSString *> *)completionsForContext:(TMCompletionContext *)context currentText:(NSString *)currentText;

/// 让下一次查询重新扫描磁盘（保存、编译后调用）。
- (void)invalidate;

// 供测试与内部使用
+ (NSArray<NSString *> *)labelsInText:(NSString *)text;
+ (NSArray<NSString *> *)citationKeysInBibText:(NSString *)text;
+ (NSArray<NSString *> *)environmentsInText:(NSString *)text;
+ (NSArray<NSString *> *)commandsInText:(NSString *)text;
+ (NSArray<NSString *> *)builtinCommands;
+ (NSArray<NSString *> *)builtinEnvironments;

@end

NS_ASSUME_NONNULL_END
