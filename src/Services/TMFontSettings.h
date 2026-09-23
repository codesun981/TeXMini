#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 导言区里的字体设置。nil 表示“文档类默认”（不写对应命令 / 选项）。
@interface TMDocumentFontSettings : NSObject
/// \setmainfont{…} 的字体名，如 "Times New Roman"。
@property (nonatomic, copy, nullable) NSString *latinFont;
/// \setCJKmainfont{…} 的字体名，如 "Songti SC"。
@property (nonatomic, copy, nullable) NSString *cjkFont;
/// \documentclass 的字号选项，如 "12pt" / "zihao=-4"。
@property (nonatomic, copy, nullable) NSString *sizeOption;
@end

/// 文档字体的纯文本逻辑：读写导言区、从日志找缺失字体、Windows → macOS 字体替换。
/// 不依赖 AppKit / CoreText；“本机有没有这个字体”由调用方（TMFontCatalog）判断。
@interface TMFontSettings : NSObject

#pragma mark - 导言区

/// \documentclass{…} 里的文档类名；没有返回 nil。
+ (nullable NSString *)documentClassInContent:(NSString *)content;
/// 同时有 \documentclass 与 \begin{document}，才能写字体设置。
+ (BOOL)contentHasPreamble:(NSString *)content;
/// ctexart / ctexrep / ctexbook / ctexbeamer，或导言区加载了 ctex 宏包。
+ (BOOL)isCTeXContent:(NSString *)content;

/// 该文档类支持的字号选项（不含“默认”）；未知文档类返回空数组，调用方应禁用字号选择。
+ (NSArray<NSString *> *)sizeOptionsForDocumentClass:(NSString *)documentClass;
/// "zihao=-4" → "小四（12pt）"，"12pt" → "12pt"。
+ (NSString *)displayNameForSizeOption:(NSString *)option;

/// 从导言区读出当前设置（注释掉的行不算）。
+ (TMDocumentFontSettings *)settingsInContent:(NSString *)content;

/// 把 settings 写进导言区：已有的 \setmainfont / \setCJKmainfont 只替换字体名（保留用户的选项），
/// 没有就插在 \begin{document} 之前，并按需补 \usepackage{fontspec} / {xeCJK}；设为 nil 则删掉对应行。
/// cjkFakeBold 为 YES 时新插入的 \setCJKmainfont 带 [AutoFakeBold]（字体没有粗体字重时用）。
/// 没有导言区返回 nil。
+ (nullable NSString *)contentByApplyingSettings:(TMDocumentFontSettings *)settings
                                     cjkFakeBold:(BOOL)cjkFakeBold
                                       toContent:(NSString *)content;

#pragma mark - 缺失字体

/// fontspec / XeTeX 报告找不到的字体名（去重、保持出现顺序）。
+ (NSArray<NSString *> *)missingFontNamesInLog:(NSString *)log;
/// 缺失字体来自 ctex 的某个 fontset（如 fontset=windows）时返回该 fontset 名，否则 nil。
+ (nullable NSString *)failingCTeXFontsetInLog:(NSString *)log;
/// 删掉 \documentclass 或 \usepackage{ctex} 上的 fontset=<fontset> 选项，让 ctex 自动选本机字体；找不到返回 nil。
+ (nullable NSString *)contentByRemovingCTeXFontset:(NSString *)fontset inContent:(NSString *)content;

/// 常见的 Windows / Office / 思源 / 苹方字体在 macOS 上的替代（按优先级），调用方取第一个本机可用的；不认识返回空数组。
+ (NSArray<NSString *> *)replacementCandidatesForFont:(NSString *)fontName;
/// 内容里出现在字体相关行（含 "font" 的行）上、替换表认识的字体名（按原文大小写，去重）。
+ (NSArray<NSString *> *)knownReplaceableFontNamesInContent:(NSString *)content;
/// 只在含 "font" 的行上按整词替换（不区分大小写）；count 返回替换次数。
+ (NSString *)contentByReplacingFonts:(NSDictionary<NSString *, NSString *> *)replacements
                            inContent:(NSString *)content
                                count:(nullable NSUInteger *)count;

@end

NS_ASSUME_NONNULL_END
