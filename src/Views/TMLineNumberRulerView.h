#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMLineNumberRulerView : NSRulerView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView;

/// 行号 → 标记等级（0 错误、1 警告、2 坏盒子，同 TMLogIssueKind）。在行号左侧画一个小圆点。传空字典清除。
- (void)setIssueMarks:(NSDictionary<NSNumber *, NSNumber *> *)marks;

@end

NS_ASSUME_NONNULL_END
