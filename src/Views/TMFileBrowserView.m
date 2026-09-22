#import "TMFileBrowserView.h"
#import "TMProject.h"

@interface TMFileBrowserView () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@property (nonatomic, strong, readwrite, nullable) NSURL *rootDirectoryURL;
@property (nonatomic, copy) NSArray<TMFileNode *> *rootNodes;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSTextField *rootLabel;
@property (nonatomic, strong) NSView *emptyView;
@property (nonatomic, assign) BOOL isProgrammaticSelection;
@property (nonatomic, strong, nullable) NSURL *selectedFileURL;
@end

@implementation TMFileBrowserView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _rootNodes = @[];
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 根目录名（点击可在访达中打开）
    _rootLabel = [NSTextField labelWithString:@""];
    _rootLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _rootLabel.textColor = [NSColor secondaryLabelColor];
    _rootLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _rootLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_rootLabel];

    _scrollView = [[NSScrollView alloc] init];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers = YES;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_scrollView];

    _outlineView = [[NSOutlineView alloc] initWithFrame:_scrollView.bounds];
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 22.0;
    _outlineView.indentationPerLevel = 12.0;
    _outlineView.style = NSTableViewStyleSourceList;
    _outlineView.autoresizesOutlineColumn = YES;
    _outlineView.target = self;
    _outlineView.action = @selector(outlineClicked:);
    _outlineView.doubleAction = @selector(outlineDoubleClicked:);

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"FileColumn"];
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:column];
    _outlineView.outlineTableColumn = column;
    _scrollView.documentView = _outlineView;

    // 空态
    _emptyView = [[NSView alloc] init];
    _emptyView.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_emptyView];
    NSTextField *emptyTitle = [NSTextField labelWithString:@"尚未打开文件夹"];
    emptyTitle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    emptyTitle.textColor = [NSColor secondaryLabelColor];
    emptyTitle.alignment = NSTextAlignmentCenter;
    emptyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:emptyTitle];
    NSTextField *emptyDesc = [NSTextField labelWithString:@"打开或保存一个 .tex 文件后\n其所在文件夹会显示在这里"];
    emptyDesc.font = [NSFont systemFontOfSize:11];
    emptyDesc.textColor = [NSColor tertiaryLabelColor];
    emptyDesc.alignment = NSTextAlignmentCenter;
    emptyDesc.translatesAutoresizingMaskIntoConstraints = NO;
    [_emptyView addSubview:emptyDesc];

    [NSLayoutConstraint activateConstraints:@[
        [_rootLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
        [_rootLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_rootLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],

        [_scrollView.topAnchor constraintEqualToAnchor:_rootLabel.bottomAnchor constant:4],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_emptyView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_emptyView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_emptyView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_emptyView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [emptyTitle.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [emptyTitle.centerYAnchor constraintEqualToAnchor:_emptyView.centerYAnchor constant:-20],
        [emptyDesc.centerXAnchor constraintEqualToAnchor:_emptyView.centerXAnchor],
        [emptyDesc.topAnchor constraintEqualToAnchor:emptyTitle.bottomAnchor constant:6]
    ]];

    [self updateEmptyState];
}

#pragma mark - 数据

- (void)setRootDirectoryURL:(nullable NSURL *)url {
    _rootDirectoryURL = url.URLByStandardizingPath;
    self.rootLabel.stringValue = url ? url.lastPathComponent : @"";
    self.rootLabel.toolTip = url.path;
    [self reload];
}

- (void)reload {
    // 记录展开的目录，reload 后恢复
    NSMutableSet<NSString *> *expanded = [NSMutableSet set];
    for (TMFileNode *n in [self allNodes:self.rootNodes]) {
        if (n.isDirectory && [self.outlineView isItemExpanded:n]) [expanded addObject:n.url.path];
    }

    self.rootNodes = self.rootDirectoryURL ? [TMProject fileTreeForDirectory:self.rootDirectoryURL maxDepth:4] : @[];
    [self.outlineView reloadData];

    for (TMFileNode *n in [self allNodes:self.rootNodes]) {
        if (n.isDirectory && [expanded containsObject:n.url.path]) [self.outlineView expandItem:n];
    }
    // 首次载入：只有一层目录时默认展开，方便看到 chapters/ 里的文件
    if (expanded.count == 0) {
        for (TMFileNode *n in self.rootNodes) {
            if (n.isDirectory && n.children.count <= 12) [self.outlineView expandItem:n];
        }
    }

    [self updateEmptyState];
    [self selectFileURL:self.selectedFileURL];
}

- (NSArray<TMFileNode *> *)allNodes:(NSArray<TMFileNode *> *)nodes {
    NSMutableArray *result = [NSMutableArray array];
    for (TMFileNode *n in nodes) {
        [result addObject:n];
        if (n.children.count) [result addObjectsFromArray:[self allNodes:n.children]];
    }
    return result;
}

- (void)updateEmptyState {
    BOOL empty = self.rootDirectoryURL == nil;
    self.emptyView.hidden = !empty;
    self.scrollView.hidden = empty;
    self.rootLabel.hidden = empty;
}

- (void)selectFileURL:(nullable NSURL *)url {
    self.selectedFileURL = url;
    if (!url) {
        self.isProgrammaticSelection = YES;
        [self.outlineView deselectAll:nil];
        self.isProgrammaticSelection = NO;
        return;
    }
    NSString *target = url.URLByStandardizingPath.path;
    for (TMFileNode *n in [self allNodes:self.rootNodes]) {
        if (n.isDirectory || ![n.url.URLByStandardizingPath.path isEqualToString:target]) continue;
        // 展开祖先
        TMFileNode *parent = [self.outlineView parentForItem:n];
        NSMutableArray *chain = [NSMutableArray array];
        while (parent) { [chain insertObject:parent atIndex:0]; parent = [self.outlineView parentForItem:parent]; }
        for (TMFileNode *p in chain) [self.outlineView expandItem:p];

        NSInteger row = [self.outlineView rowForItem:n];
        if (row >= 0) {
            self.isProgrammaticSelection = YES;
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            [self.outlineView scrollRowToVisible:row];
            self.isProgrammaticSelection = NO;
        }
        return;
    }
}

#pragma mark - 交互

- (void)outlineClicked:(id)sender {
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0) return;
    TMFileNode *node = [self.outlineView itemAtRow:row];
    if (!node || node.isDirectory) return;
    if ([TMProject isEditableFileURL:node.url]) {
        self.selectedFileURL = node.url;
        if ([self.delegate respondsToSelector:@selector(fileBrowserView:didSelectFileURL:)]) {
            [self.delegate fileBrowserView:self didSelectFileURL:node.url];
        }
    } else {
        // 图片 / pdf：在系统默认应用中打开
        [[NSWorkspace sharedWorkspace] openURL:node.url];
        [self selectFileURL:self.selectedFileURL];
    }
}

