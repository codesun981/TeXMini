#import "TMTemplatePicker.h"
#import "TMHoverControl.h"

static const CGFloat kTMTemplateCardWidth = 208;
static const NSUInteger kTMTemplateColumns = 3;

@implementation TMTemplateItem

+ (instancetype)itemWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbolName {
    TMTemplateItem *item = [[TMTemplateItem alloc] init];
    item.title = title;
    item.subtitle = subtitle;
    item.symbolName = symbolName;
    return item;
}

@end

@interface TMTemplatePicker ()
@property (nonatomic, strong) NSPanel *panel;
@property (nonatomic, weak) NSWindow *parentWindow;
@property (nonatomic, copy) NSArray<TMHoverControl *> *cards;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, copy) void (^completion)(NSInteger);
@end

@implementation TMTemplatePicker

+ (void)presentWithItems:(NSArray<TMTemplateItem *> *)items
                 forWindow:(NSWindow *)window
                completion:(void (^)(NSInteger))completion {
    if (items.count == 0) return;
    TMTemplatePicker *picker = [[TMTemplatePicker alloc] init];
    picker.parentWindow = window;
    picker.completion = completion;
    [picker buildWithItems:items];
    // sheet 结束前由 completionHandler 持有 picker
    [window beginSheet:picker.panel completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK && picker.completion) picker.completion(picker.selectedIndex);
        picker.completion = nil;
    }];
}

- (void)buildWithItems:(NSArray<TMTemplateItem *> *)items {
    NSTextField *title = [NSTextField labelWithString:@"从模板开始"];
    title.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    NSTextField *hint = [NSTextField labelWithString:@"选择一个起点，双击或按回车直接使用。当前文档若有未保存的更改会先询问。"];
    hint.font = [NSFont systemFontOfSize:12];
    hint.textColor = [NSColor secondaryLabelColor];

    // 卡片网格：按列数分行
    NSMutableArray<TMHoverControl *> *cards = [NSMutableArray array];
    NSStackView *grid = [[NSStackView alloc] init];
    grid.orientation = NSUserInterfaceLayoutOrientationVertical;
    grid.alignment = NSLayoutAttributeLeading;
    grid.spacing = 12;
    NSStackView *row = nil;
    for (NSUInteger i = 0; i < items.count; i++) {
        if (i % kTMTemplateColumns == 0) {
            row = [[NSStackView alloc] init];
            row.spacing = 12;
            row.alignment = NSLayoutAttributeTop;
            [grid addArrangedSubview:row];
        }
        TMHoverControl *card = [self cardForItem:items[i] index:i];
        [row addArrangedSubview:card];
        [cards addObject:card];
    }
    self.cards = cards;
    self.selectedIndex = 0;
    cards.firstObject.selected = YES;

    NSButton *cancel = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancel:)];
    cancel.keyEquivalent = @"\e";
    NSButton *use = [NSButton buttonWithTitle:@"使用模板" target:self action:@selector(confirm:)];
    use.keyEquivalent = @"\r";
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[spacer, cancel, use]];
    buttons.spacing = 10;

    NSStackView *content = [NSStackView stackViewWithViews:@[title, hint, grid, buttons]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeLeading;
    content.spacing = 6;
    [content setCustomSpacing:20 afterView:hint];
    [content setCustomSpacing:24 afterView:grid];
    content.edgeInsets = NSEdgeInsetsMake(24, 24, 20, 24);
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [buttons.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-48].active = YES;

    CGFloat gridWidth = kTMTemplateColumns * kTMTemplateCardWidth + (kTMTemplateColumns - 1) * 12;
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, gridWidth + 48, 300)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskDocModalWindow
                                                  backing:NSBackingStoreBuffered
                                                    defer:YES];
    [panel.contentView addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:panel.contentView.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:panel.contentView.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:panel.contentView.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:panel.contentView.trailingAnchor],
        [content.widthAnchor constraintEqualToConstant:gridWidth + 48],
    ]];
    panel.defaultButtonCell = use.cell;
    self.panel = panel;
}

- (TMHoverControl *)cardForItem:(TMTemplateItem *)item index:(NSUInteger)index {
    NSImage *symbol = [NSImage imageWithSystemSymbolName:item.symbolName accessibilityDescription:nil];
    NSImageView *icon = [NSImageView imageViewWithImage:[symbol imageWithSymbolConfiguration:
                          [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular]]];
    icon.contentTintColor = [NSColor controlAccentColor];
    NSView *badge = [[NSView alloc] init];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 8;
    badge.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.12].CGColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:36],
        [badge.heightAnchor constraintEqualToConstant:36],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
    ]];

    NSTextField *t = [NSTextField labelWithString:item.title];
    t.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    NSTextField *s = [NSTextField wrappingLabelWithString:item.subtitle];
    s.font = [NSFont systemFontOfSize:12];
    s.textColor = [NSColor secondaryLabelColor];
    s.preferredMaxLayoutWidth = kTMTemplateCardWidth - 32;

    NSStackView *inner = [NSStackView stackViewWithViews:@[badge, t, s]];
    inner.orientation = NSUserInterfaceLayoutOrientationVertical;
    inner.alignment = NSLayoutAttributeLeading;
    inner.spacing = 4;
    [inner setCustomSpacing:14 afterView:badge];
    inner.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);

    TMHoverControl *card = [[TMHoverControl alloc] init];
    card.cardStyle = YES;
    [card fillWithContent:inner];
    [card.widthAnchor constraintEqualToConstant:kTMTemplateCardWidth].active = YES;
    [card.heightAnchor constraintGreaterThanOrEqualToConstant:132].active = YES;
    __weak typeof(self) weakSelf = self;
    card.onClick = ^{ [weakSelf selectIndex:(NSInteger)index]; };
    card.onDoubleClick = ^{
        [weakSelf selectIndex:(NSInteger)index];
        [weakSelf confirm:nil];
    };
    return card;
}

- (void)selectIndex:(NSInteger)index {
    self.selectedIndex = index;
    [self.cards enumerateObjectsUsingBlock:^(TMHoverControl *card, NSUInteger i, BOOL *stop) {
        card.selected = (NSInteger)i == index;
    }];
}

- (void)confirm:(id)sender {
    [self.parentWindow endSheet:self.panel returnCode:NSModalResponseOK];
}

- (void)cancel:(id)sender {
    [self.parentWindow endSheet:self.panel returnCode:NSModalResponseCancel];
}

@end
