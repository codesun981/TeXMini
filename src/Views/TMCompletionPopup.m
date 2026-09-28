#import "TMCompletionPopup.h"

static const NSInteger kTMPopupMaxRows = 8;
static const CGFloat kTMPopupCornerRadius = 8.0;
static const CGFloat kTMPopupMinWidth = 190.0;
static const CGFloat kTMPopupMaxWidth = 360.0;

/// 不抢焦点的无边框浮窗
@interface TMCompletionPanel : NSPanel
@end

@implementation TMCompletionPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

/// 浮窗背景只负责一块圆角纯色面；不使用 NSVisualEffectView，避免材质边缘产生白色高光。
@interface TMCompletionBackgroundView : NSView
@end

@implementation TMCompletionBackgroundView

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    self.layer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    self.layer.cornerRadius = kTMPopupCornerRadius;
    self.layer.masksToBounds = YES;
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    [self updateLayer];
}

@end

/// 浮窗不抢焦点；选中项使用系统强调色，但留出菜单式圆角内边距。
@interface TMCompletionRowView : NSTableRowView
@end

@implementation TMCompletionRowView
- (BOOL)isEmphasized { return YES; }

- (void)drawSelectionInRect:(NSRect)dirtyRect {
    if (!self.isSelected) return;
    NSRect highlight = NSInsetRect(self.bounds, 6.0, 2.0);
    [[NSColor selectedContentBackgroundColor] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:highlight xRadius:5.0 yRadius:5.0] fill];
}
@end

@interface TMCompletionPopup () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) TMCompletionPanel *panel;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, copy) NSArray<NSString *> *items;
@property (nonatomic, copy) NSString *partial;
@property (nonatomic, strong) NSFont *font;
@end

@implementation TMCompletionPopup

- (instancetype)init {
    self = [super init];
    if (self) {
        _items = @[];
        _partial = @"";
        _font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
        [self buildPanel];
    }
    return self;
}

- (void)buildPanel {
    _panel = [[TMCompletionPanel alloc] initWithContentRect:NSMakeRect(0, 0, 240, 100)
                                                  styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES];
    _panel.opaque = NO;
    _panel.backgroundColor = [NSColor clearColor];
    _panel.hasShadow = YES;
    _panel.level = NSPopUpMenuWindowLevel;
    _panel.hidesOnDeactivate = YES;

    // 纯色圆角内容层：panel 外部保持透明，只由 hasShadow 提供自然阴影。
    TMCompletionBackgroundView *background = [[TMCompletionBackgroundView alloc] initWithFrame:_panel.contentView.bounds];
    background.wantsLayer = YES;
    background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    background.layer.cornerRadius = kTMPopupCornerRadius;
    background.layer.masksToBounds = YES;
    [background updateLayer];
    _panel.contentView = background;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    _tableView.headerView = nil;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.intercellSpacing = NSMakeSize(0, 0);
    _tableView.style = NSTableViewStyleFullWidth;
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.focusRingType = NSFocusRingTypeNone;
    _tableView.refusesFirstResponder = YES;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(rowDoubleClicked:);

    _scrollView = [[NSScrollView alloc] initWithFrame:background.bounds];
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.borderType = NSNoBorder;
    _scrollView.documentView = _tableView;
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.contentInsets = NSEdgeInsetsMake(5, 0, 5, 0);
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [background addSubview:_scrollView];
}

#pragma mark - 显示

- (BOOL)isVisible {
    return self.panel.isVisible;
}

- (nullable NSString *)selectedItem {
    NSInteger row = self.tableView.selectedRow;
    return (row >= 0 && row < (NSInteger)self.items.count) ? self.items[row] : nil;
}

- (CGFloat)rowHeight {
    return ceil(self.font.ascender - self.font.descender + self.font.leading) + 6.0;
}