- (void)outlineDoubleClicked:(id)sender {
    NSInteger row = self.outlineView.clickedRow;
    if (row < 0) return;
    TMFileNode *node = [self.outlineView itemAtRow:row];
    if (node.isDirectory) {
        if ([self.outlineView isItemExpanded:node]) [self.outlineView collapseItem:node];
        else [self.outlineView expandItem:node];
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    return item ? [(TMFileNode *)item children].count : self.rootNodes.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    return item ? [(TMFileNode *)item children][index] : self.rootNodes[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [(TMFileNode *)item isDirectory];
}

#pragma mark - NSOutlineViewDelegate

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    static NSString *cellID = @"TMFileCell";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:cellID owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 200, 22)];
        cell.identifier = cellID;
        NSImageView *icon = [[NSImageView alloc] init];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:icon];
        cell.imageView = icon;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.font = [NSFont systemFontOfSize:12];
        label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [icon.widthAnchor constraintEqualToConstant:16],
            [icon.heightAnchor constraintEqualToConstant:16],
            [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:5],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    TMFileNode *node = item;
    cell.textField.stringValue = node.name;
    cell.textField.textColor = (node.isDirectory || [TMProject isEditableFileURL:node.url]) ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    cell.imageView.image = [self iconForNode:node];
    return cell;
}

- (NSImage *)iconForNode:(TMFileNode *)node {
    NSString *symbol;
    NSColor *tint = [NSColor secondaryLabelColor];
    if (node.isDirectory) {
        symbol = @"folder";
        tint = [NSColor systemBlueColor];
    } else {
        NSString *ext = node.url.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"tex"] || [ext isEqualToString:@"latex"] || [ext isEqualToString:@"ltx"]) {
            symbol = @"doc.text"; tint = [NSColor controlAccentColor];
        } else if ([ext isEqualToString:@"bib"]) {
            symbol = @"books.vertical"; tint = [NSColor systemPurpleColor];
        } else if ([ext isEqualToString:@"sty"] || [ext isEqualToString:@"cls"] || [ext isEqualToString:@"bst"] || [ext isEqualToString:@"dtx"]) {
            symbol = @"gearshape"; tint = [NSColor systemGrayColor];
        } else if ([@[@"png", @"jpg", @"jpeg", @"eps", @"svg"] containsObject:ext]) {
            symbol = @"photo"; tint = [NSColor systemGreenColor];
        } else if ([ext isEqualToString:@"pdf"]) {
            symbol = @"doc.richtext"; tint = [NSColor systemRedColor];
        } else {
            symbol = @"doc.plaintext";
        }
    }
    NSImage *img = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil];
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPaletteColors:@[tint]];
    return [img imageWithSymbolConfiguration:cfg] ?: img;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    return ![(TMFileNode *)item isDirectory];
}

@end
