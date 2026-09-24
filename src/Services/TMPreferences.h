#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 任何偏好变化后发出（主线程）。userInfo 为空，监听方整体重新应用即可。
extern NSNotificationName const TMPreferencesDidChangeNotification;

/// 所有用户偏好的唯一入口，底层是 NSUserDefaults（键以 TM 开头）。
/// 纯 Foundation，便于测试；UI 层通过它读写，不直接碰 NSUserDefaults。
@interface TMPreferences : NSObject

+ (instancetype)shared;
/// 注册默认值；App 启动时调用一次。
+ (void)registerDefaults;

// 编辑器
@property (nonatomic, copy) NSString *editorFontName;      // 默认 Menlo
@property (nonatomic, assign) CGFloat editorFontSize;      // 9–30，默认 13.5
@property (nonatomic, assign) BOOL softWrapEnabled;        // 默认 YES
@property (nonatomic, assign) BOOL highlightsCurrentLine;  // 默认 YES
/// 停止输入 1 秒后、窗口失去焦点时保存 .tex（不编译）；切换 / 关闭文件时不再询问。默认 YES。
@property (nonatomic, assign) BOOL autoSaveEnabled;

// 启动
/// 启动时打开上次的项目与文件；关闭则显示首页。默认 YES。
@property (nonatomic, assign) BOOL restoreLastSession;

// 编译
@property (nonatomic, assign) NSInteger defaultEngine;     // TMTeXEngine 的原始值，默认 0（latexmk 自动）
@property (nonatomic, assign) BOOL autoCompileEnabled;     // 默认 NO
@property (nonatomic, assign) BOOL shellEscapeEnabled;     // 默认 NO
/// .aux/.log 等中间文件放在源文件旁（老习惯）。默认 NO：放进 ~/Library/Caches/TeXMini/build/。
@property (nonatomic, assign) BOOL auxFilesBesideSource;
@property (nonatomic, copy) NSString *latexmkExtraArguments; // 默认空；按空白拆分

// PDF
@property (nonatomic, assign) BOOL pdfInverted;            // 默认 NO

/// 把附加参数字符串按空白拆成数组（支持简单的双引号包裹）。
+ (NSArray<NSString *> *)argumentsFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