- (void)showItems:(NSArray<NSString *> *)items partial:(NSString *)partial anchorOnScreen:(NSRect)anchor parentWindow:(NSWindow *)parent font:(NSFont *)font {
    if (items.count == 0) { [self hide]; return; }

    // 保留原来选中的项（若它还在列表里），否则回到第一项
    NSString *previous = self.isVisible ? self.selectedItem : nil;
    self.items = items;
    self.partial = partial ?: @"";
    // 补全列表使用独立的小字号，避免编辑器字号较大时浮窗也变成“大面板”。
    CGFloat popupSize = MIN(MAX(font.pointSize - 2.0, 12.0), 14.0);
    self.font = [NSFont fontWithName:font.fontName size:popupSize]
        ?: [NSFont monospacedSystemFontOfSize:popupSize weight:NSFontWeightRegular];
    self.tableView.rowHeight = [self rowHeight];
    [self.tableView reloadData];

    NSUInteger keep = previous ? [items indexOfObject:previous] : NSNotFound;
    NSInteger row = keep == NSNotFound ? 0 : (NSInteger)keep;
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];

    // 宽度按最长候选算，限制在合理范围
    NSDictionary *attrs = @{NSFontAttributeName: self.font};
    CGFloat textWidth = 0;
    for (NSString *s in items) textWidth = MAX(textWidth, [s sizeWithAttributes:attrs].width);
    CGFloat width = MIN(MAX(ceil(textWidth) + 32.0, kTMPopupMinWidth), kTMPopupMaxWidth);
    NSInteger rows = MIN((NSInteger)items.count, kTMPopupMaxRows);
    CGFloat height = rows * self.tableView.rowHeight + 10.0;

    // 默认放在文字下方；屏幕下方放不下就翻到上方
    NSRect screen = (parent.screen ?: [NSScreen mainScreen]).visibleFrame;
    NSRect frame = NSMakeRect(NSMinX(anchor) - 8.0, NSMinY(anchor) - height - 2.0, width, height);
    if (NSMinY(frame) < NSMinY(screen)) frame.origin.y = NSMaxY(anchor) + 2.0;
    if (NSMaxX(frame) > NSMaxX(screen)) frame.origin.x = NSMaxX(screen) - width;
    [self.panel setFrame:frame display:YES];

    if (!self.panel.isVisible) {
        [parent addChildWindow:self.panel ordered:NSWindowAbove];
        [self.panel orderFront:nil];
    }
}

- (void)hide {
    if (!self.panel.isVisible) return;
    [self.panel.parentWindow removeChildWindow:self.panel];
    [self.panel orderOut:nil];
    self.items = @[];
}

- (void)moveSelectionBy:(NSInteger)delta {
    if (self.items.count == 0) return;
    NSInteger count = (NSInteger)self.items.count;
    NSInteger row = (self.tableView.selectedRow + delta + count) % count; // 首尾循环
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];
}

- (void)rowDoubleClicked:(id)sender {
    NSString *item = self.selectedItem;
    if (item && self.onAccept) self.onAccept(item);
}

#pragma mark - NSTableView

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.items.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTableCellView *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = @"cell";
        NSTextField *label = [NSTextField labelWithString:@""];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.usesSingleLineMode = YES;
        label.maximumNumberOfLines = 1;
        label.allowsDefaultTighteningForTruncation = YES;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12.0],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12.0],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
        ]];
    }
    cell.textField.attributedStringValue = [self attributedItem:self.items[row] selected:[tableView isRowSelected:row]];
    return cell;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
    return [[TMCompletionRowView alloc] init];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    // 选中行文字要换成白色，重画一遍（最多 60 行，开销可以忽略）
    NSIndexSet *all = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.items.count)];
    [self.tableView reloadDataForRowIndexes:all columnIndexes:[NSIndexSet indexSetWithIndex:0]];
}

/// 已输入的前缀加粗，未匹配部分保持清晰的主文字色
- (NSAttributedString *)attributedItem:(NSString *)item selected:(BOOL)selected {
    NSFont *bold = [[NSFontManager sharedFontManager] convertFont:self.font toHaveTrait:NSBoldFontMask];
    NSColor *textColor = selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:item attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: textColor,
    }];
    NSRange r = self.partial.length > 0 ? [item rangeOfString:self.partial options:NSCaseInsensitiveSearch] : NSMakeRange(NSNotFound, 0);
    if (r.location != NSNotFound) {
        [s addAttributes:@{NSFontAttributeName: bold, NSForegroundColorAttributeName: textColor} range:r];
    }
    return s;
}

@end
