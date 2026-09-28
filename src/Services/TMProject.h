#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 文件树中的一个节点（文件或目录）。
@interface TMFileNode : NSObject
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isDirectory;
@property (nonatomic, copy) NSArray<TMFileNode *> *children;
@end

/// “文件夹即项目”：不维护工程文件，一切从磁盘目录推断。
@interface TMProject : NSObject

/// 可在编辑器里打开的纯文本类型（tex / bib / sty / cls / bst / txt / md …）。
+ (NSArray<NSString *> *)editableExtensions;
/// 文件浏览器里显示的类型：editableExtensions + 常见图片 / pdf。
+ (NSArray<NSString *> *)visibleExtensions;
+ (BOOL)isEditableFileURL:(NSURL *)url;

/// 递归列出目录（跳过隐藏项与编译辅助文件），目录优先、按名字排序。maxDepth 防止误开巨型目录。
+ (NSArray<TMFileNode *> *)fileTreeForDirectory:(NSURL *)directoryURL maxDepth:(NSUInteger)maxDepth;

/// 推断应当编译的主文件：
/// 1. `% !TEX root` 魔法注释；
/// 2. 当前文件自身含 \documentclass；
/// 3. 当前目录及最多 8 层祖先中含 \documentclass 的文件，按完整路径追踪 \input/\include/\subfile/
///    \import 依赖；只有一个明确引用当前文件的候选才采用它，循环/超大依赖图有界处理；
///    无明确引用时，仅在当前或紧邻父目录只有一个候选的情况下回退；
/// 4. 都不满足返回 nil（调用方回退到当前文件）。
+ (nullable NSURL *)mainFileURLForDocumentURL:(NSURL *)documentURL content:(NSString *)content;

/// 在目录顶层寻找含 \documentclass 的 .tex 文件（用于“打开文件夹”）。
/// 多个候选时优先 main.tex / thesis.tex / paper.tex 等常见名字，再退回引用其他文件最多的那个。
+ (nullable NSURL *)guessMainFileInDirectory:(NSURL *)directoryURL;

/// 主文件的 .bbl 能否重新生成：主文件里（注释外）的 \bibliography{…} / \addbibresource{…}
/// 必须至少声明一个来源，且每个来源都是可读的实际文件；宏展开或输入依赖无法完整确认时返回 NO。
/// 从 arXiv 下载的源码常常只有 .bbl 没有 .bib，这种 .bbl 删掉就再也生成不出来。
+ (BOOL)canRegenerateBibliographyForTeXFileURL:(NSURL *)texURL;

@end

NS_ASSUME_NONNULL_END
