#import "TMDocumentFontView.h"

/// 中文字体下拉框里排在最前面的 macOS 自带字体。
static NSArray<NSString *> *TMRecommendedCJKFamilies(void) {
    return @[@"Songti SC", @"Heiti SC", @"Kaiti SC", @"STFangsong", @"Hiragino Sans GB"];
}

/// 英文字体下拉框里的常用正文字体。
static NSArray<NSString *> *TMRecommendedLatinFamilies(void) {
    return @[@"Times New Roman", @"Palatino", @"Georgia", @"Baskerville", @"Charter", @"Hoefler Text",
             @"Helvetica Neue", @"Avenir Next", @"Optima", @"Arial"];
}

@interface TMDocumentFontView ()
@property (nonatomic, copy) NSArray<TMFontFamily *> *families;
@property (nonatomic, strong, readwrite) NSPopUpButton *latinPopup;
@property (nonatomic, strong) NSPopUpButton *cjkPopup;
@property (nonatomic, strong) NSPopUpButton *sizePopup;
@property (nonatomic, strong) NSTextField *previewLabel;
@end

@implementation TMDocumentFontView

- (instancetype)initWithFamilies:(NSArray<TMFontFamily *> *)families
                         current:(TMDocumentFontSettings *)current
                     sizeOptions:(NSArray<NSString *> *)sizeOptions
                 cjkDefaultTitle:(NSString *)cjkDefaultTitle {
    self = [super initWithFrame:NSMakeRect(0, 0, 380, 170)];
    if (!self) return nil;
    _families = [families copy];

    NSMutableArray<TMFontFamily *> *latin = [NSMutableArray array];
    NSMutableArray<TMFontFamily *> *cjk = [NSMutableArray array];
    for (TMFontFamily *f in families) [(f.supportsChinese ? cjk : latin) addObject:f];

    _latinPopup = [self popupWithDefaultTitle:@"文档默认（Latin Modern）"
                                  recommended:TMRecommendedLatinFamilies()
                                     families:latin
                                     selected:current.latinFont];
    _cjkPopup = [self popupWithDefaultTitle:cjkDefaultTitle
                                recommended:TMRecommendedCJKFamilies()
                                   families:cjk
                                   selected:current.cjkFont];

    _sizePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_sizePopup addItemWithTitle:@"文档默认"];
    NSMutableArray<NSString *> *sizes = [sizeOptions mutableCopy];
    if (current.sizeOption && ![sizes containsObject:current.sizeOption]) [sizes addObject:current.sizeOption];
    for (NSString *opt in sizes) {
        [_sizePopup addItemWithTitle:[TMFontSettings displayNameForSizeOption:opt]];
        _sizePopup.lastItem.representedObject = opt;
    }
    if (current.sizeOption) [_sizePopup selectItemAtIndex:[_sizePopup indexOfItemWithRepresentedObject:current.sizeOption]];
    if (sizes.count == 0) {
        _sizePopup.enabled = NO;
        _sizePopup.toolTip = @"这个文档类的字号由模板自己决定";
    }

    for (NSPopUpButton *p in @[_latinPopup, _cjkPopup]) {
        p.target = self;
        p.action = @selector(selectionChanged:);
    }

    _previewLabel = [NSTextField labelWithString:@""];
    _previewLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"英文字体："], _latinPopup],
        @[[NSTextField labelWithString:@"中文字体："], _cjkPopup],
        @[[NSTextField labelWithString:@"字号："], _sizePopup],
        @[[NSTextField labelWithString:@"预览："], _previewLabel],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 8;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid rowAtIndex:3].topPadding = 4;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:self.topAnchor],
        [grid.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [grid.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_latinPopup.widthAnchor constraintEqualToConstant:280],
        [_cjkPopup.widthAnchor constraintEqualToAnchor:_latinPopup.widthAnchor],
        [_sizePopup.widthAnchor constraintEqualToAnchor:_latinPopup.widthAnchor],
        [_previewLabel.widthAnchor constraintEqualToAnchor:_latinPopup.widthAnchor],
    ]];
    [self layoutSubtreeIfNeeded];
    self.frame = NSMakeRect(0, 0, grid.fittingSize.width, grid.fittingSize.height);
    [self updatePreview];
    return self;
}

