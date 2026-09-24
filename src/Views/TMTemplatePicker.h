#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 一个可选模板的展示信息。
@interface TMTemplateItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
/// SF Symbol 名称。
@property (nonatomic, copy) NSString *symbolName;
+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbolName;
@end

/// “从模板开始”弹窗：卡片网格，单击选中、双击或回车使用，Esc 取消。
@interface TMTemplatePicker : NSObject

/// 以 sheet 形式弹出；用户确认后回调所选下标，取消则不回调。
+ (void)presentWithItems:(NSArray<TMTemplateItem *> *)items
                 forWindow:(NSWindow *)window
                completion:(void (^)(NSInteger index))completion;

@end

NS_ASSUME_NONNULL_END
