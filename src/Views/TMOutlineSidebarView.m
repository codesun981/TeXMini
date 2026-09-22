#import "TMOutlineSidebarView.h"
#import "TMOutlineParser.h"

// 内部自定义大纲 Cell
@interface TMOutlineCellView : NSTableCellView

@property (nonatomic, strong) NSTextField *badgeField;
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextField *lineField;

- (void)configureWithItem:(TMOutlineItem *)item;

@end

@implementation TMOutlineCellView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        // 1. 层级小徽标 (H1, H2, H3 等)
        _badgeField = [NSTextField labelWithString:@""];
        _badgeField.font = [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightBold];
        _badgeField.textColor = [NSColor secondaryLabelColor];
        _badgeField.alignment = NSTextAlignmentCenter;
        _badgeField.wantsLayer = YES;
        _badgeField.layer.cornerRadius = 3.0;
        _badgeField.layer.masksToBounds = YES;
        _badgeField.layer.backgroundColor = [NSColor quaternaryLabelColor].CGColor;
        _badgeField.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_badgeField];

        // 2. 行号提示 (右侧微弱显示)
        _lineField = [NSTextField labelWithString:@""];
        _lineField.font = [NSFont monospacedSystemFontOfSize:9.5 weight:NSFontWeightRegular];
        _lineField.textColor = [NSColor tertiaryLabelColor];
        _lineField.alignment = NSTextAlignmentRight;
        _lineField.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_lineField];

        // 3. 标题文本
        _titleField = [NSTextField labelWithString:@""];
        _titleField.lineBreakMode = NSLineBreakByTruncatingTail;
        _titleField.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_titleField];

        [NSLayoutConstraint activateConstraints:@[
            [_badgeField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
            [_badgeField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_badgeField.widthAnchor constraintEqualToConstant:24],
            [_badgeField.heightAnchor constraintEqualToConstant:15],

            [_lineField.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [_lineField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_lineField.widthAnchor constraintGreaterThanOrEqualToConstant:24],

            [_titleField.leadingAnchor constraintEqualToAnchor:_badgeField.trailingAnchor constant:6],
            [_titleField.trailingAnchor constraintEqualToAnchor:_lineField.leadingAnchor constant:-4],
            [_titleField.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
    }
    return self;
}

- (void)configureWithItem:(TMOutlineItem *)item {
    self.badgeField.stringValue = item.badgeText ?: @"";
    self.titleField.stringValue = item.title ?: @"";
    self.lineField.stringValue = [NSString stringWithFormat:@"%ld", (long)item.lineNumber];

    // 根据层级应用不同字号与颜色
    if (item.level <= TMOutlineLevelSection) {
        self.titleField.font = [NSFont systemFontOfSize:12.5 weight:NSFontWeightMedium];
        self.titleField.textColor = [NSColor labelColor];
        self.badgeField.textColor = [NSColor controlAccentColor];
        self.badgeField.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.15].CGColor;
    } else if (item.level == TMOutlineLevelSubsection) {
        self.titleField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
        self.titleField.textColor = [NSColor labelColor];
        self.badgeField.textColor = [NSColor secondaryLabelColor];
        self.badgeField.layer.backgroundColor = [NSColor quaternaryLabelColor].CGColor;
    } else {
        self.titleField.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
        self.titleField.textColor = [NSColor secondaryLabelColor];
        self.badgeField.textColor = [NSColor tertiaryLabelColor];
        self.badgeField.layer.backgroundColor = [NSColor quaternaryLabelColor].CGColor;
    }
}

@end

#pragma mark - TMOutlineSidebarView

@interface TMOutlineSidebarView () <NSOutlineViewDelegate, NSOutlineViewDataSource>

@property (nonatomic, strong) NSView *headerView;
@property (nonatomic, strong) NSSegmentedControl *modeControl;
@property (nonatomic, strong) NSTextField *countBadgeLabel;
@property (nonatomic, strong) NSButton *toggleButton;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSView *emptyView;
@property (nonatomic, strong, readwrite) TMFileBrowserView *fileBrowserView;

@property (nonatomic, copy, readwrite) NSArray<TMOutlineItem *> *rootItems;
@property (nonatomic, copy, readwrite) NSArray<TMOutlineItem *> *flatItems;

@property (nonatomic, assign) BOOL isProgrammaticSelection;

@end

static NSString *const kTMDefaultsSidebarMode = @"TMSidebarMode";

@implementation TMOutlineSidebarView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _rootItems = @[];
        _flatItems = @[];
        _isProgrammaticSelection = NO;

        [self setupMaterial];
        [self setupHeader];
        [self setupOutlineView];
        [self setupEmptyView];
        [self setupFileBrowser];

        NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kTMDefaultsSidebarMode];
        _mode = -1; // 强制 setter 生效
        self.mode = (saved == TMSidebarModeFiles) ? TMSidebarModeFiles : TMSidebarModeOutline;
    }
    return self;
}

