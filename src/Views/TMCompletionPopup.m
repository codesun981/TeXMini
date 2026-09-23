#import "TMCompletionPopup.h"

static const NSInteger kTMPopupMaxRows = 8;
static const CGFloat kTMPopupCornerRadius = 6.0;

/// 不抢焦点的无边框浮窗
@interface TMCompletionPanel : NSPanel
@end

@implementation TMCompletionPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

/// 浮窗永远不是 key window，默认选中行会画成灰色；强制用强调色
@interface TMCompletionRowView : NSTableRowView
@end

@implementation TMCompletionRowView
- (BOOL)isEmphasized { return YES; }
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

    // 与系统菜单同一种半透明材质，自动适配深浅色
    NSVisualEffectView *effect = [[NSVisualEffectView alloc] initWithFrame:_panel.contentView.bounds];
    effect.material = NSVisualEffectMaterialMenu;
    effect.state = NSVisualEffectStateActive;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = kTMPopupCornerRadius;
    effect.layer.masksToBounds = YES;
    effect.layer.borderWidth = 0.5;
    effect.layer.borderColor = [[NSColor separatorColor] CGColor];
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _panel.contentView = effect;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    col.resizingMask = NSTableColumnAutoresizingMask;
    [_tableView addTableColumn:col];
    _tableView.headerView = nil;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.intercellSpacing = NSMakeSize(0, 0);
    _tableView.style = NSTableViewStyleInset;
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _tableView.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
    _tableView.refusesFirstResponder = YES;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.target = self;
    _tableView.doubleAction = @selector(rowDoubleClicked:);

    _scrollView = [[NSScrollView alloc] initWithFrame:effect.bounds];
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.borderType = NSNoBorder;
    _scrollView.documentView = _tableView;
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.contentInsets = NSEdgeInsetsMake(4, 0, 4, 0);
    _scrollView.automaticallyAdjustsContentInsets = NO;
    [effect addSubview:_scrollView];
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
    return ceil(self.font.ascender - self.font.descender + self.font.leading) + 8.0;
}

- (void)showItems:(NSArray<NSString *> *)items partial:(NSString *)partial anchorOnScreen:(NSRect)anchor parentWindow:(NSWindow *)parent font:(NSFont *)font {
    if (items.count == 0) { [self hide]; return; }

    // 保留原来选中的项（若它还在列表里），否则回到第一项
    NSString *previous = self.isVisible ? self.selectedItem : nil;
    self.items = items;
    self.partial = partial ?: @"";
    self.font = [NSFont fontWithName:font.fontName size:MAX(11.0, font.pointSize - 1.0)] ?: font;
    self.tableView.rowHeight = [self rowHeight];
    [self.tableView reloadData];

    NSUInteger keep = previous ? [items indexOfObject:previous] : NSNotFound;
    NSInteger row = keep == NSNotFound ? 0 : (NSInteger)keep;
    [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [self.tableView scrollRowToVisible:row];

    // 宽度按最长候选算，限制在合理范围
    NSDictionary *attrs = @{NSFontAttributeName: [[NSFontManager sharedFontManager] convertFont:self.font toHaveTrait:NSBoldFontMask]};
    CGFloat textWidth = 0;
    for (NSString *s in items) textWidth = MAX(textWidth, [s sizeWithAttributes:attrs].width);
    CGFloat width = MIN(MAX(ceil(textWidth) + 36.0, 160.0), 420.0);
    NSInteger rows = MIN((NSInteger)items.count, kTMPopupMaxRows);
    CGFloat height = rows * self.tableView.rowHeight + 8.0;

    // 默认放在文字下方；屏幕下方放不下就翻到上方
    NSRect screen = (parent.screen ?: [NSScreen mainScreen]).visibleFrame;
    NSRect frame = NSMakeRect(NSMinX(anchor) - 12.0, NSMinY(anchor) - height - 2.0, width, height);
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
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4.0],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4.0],
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

/// 已输入的前缀加粗，剩下的部分用次要颜色，一眼看出还差什么
- (NSAttributedString *)attributedItem:(NSString *)item selected:(BOOL)selected {
    NSFont *bold = [[NSFontManager sharedFontManager] convertFont:self.font toHaveTrait:NSBoldFontMask];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:item attributes:@{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: selected ? [NSColor alternateSelectedControlTextColor] : [NSColor secondaryLabelColor],
    }];
    NSRange r = self.partial.length > 0 ? [item rangeOfString:self.partial options:NSCaseInsensitiveSearch] : NSMakeRange(NSNotFound, 0);
    if (r.location != NSNotFound) {
        [s addAttributes:@{NSFontAttributeName: bold, NSForegroundColorAttributeName: selected ? [NSColor alternateSelectedControlTextColor] : [NSColor labelColor]} range:r];
    }
    return s;
}

@end
