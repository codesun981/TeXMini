#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 本机一个可被 XeLaTeX 使用的字体家族。
@interface TMFontFamily : NSObject
/// 写进 .tex 的名字（fontspec 按家族名查找），如 "Songti SC"。
@property (nonatomic, copy, readonly) NSString *familyName;
/// 按系统语言本地化的名字，如 "宋体-简"；没有本地化时同 familyName。
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, assign, readonly) BOOL supportsChinese;
/// 家族里有粗体字重；没有时 \textbf 需要 AutoFakeBold。
@property (nonatomic, assign, readonly) BOOL hasBold;
@end

/// 系统字体目录：CoreText 枚举一次（约 0.2 秒，后台线程）后缓存。
/// 过滤掉 XeTeX 读不到的字体：系统保留字体（如苹方，文件在 PrivateFrameworks 里）、点号开头的 UI 字体、位图字体。
@interface TMFontCatalog : NSObject

+ (instancetype)shared;
/// 已加载则同步回调；否则后台加载，完成后在主线程回调。
- (void)loadWithCompletion:(void (^)(NSArray<TMFontFamily *> *families))completion;
/// 未加载时为 nil。按 familyName 排序。
@property (nonatomic, copy, readonly, nullable) NSArray<TMFontFamily *> *families;
/// 不区分大小写地查找家族；未加载或没有时返回 nil。
- (nullable TMFontFamily *)familyNamed:(NSString *)name;

/// 同步枚举（测试与后台线程用）。
+ (NSArray<TMFontFamily *> *)enumerateSystemFamilies;

@end

NS_ASSUME_NONNULL_END
