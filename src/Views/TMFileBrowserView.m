#import "TMFileBrowserView.h"
#import "TMProject.h"

@interface TMFileBrowserView () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@property (nonatomic, strong, readwrite, nullable) NSURL *rootDirectoryURL;
@property (nonatomic, copy) NSArray<TMFileNode *> *rootNodes;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSTextField *rootLabel;
@property (nonatomic, strong) NSView *emptyView;
@property (nonatomic, assign) BOOL isProgrammaticSelection;
@property (nonatomic, strong, nullable) NSURL *selectedFileURL;
/// 右键菜单弹出时点中的节点；nil 表示空白处（按根目录处理）。
@property (nonatomic, strong, nullable) TMFileNode *contextNode;
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

    NSMenu *contextMenu = [[NSMenu alloc] initWithTitle:@"文件"];
    contextMenu.delegate = self;
    _outlineView.menu = contextMenu;

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

#pragma mark - 右键菜单

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    if (!self.rootDirectoryURL) return;
    NSInteger row = self.outlineView.clickedRow;
    self.contextNode = row >= 0 ? [self.outlineView itemAtRow:row] : nil;

    NSMenuItem *item;
    item = [menu addItemWithTitle:@"新建 .tex 文件…" action:@selector(newTeXFileAction:) keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:@"新建 .bib 文件…" action:@selector(newBibFileAction:) keyEquivalent:@""];
    item.target = self;
    item = [menu addItemWithTitle:@"新建文件夹…" action:@selector(newFolderAction:) keyEquivalent:@""];
    item.target = self;

    if (self.contextNode) {
        [menu addItem:[NSMenuItem separatorItem]];
        item = [menu addItemWithTitle:@"重命名…" action:@selector(renameAction:) keyEquivalent:@""];
        item.target = self;
        item = [menu addItemWithTitle:@"在访达中显示" action:@selector(revealAction:) keyEquivalent:@""];
        item.target = self;
        [menu addItem:[NSMenuItem separatorItem]];
        item = [menu addItemWithTitle:@"移到废纸篓" action:@selector(trashAction:) keyEquivalent:@""];
        item.target = self;
    } else {
        [menu addItem:[NSMenuItem separatorItem]];
        item = [menu addItemWithTitle:@"在访达中显示项目文件夹" action:@selector(revealAction:) keyEquivalent:@""];
        item.target = self;
    }
}

/// 新建项放在：点中的目录 / 点中文件的所在目录 / 根目录。
- (NSURL *)directoryForNewItems {
    TMFileNode *node = self.contextNode;
    if (!node) return self.rootDirectoryURL;
    return node.isDirectory ? node.url : node.url.URLByDeletingLastPathComponent;
}

- (nullable NSString *)promptForNameWithTitle:(NSString *)title message:(NSString *)message defaultName:(NSString *)defaultName {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"好"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.stringValue = defaultName;
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    // 选中扩展名之前的部分，方便直接输入新名字
    dispatch_async(dispatch_get_main_queue(), ^{
        NSText *editor = [field currentEditor];
        NSUInteger dot = [defaultName rangeOfString:@"." options:NSBackwardsSearch].location;
        if (editor) [editor setSelectedRange:NSMakeRange(0, dot == NSNotFound ? defaultName.length : dot)];
    });
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0 || [name containsString:@"/"] || [name isEqualToString:@"."] || [name isEqualToString:@".."]) {
        NSBeep();
        return nil;
    }
    return name;
}

- (void)showError:(NSError *)error fallback:(NSString *)fallback {
    NSAlert *alert = error ? [NSAlert alertWithError:error] : [[NSAlert alloc] init];
    if (!error) alert.messageText = fallback;
    [alert runModal];
}

