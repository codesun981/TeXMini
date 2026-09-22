#import <Foundation/Foundation.h>
#import "TMOutlineItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface TMOutlineParser : NSObject

/**
 * 从 LaTeX 文本中解析大纲层级树。
 * @param latexString 完整的 LaTeX 源码
 * @param outFlatList 可选输出，按文档顺序排列的扁平大纲项列表，方便快速检索
 * @return 根节点列表构成的树状结构
 */
+ (NSArray<TMOutlineItem *> *)parseOutlineFromLaTeXString:(NSString *)latexString
                                                 flatList:(NSArray<TMOutlineItem *> * _Nullable * _Nullable)outFlatList;

/**
 * 根据源码光标行号，快速查找当前光标所处的章节项
 * @param lineNumber 1-based 行号
 * @param flatList 扁平大纲列表
 * @return 当前光标所处的章节（若光标在首个章节之前，返回 nil）
 */
+ (nullable TMOutlineItem *)activeItemForLineNumber:(NSInteger)lineNumber
                                         inFlatList:(NSArray<TMOutlineItem *> *)flatList;

/**
 * 清洗标题字符串（去除常见的 LaTeX 格式标签如 \textbf{}，多余的花括号与空白）
 */
+ (NSString *)cleanHeadingTitle:(NSString *)rawTitle;

@end

NS_ASSUME_NONNULL_END
