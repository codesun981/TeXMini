#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMMarkdownRegionKind) {
    TMMarkdownRegionHeading = 0,   // # 标题 整行（含 #）
    TMMarkdownRegionMarker,        // 标题的 #、列表的 - / 1.、引用的 >、分隔线
    TMMarkdownRegionStrong,        // **粗** / __粗__（含标记）
    TMMarkdownRegionEmphasis,      // *斜* / _斜_（含标记）
    TMMarkdownRegionStrike,        // ~~删除~~
    TMMarkdownRegionCode,          // `代码`、``` 代码块 ```（含围栏）、缩进代码不算
    TMMarkdownRegionLink,          // [文字](地址) / ![图](地址) 整段
    TMMarkdownRegionQuote          // > 引用 整行
};

typedef struct {
    TMMarkdownRegionKind kind;
    NSRange range;
} TMMarkdownRegion;

@interface TMMarkdownScanResult : NSObject
@property (nonatomic, readonly) NSUInteger regionCount;
/// 按起点排序
@property (nonatomic, readonly) const TMMarkdownRegion *regions;
@end

/// 按行扫描常用的 Markdown 语法，只认标题、粗斜体、删除线、代码、链接、列表、引用、分隔线。
/// 不追求 CommonMark 完全兼容：用于代码模式着色和（以后的）易读渲染。
@interface TMMarkdownScanner : NSObject
+ (TMMarkdownScanResult *)scanString:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
