#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 编辑器里的补全候选浮窗。
///
/// 系统 NSTextView 的补全弹窗字体大、会把第一个候选直接写进正文，而且输入时不会继续过滤，
/// 这里换成一个小而轻的浮窗：只负责显示和选择，文字的替换由编辑器自己做。
/// 浮窗从不成为 key window，键盘始终留在编辑器，由编辑器把 ↑↓ 回车 Esc 转给它。
@interface TMCompletionPopup : NSObject

@property (nonatomic, readonly, getter=isVisible) BOOL visible;
@property (nonatomic, readonly, nullable) NSString *selectedItem;
/// 双击某一项时调用（键盘确认由编辑器自己处理）。
@property (nonatomic, copy, nullable) void (^onAccept)(NSString *item);

/// 显示或刷新候选。anchor 是被补全那段文字在屏幕上的矩形，浮窗贴在它下方（下方放不下就放上方）。
/// partial 是用户已经输入的部分，在候选里加粗显示。
- (void)showItems:(NSArray<NSString *> *)items
          partial:(NSString *)partial
     anchorOnScreen:(NSRect)anchor
       parentWindow:(NSWindow *)parent
             font:(NSFont *)font;
- (void)hide;
- (void)moveSelectionBy:(NSInteger)delta;

@end

NS_ASSUME_NONNULL_END