- (NSString *)titleForFamily:(TMFontFamily *)f {
    return [f.displayName isEqualToString:f.familyName] ? f.familyName
                                                        : [NSString stringWithFormat:@"%@（%@）", f.displayName, f.familyName];
}

/// 默认项 → 推荐 → 全部；文档里写的字体本机没有时单独列出并选中，不悄悄改掉。
- (NSPopUpButton *)popupWithDefaultTitle:(NSString *)defaultTitle
                             recommended:(NSArray<NSString *> *)recommended
                                families:(NSArray<TMFontFamily *> *)families
                                selected:(nullable NSString *)selected {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMenu *menu = popup.menu;
    [popup addItemWithTitle:defaultTitle];

    NSMutableDictionary<NSString *, TMFontFamily *> *byName = [NSMutableDictionary dictionary];
    for (TMFontFamily *f in families) byName[f.familyName] = f;

    BOOL selectedKnown = selected == nil;
    for (TMFontFamily *f in families) {
        if ([f.familyName caseInsensitiveCompare:selected ?: @""] == NSOrderedSame) { selectedKnown = YES; break; }
    }
    if (!selectedKnown) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *missing = [menu addItemWithTitle:[NSString stringWithFormat:@"%@（本机没有）", selected] action:nil keyEquivalent:@""];
        missing.representedObject = selected;
    }

    NSMutableArray<TMFontFamily *> *top = [NSMutableArray array];
    for (NSString *name in recommended) if (byName[name]) [top addObject:byName[name]];
    if (top.count) {
        [menu addItem:[NSMenuItem separatorItem]];
        [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"推荐"]];
        for (TMFontFamily *f in top) {
            [menu addItemWithTitle:[self titleForFamily:f] action:nil keyEquivalent:@""].representedObject = f.familyName;
        }
    }
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[NSMenuItem sectionHeaderWithTitle:@"全部"]];
    for (TMFontFamily *f in families) {
        [menu addItemWithTitle:[self titleForFamily:f] action:nil keyEquivalent:@""].representedObject = f.familyName;
    }

    if (selected) {
        for (NSMenuItem *item in menu.itemArray) {
            NSString *name = item.representedObject;
            if (name && [name caseInsensitiveCompare:selected] == NSOrderedSame) { [popup selectItem:item]; break; }
        }
    }
    return popup;
}

- (void)selectionChanged:(id)sender {
    [self updatePreview];
}

- (void)updatePreview {
    TMDocumentFontSettings *s = self.selectedSettings;
    // 默认项的预览：LaTeX 默认英文字体 Latin Modern 通常不在系统里，用 Times 近似；ctex 在 macOS 上默认宋体
    NSFont *latinFont = [self fontForFamily:s.latinFont ?: @"Times New Roman"] ?: [NSFont systemFontOfSize:14];
    NSFont *cjkFont = [self fontForFamily:s.cjkFont ?: @"Songti SC"] ?: [NSFont systemFontOfSize:14];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"Sample Text 123  " attributes:@{NSFontAttributeName: latinFont}]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"中文字体预览" attributes:@{NSFontAttributeName: cjkFont}]];
    self.previewLabel.attributedStringValue = text;
}

- (nullable NSFont *)fontForFamily:(NSString *)family {
    NSFontDescriptor *d = [NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute: family}];
    return [NSFont fontWithDescriptor:d size:14];
}

- (TMDocumentFontSettings *)selectedSettings {
    TMDocumentFontSettings *s = [[TMDocumentFontSettings alloc] init];
    s.latinFont = self.latinPopup.selectedItem.representedObject;
    s.cjkFont = self.cjkPopup.selectedItem.representedObject;
    s.sizeOption = self.sizePopup.selectedItem.representedObject;
    return s;
}

- (BOOL)selectedCJKFontNeedsFakeBold {
    NSString *name = self.cjkPopup.selectedItem.representedObject;
    if (!name) return NO;
    for (TMFontFamily *f in self.families) {
        if ([f.familyName isEqualToString:name]) return !f.hasBold;
    }
    return NO;
}

@end
