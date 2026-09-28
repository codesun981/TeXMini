#import <Foundation/Foundation.h>
#import "TMOutlineItem.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMLaTeXRegionKind) {
    TMLaTeXRegionCommand = 0,    // \foo
    TMLaTeXRegionEnvironment,    // \begin{foo} / \end{foo}
    TMLaTeXRegionMath,           // $…$ $$…$$ \(…\) \[…\] 以及 equation / align 等整个环境
    TMLaTeXRegionVerbatim,       // \verb|…|、verbatim / lstlisting / minted 的内容
    TMLaTeXRegionComment,        // % 到行尾、comment 环境的内容
    TMLaTeXRegionRaw             // \url{…} 等按原样读取的参数：不着色，但里面的 % $ { 不算数
};

typedef struct {
    TMLaTeXRegionKind kind;
    NSRange range;
} TMLaTeXRegion;

/// 一个标题（\section 等、包装它们的自定义命令、beamer 的帧标题）。
@interface TMLaTeXHeading : NSObject
@property (nonatomic, assign) TMOutlineLevel level;
@property (nonatomic, copy) NSString *commandName;
/// 花括号里的原始标题文本（未清洗）
@property (nonatomic, copy) NSString *rawTitle;
/// 命令反斜杠所在位置
@property (nonatomic, assign) NSUInteger location;
@end

@interface TMLaTeXScanResult : NSObject
@property (nonatomic, readonly) NSUInteger regionCount;
@property (nonatomic, readonly) const TMLaTeXRegion *regions;   // 按起点排序，公式里的注释会与公式区重叠
@property (nonatomic, readonly) NSArray<TMLaTeXHeading *> *headings;
/// 长公式 / 代码块 / 注释环境的种类摘要；范围失效判断使用 rangeAffectedComparedToScan:editedRange:。
@property (nonatomic, readonly) NSString *blockSignature;
@property (nonatomic, readonly) NSUInteger sourceLength;

/// 与上次扫描相比，需要在编辑段落之外重染的区域（新文本坐标）；没有变化返回 {NSNotFound, 0}。
/// editedRange 是这两次扫描之间所有编辑在新文本中的包围范围。
- (NSRange)rangeAffectedComparedToScan:(nullable TMLaTeXScanResult *)previous editedRange:(NSRange)editedRange;

/// index 处是否在注释、代码块或原样参数里（括号匹配等应忽略这些位置）。二分查找。
- (BOOL)isIgnorableAtIndex:(NSUInteger)index;
@end

/// 按 TeX 的读法把整篇源码扫一遍，高亮、大纲、括号匹配都以这一次扫描的结果为准，
/// 不再各自用正则去猜（正则处理不了 $a$$b$、代码块里的 $、\newcommand 定义体里的 \section 这类情况）。
/// 线性扫描，一万行的文档几毫秒。
@interface TMLaTeXScanner : NSObject
+ (TMLaTeXScanResult *)scanString:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