- (void)setupMaterial {
    self.material = NSVisualEffectMaterialSidebar;
    self.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.state = NSVisualEffectStateFollowsWindowActiveState;
    self.wantsLayer = YES;
}

- (void)setupHeader {
    _headerView = [[NSView alloc] init];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_headerView];

    _modeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"大纲", @"文件"]
                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                           target:self
                                                           action:@selector(modeControlChanged:)];
    _modeControl.segmentStyle = NSSegmentStyleRounded;
    _modeControl.controlSize = NSControlSizeSmall;
    _modeControl.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_modeControl];

    _countBadgeLabel = [NSTextField labelWithString:@"0 节"];
    _countBadgeLabel.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    _countBadgeLabel.textColor = [NSColor secondaryLabelColor];
    _countBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_countBadgeLabel];

    _toggleButton = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"sidebar.left" accessibilityDescription:@"折叠大纲"]
                                       target:self
                                       action:@selector(toggleButtonClicked:)];
    _toggleButton.bordered = NO;
    _toggleButton.buttonType = NSButtonTypeMomentaryChange;
    _toggleButton.contentTintColor = [NSColor secondaryLabelColor];
    _toggleButton.toolTip = @"收起侧边栏 (⌘1)";
    _toggleButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:_toggleButton];

    NSBox *divider = [[NSBox alloc] init];
    divider.boxType = NSBoxSeparator;
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [_headerView addSubview:divider];

    [NSLayoutConstraint activateConstraints:@[
        [_headerView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:36],

        [_modeControl.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:10],
        [_modeControl.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        [_countBadgeLabel.leadingAnchor constraintEqualToAnchor:_modeControl.trailingAnchor constant:8],
        [_countBadgeLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_countBadgeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_toggleButton.leadingAnchor constant:-4],

        [_toggleButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-8],
        [_toggleButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_toggleButton.widthAnchor constraintEqualToConstant:20],
        [_toggleButton.heightAnchor constraintEqualToConstant:20],

        [divider.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor],
        [divider.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor],
        [divider.bottomAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [divider.heightAnchor constraintEqualToConstant:1]
    ]];
}

- (void)setupFileBrowser {
    _fileBrowserView = [[TMFileBrowserView alloc] init];
    _fileBrowserView.translatesAutoresizingMaskIntoConstraints = NO;
    _fileBrowserView.hidden = YES;
    [self addSubview:_fileBrowserView];
    [NSLayoutConstraint activateConstraints:@[
        [_fileBrowserView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_fileBrowserView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_fileBrowserView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_fileBrowserView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

#pragma mark - 模式切换

- (void)setMode:(TMSidebarMode)mode {
    if (_mode == mode) return;
    _mode = mode;
    self.modeControl.selectedSegment = mode;
    [[NSUserDefaults standardUserDefaults] setInteger:mode forKey:kTMDefaultsSidebarMode];
    [self applyModeVisibility];
}

- (void)modeControlChanged:(NSSegmentedControl *)sender {
    self.mode = (TMSidebarMode)sender.selectedSegment;
}

- (void)applyModeVisibility {
    BOOL files = (self.mode == TMSidebarModeFiles);
    self.fileBrowserView.hidden = !files;
    self.countBadgeLabel.hidden = files;
    if (files) {
        self.scrollView.hidden = YES;
        self.emptyView.hidden = YES;
    } else {
        BOOL empty = self.rootItems.count == 0;
        self.scrollView.hidden = empty;
        self.emptyView.hidden = !empty;
    }
}

- (void)setupOutlineView {
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scrollView];

    _outlineView = [[NSOutlineView alloc] initWithFrame:_scrollView.bounds];
    _outlineView.delegate = self;
    _outlineView.dataSource = self;
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 26.0;
    _outlineView.indentationPerLevel = 14.0;
    _outlineView.autoresizesOutlineColumn = YES;
    _outlineView.style = NSTableViewStyleSourceList;
    _outlineView.target = self;
    _outlineView.action = @selector(outlineViewClicked:);

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"OutlineColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:column];
    _outlineView.outlineTableColumn = column;

    _scrollView.documentView = _outlineView;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)setupEmptyView {
    _emptyView = [[NSView alloc] init];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyView.hidden = YES;
    [self addSubview:_emptyView];

    NSImageView *emptyIcon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:nil]];
    emptyIcon.contentTintColor = [NSColor tertiaryLabelColor];
    emptyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:emptyIcon];

    NSTextField *emptyTitle = [NSTextField labelWithString:@"暂无章节大纲"];
    emptyTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:emptyTitle];

    NSTextField *emptyDesc = [NSTextField labelWithString:@"在 LaTeX 源码中使用 \\section{} 等命令\n即可在此处自动生成结构大纲"];
    emptyDesc.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    emptyDesc.textColor = [NSColor tertiaryLabelColor];
    emptyDesc.alignment = NSTextAlignmentCenter;
    emptyDesc.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:emptyDesc];

    [NSLayoutConstraint activateConstraints:@[
        [_emptyView.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_emptyView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_emptyView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_emptyView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [emptyIcon.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [emptyIcon.centerYAnchor constraintEqualToAnchor:_emptyView.centerYAnchor constant:-30],
        [emptyIcon.widthAnchor constraintEqualToConstant:36],
        [emptyIcon.heightAnchor constraintEqualToConstant:36],

        [emptyTitle.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [emptyTitle.topAnchor constraintEqualToAnchor:emptyIcon.bottomAnchor constant:10],

        [emptyDesc.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [emptyDesc.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:6]
    ]];
}

#pragma mark - 数据更新与刷新

- (void)updateWithRootItems:(NSArray<TMOutlineItem *> *)rootItems
                  flatItems:(NSArray<TMOutlineItem *> *)flatItems {
    self.rootItems = rootItems ?: @[];
    self.flatItems = flatItems ?: @[];

    self.countBadgeLabel.stringValue = [NSString stringWithFormat:@"%lu 节", (unsigned long)self.flatItems.count];

    [self applyModeVisibility];

    [self.outlineView reloadData];

    // 默认展开所有大纲节点，便于一览全局
    [self.outlineView expandItem:nil expandChildren:YES];
}

- (void)highlightItemForLineNumber:(NSInteger)lineNumber {
    if (self.flatItems.count == 0) return;

    TMOutlineItem *active = [TMOutlineParser activeItemForLineNumber:lineNumber inFlatList:self.flatItems];
    if (!active) {
        _isProgrammaticSelection = YES;
        [self.outlineView deselectAll:nil];
        _isProgrammaticSelection = NO;
        return;
    }

    // 展开所有父节点
    TMOutlineItem *curr = active.parent;
    while (curr) {
        if (![self.outlineView isItemExpanded:curr]) {
            [self.outlineView expandItem:curr];
        }
        curr = curr.parent;
    }

    NSInteger row = [self.outlineView rowForItem:active];
    if (row >= 0 && row != self.outlineView.selectedRow) {
        _isProgrammaticSelection = YES;
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [self.outlineView scrollRowToVisible:row];
        _isProgrammaticSelection = NO;
    }
}

#pragma mark - 交互响应

- (void)toggleButtonClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(outlineSidebarViewDidRequestToggle:)]) {
        [self.delegate outlineSidebarViewDidRequestToggle:self];
    }
}

