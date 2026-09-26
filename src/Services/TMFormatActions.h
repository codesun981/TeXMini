#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 段落样式：「格式」菜单和状态栏样式框里的那一组预设。
typedef NS_ENUM(NSInteger, TMParagraphStyle) {
    TMParagraphStyleBody = 0,
    TMParagraphStyleHeading1,
    TMParagraphStyleHeading2,
    TMParagraphStyleHeading3,
    TMParagraphStyleHeading4,
    TMParagraphStyleBulletList,
    TMParagraphStyleNumberedList,
    TMParagraphStyleQuote
};

typedef NS_ENUM(NSInteger, TMInlineStyle) {
    TMInlineStyleBold = 0,
    TMInlineStyleItalic,
    TMInlineStyleUnderline
};

typedef NS_ENUM(NSInteger, TMFormatInsertion) {
    TMFormatInsertInlineMath = 0,
    TMFormatInsertDisplayMath,
    TMFormatInsertTable,
    TMFormatInsertFootnote,
    TMFormatInsertLink
};

/// 一次替换：把 range 换成 replacement，之后选中 selection（替换后的坐标）。
@interface TMFormatEdit : NSObject
@property (nonatomic, assign) NSRange range;
@property (nonatomic, copy) NSString *replacement;
@property (nonatomic, assign) NSRange selection;
/// 需要在导言区补的宏包（例如链接要 hyperref）；不需要为 nil
@property (nonatomic, copy, nullable) NSString *requiredPackage;
@end

/// 「格式」菜单的纯文本逻辑：替用户写 \section{…} \textbf{…} 这些命令。
/// LaTeX 和 Markdown 各写各的语法；不依赖 AppKit，便于单元测试。
@interface TMFormatActions : NSObject

+ (NSString *)displayNameForParagraphStyle:(TMParagraphStyle)style;

/// 标题 1 是否对应 \chapter：book / report / ctexbook / 学位论文类文档类，或文中已经用了 \chapter。
/// mainContent 是主文件内容（多文件项目的导言区在主文件里），currentContent 是正在编辑的文件。
+ (BOOL)usesChaptersForMainContent:(nullable NSString *)mainContent currentContent:(NSString *)currentContent;

/// 光标所在段落的样式（状态栏样式框显示它）。
+ (TMParagraphStyle)paragraphStyleAtLocation:(NSUInteger)location inText:(NSString *)text
                                    markdown:(BOOL)markdown usesChapters:(BOOL)usesChapters;

/// 把选区所在的段落设成 style；已经是这个样式时变回正文（再按一次取消）。
+ (nullable TMFormatEdit *)editForParagraphStyle:(TMParagraphStyle)style selection:(NSRange)selection inText:(NSString *)text
                                        markdown:(BOOL)markdown usesChapters:(BOOL)usesChapters;

/// 加粗 / 斜体 / 下划线：有选区时包起来（已经包着就去掉）；没有选区时，光标在这种样式里就去掉，否则插入一对空的。
+ (TMFormatEdit *)editForInlineStyle:(TMInlineStyle)style selection:(NSRange)selection inText:(NSString *)text markdown:(BOOL)markdown;

/// 插入公式、表格、脚注、链接的骨架；有选区时尽量把选中的文字放进去。
+ (TMFormatEdit *)editForInsertion:(TMFormatInsertion)kind selection:(NSRange)selection inText:(NSString *)text markdown:(BOOL)markdown;

/// 若内容里还没加载 package，返回应插入 "\\usepackage{package}\n" 的位置；
/// hyperref 放在 \begin{document} 之前（它要最后加载），其他放在 \documentclass 行之后。
/// 已加载或找不到 \documentclass 时返回 NSNotFound。
+ (NSUInteger)usepackageInsertionLocationForPackage:(NSString *)package inContent:(NSString *)content;

@end

NS_ASSUME_NONNULL_END
