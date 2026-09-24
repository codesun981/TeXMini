#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class TMWelcomeView;

@protocol TMWelcomeViewDelegate <NSObject>
- (void)welcomeViewDidRequestNewDocument:(TMWelcomeView *)view;
/// 点击指定模板新建：0: 学术论文, 1: 中文报告, 2: 空白文档
- (void)welcomeView:(TMWelcomeView *)view didSelectTemplateAtIndex:(NSInteger)index;
/// “从模板开始”：弹出模板选择。
- (void)welcomeViewDidRequestTemplatePicker:(TMWelcomeView *)view;
- (void)welcomeViewDidRequestOpenFile:(TMWelcomeView *)view;
- (void)welcomeViewDidRequestOpenFolder:(TMWelcomeView *)view;
/// 最近列表里的文件或文件夹。
- (void)welcomeView:(TMWelcomeView *)view didSelectRecentURL:(NSURL *)url;
/// “返回编辑”或 Esc：收起首页回到当前文档。
- (void)welcomeViewDidRequestDismiss:(TMWelcomeView *)view;
@end

/// 首页：盖在主窗口内容区上方，只有新建 / 打开 / 最近列表和“启动时打开上次的项目”开关。
@interface TMWelcomeView : NSView

@property (nonatomic, weak) id<TMWelcomeViewDelegate> delegate;
/// 背后有正在编辑的文档时显示“返回编辑”，Esc 也可收起。
@property (nonatomic, assign) BOOL showsDismissButton;
/// 重新读取最近列表与偏好；每次显示前调用。
- (void)reload;

@end

NS_ASSUME_NONNULL_END