- (void)outlineViewClicked:(id)sender {
    NSInteger clickedRow = self.outlineView.clickedRow;
    if (clickedRow >= 0) {
        TMOutlineItem *item = [self.outlineView itemAtRow:clickedRow];
        if (item && [self.delegate respondsToSelector:@selector(outlineSidebarView:didSelectItem:)]) {
            [self.delegate outlineSidebarView:self didSelectItem:item];
        }
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (_isProgrammaticSelection) return;

    NSInteger selectedRow = self.outlineView.selectedRow;
    if (selectedRow >= 0) {
        TMOutlineItem *item = [self.outlineView itemAtRow:selectedRow];
        if (item && [self.delegate respondsToSelector:@selector(outlineSidebarView:didSelectItem:)]) {
            [self.delegate outlineSidebarView:self didSelectItem:item];
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (item == nil) {
        return self.rootItems.count;
    }
    if ([item isKindOfClass:[TMOutlineItem class]]) {
        return [(TMOutlineItem *)item children].count;
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (item == nil) {
        return self.rootItems[index];
    }
    if ([item isKindOfClass:[TMOutlineItem class]]) {
        return [(TMOutlineItem *)item children][index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if ([item isKindOfClass:[TMOutlineItem class]]) {
        return [(TMOutlineItem *)item children].count > 0;
    }
    return NO;
}

#pragma mark - NSOutlineViewDelegate

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    static NSString *cellID = @"TMOutlineCellView";
    TMOutlineCellView *cell = [outlineView makeViewWithIdentifier:cellID owner:self];
    if (!cell) {
        cell = [[TMOutlineCellView alloc] initWithFrame:NSMakeRect(0, 0, outlineView.bounds.size.width, 26)];
        cell.identifier = cellID;
    }
    if ([item isKindOfClass:[TMOutlineItem class]]) {
        [cell configureWithItem:(TMOutlineItem *)item];
    }
    return cell;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return YES;
}

@end
