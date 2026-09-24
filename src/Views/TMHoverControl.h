#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 可悬停的点击区域：首页卡片 / 列表行 / 文字按钮、模板选择卡片共用。
@interface TMHoverControl : NSView

@property (nonatomic, copy, nullable) void (^onClick)(void);
@property (nonatomic, copy, nullable) void (^onDoubleClick)(void);
@property (nonatomic, assign) BOOL isHovered;
/// YES：带描边和底色的卡片样式。
@property (nonatomic, assign) BOOL cardStyle;
/// 卡片被选中：描边用强调色。
@property (nonatomic, assign) BOOL selected;

/// 用一个内容视图填满自身。
- (void)fillWithContent:(NSView *)content;

@end

NS_ASSUME_NONNULL_END