- (void)createFileWithExtension:(NSString *)ext initialContent:(NSString *)content {
    NSURL *dir = [self directoryForNewItems];
    NSString *name = [self promptForNameWithTitle:[NSString stringWithFormat:@"新建 .%@ 文件", ext]
                                          message:[NSString stringWithFormat:@"将创建在 %@", dir.lastPathComponent]
                                      defaultName:[@"untitled" stringByAppendingPathExtension:ext]];
    if (!name) return;
    if (![name.pathExtension.lowercaseString isEqualToString:ext]) name = [name stringByAppendingPathExtension:ext];
    NSURL *url = [dir URLByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        [self showError:nil fallback:[NSString stringWithFormat:@"“%@” 已存在", name]];
        return;
    }
    NSError *err = nil;
    if (![content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        [self showError:err fallback:@"无法创建文件"];
        return;
    }
    [self reload];
    [self selectFileURL:url];
    if ([self.delegate respondsToSelector:@selector(fileBrowserView:didCreateFileURL:)]) {
        [self.delegate fileBrowserView:self didCreateFileURL:url];
    }
}

- (void)newTeXFileAction:(id)sender {
    [self createFileWithExtension:@"tex" initialContent:@""];
}

- (void)newBibFileAction:(id)sender {
    [self createFileWithExtension:@"bib" initialContent:@""];
}

- (void)newFolderAction:(id)sender {
    NSURL *dir = [self directoryForNewItems];
    NSString *name = [self promptForNameWithTitle:@"新建文件夹" message:[NSString stringWithFormat:@"将创建在 %@", dir.lastPathComponent] defaultName:@"新建文件夹"];
    if (!name) return;
    NSError *err = nil;
    NSURL *url = [dir URLByAppendingPathComponent:name isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&err]) {
        [self showError:err fallback:@"无法创建文件夹"];
        return;
    }
    [self reload];
    for (TMFileNode *n in [self allNodes:self.rootNodes]) {
        if (n.isDirectory && [n.url.URLByStandardizingPath.path isEqualToString:url.URLByStandardizingPath.path]) {
            [self.outlineView expandItem:n];
            break;
        }
    }
}

- (void)renameAction:(id)sender {
    TMFileNode *node = self.contextNode;
    if (!node) return;
    NSString *name = [self promptForNameWithTitle:@"重命名" message:@"输入新的名字：" defaultName:node.name];
    if (!name || [name isEqualToString:node.name]) return;
    NSURL *newURL = [node.url.URLByDeletingLastPathComponent URLByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:newURL.path]) {
        [self showError:nil fallback:[NSString stringWithFormat:@"“%@” 已存在", name]];
        return;
    }
    NSError *err = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:node.url toURL:newURL error:&err]) {
        [self showError:err fallback:@"无法重命名"];
        return;
    }
    if ([self.delegate respondsToSelector:@selector(fileBrowserView:didRenameItemAtURL:toURL:)]) {
        [self.delegate fileBrowserView:self didRenameItemAtURL:node.url toURL:newURL];
    }
    [self reload];
}

- (void)revealAction:(id)sender {
    NSURL *url = self.contextNode ? self.contextNode.url : self.rootDirectoryURL;
    if (url) [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
}

- (void)trashAction:(id)sender {
    TMFileNode *node = self.contextNode;
    if (!node) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"把“%@”移到废纸篓？", node.name];
    alert.informativeText = node.isDirectory ? @"文件夹及其中的全部内容都会被移到废纸篓。" : @"可以在废纸篓里找回。";
    [alert addButtonWithTitle:@"移到废纸篓"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSError *err = nil;
    if (![[NSFileManager defaultManager] trashItemAtURL:node.url resultingItemURL:nil error:&err]) {
        [self showError:err fallback:@"无法移到废纸篓"];
        return;
    }
    if ([self.delegate respondsToSelector:@selector(fileBrowserView:didTrashItemAtURL:)]) {
        [self.delegate fileBrowserView:self didTrashItemAtURL:node.url];
    }
    [self reload];
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
