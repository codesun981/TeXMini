#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 不保留正文的不可变行首索引。沿用编辑器规则：UTF-16 位置，仅 '\n' 换行。
@interface TMLineIndex : NSObject
- (instancetype)initWithString:(NSString *)string;
@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly) NSUInteger lineCount;
/// 1-based；index 超出正文时夹至末尾。
- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)index;
/// 1-based；非法行号返回 NSNotFound，尾换行后的空行起点为 length。
- (NSUInteger)startOfLine:(NSUInteger)line;
@end

NS_ASSUME_NONNULL_END
