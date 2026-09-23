#import <Cocoa/Cocoa.h>
#import "TMFontSettings.h"
#import "TMFontCatalog.h"

NS_ASSUME_NONNULL_BEGIN

/// “文档字体”sheet 的内容：英文字体 / 中文字体 / 字号三个下拉框 + 一行预览。
/// 只负责选择，写回文档由 TMMainWindowController 完成。
@interface TMDocumentFontView : NSView

/// sizeOptions 为空时字号下拉框禁用（文档类的字号由模板决定）。
/// cjkDefaultTitle 是中文字体“默认”项的文字，如 "文档默认（ctex 自动选宋体）"。
- (instancetype)initWithFamilies:(NSArray<TMFontFamily *> *)families
                         current:(TMDocumentFontSettings *)current
                     sizeOptions:(NSArray<NSString *> *)sizeOptions
                 cjkDefaultTitle:(NSString *)cjkDefaultTitle;

@property (nonatomic, readonly) TMDocumentFontSettings *selectedSettings;
/// 选中的中文字体没有粗体字重，需要 AutoFakeBold。
@property (nonatomic, readonly) BOOL selectedCJKFontNeedsFakeBold;
@property (nonatomic, readonly) NSPopUpButton *latinPopup;

@end

NS_ASSUME_NONNULL_END
