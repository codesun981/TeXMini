#import "TMMainWindowController.h"
#import "TMEditorTextView.h"
#import "TMLineNumberRulerView.h"
#import "TMPDFView.h"
#import "TMStatusBarView.h"
#import "TMLogDrawerView.h"
#import "TMCompiler.h"
#import "TMWordCounter.h"
#import "TMSyncTeX.h"
#import "TMOutlineSidebarView.h"
#import "TMOutlineParser.h"
#import "TMRecentFiles.h"
#import "TMProject.h"
#import "TMFileWatcher.h"
#import "TMPreferences.h"
#import "TMLaTeXHighlighter.h"
#import "TMEditActions.h"
#import "TMFontFixController.h"
#import "TMTemplatePicker.h"
#import "TMWelcomeView.h"
#import "TMPreferencesWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kTMDefaultsOutlineCollapsed = @"TMOutlineCollapsed";
static const CGFloat kTMDividerHandleWidth = 10.0;

/// 盖在 代码|PDF 分隔线上的透明拖动条。
/// 只靠 effectiveRect 扩大热区不够：编辑器的滚动条、文本视图的 I 形光标、PDFView 都会抢走
/// 分隔线旁边的点击和光标。这个视图是分栏的兄弟且在最上层，光标和拖动都一定先落到它身上。
@interface TMSplitDividerHandle : NSView
@property (nonatomic, weak) NSSplitView *splitView;
@end

@implementation TMSplitDividerHandle
- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor resizeLeftRightCursor]];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSSplitView *splitView = self.splitView;
    if (splitView.subviews.count < 2) return;
    // 按下点与分隔线的偏移，拖动时保持不变，避免一按下分隔线就跳到指针处
    CGFloat grabOffset = [splitView convertPoint:event.locationInWindow fromView:nil].x - NSMaxX(splitView.subviews[0].frame);
    [[NSCursor resizeLeftRightCursor] push];
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) break;
        CGFloat x = [splitView convertPoint:next.locationInWindow fromView:nil].x - grabOffset;
        CGFloat minX = [splitView.delegate splitView:splitView constrainMinCoordinate:0 ofSubviewAt:0];
        CGFloat maxX = [splitView.delegate splitView:splitView constrainMaxCoordinate:0 ofSubviewAt:0];
        [splitView setPosition:MAX(minX, MIN(x, maxX)) ofDividerAtIndex:0];
    }
    [NSCursor pop];
    [self.window invalidateCursorRectsForView:self];
}

- (void)mouseDragged:(NSEvent *)event {}
@end

@interface TMMainWindowController () <TMWelcomeViewDelegate, NSToolbarDelegate, NSSplitViewDelegate, TMEditorTextViewDelegate, TMPDFViewDelegate, TMCompilerDelegate, TMStatusBarViewDelegate, TMOutlineSidebarViewDelegate, TMFileBrowserViewDelegate, TMLogDrawerViewDelegate, TMFontFixHost>

// 外层：系统 NSSplitViewController 负责侧边栏折叠、分割线隐藏、宽度记忆
@property (nonatomic, strong) NSSplitViewController *mainSplitViewController;
@property (nonatomic, strong) NSSplitViewItem *sidebarItem;
@property (nonatomic, strong) TMOutlineSidebarView *outlineSidebarView;
// 内层：代码 | PDF
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) TMSplitDividerHandle *dividerHandle;
@property (nonatomic, strong) TMEditorTextView *editorTextView;
@property (nonatomic, strong) NSScrollView *editorScrollView;
@property (nonatomic, strong) TMLineNumberRulerView *lineNumberRuler;
/// 最近一次编译解析出的问题，切换文件时据此重画行号槽标记。
@property (nonatomic, copy) NSArray<TMLogIssue *> *lastIssues;
@property (nonatomic, strong) NSView *pdfContainerView;
@property (nonatomic, strong) TMPDFView *pdfView;
@property (nonatomic, strong) NSView *pdfPlaceholderView;
// PDF 内查找栏
@property (nonatomic, strong) NSView *pdfSearchBar;
@property (nonatomic, strong) NSSearchField *pdfSearchField;
@property (nonatomic, strong) NSTextField *pdfSearchCountLabel;
@property (nonatomic, copy) NSArray<PDFSelection *> *pdfSearchResults;
@property (nonatomic, assign) NSInteger pdfSearchIndex;
@property (nonatomic, strong) TMStatusBarView *statusBar;
@property (nonatomic, strong) TMLogDrawerView *logDrawer;
@property (nonatomic, strong) TMWelcomeView *welcomeView;

@property (nonatomic, assign) NSInteger currentCursorLine;
@property (nonatomic, assign) NSInteger currentCursorCol;
@property (nonatomic, strong, nullable) NSTimer *outlineDebounceTimer;
@property (nonatomic, strong, nullable) NSTimer *autoCompileTimer;
@property (nonatomic, strong, nullable) NSTimer *autoSaveTimer;
@property (nonatomic, strong) TMWordCounter *wordCounter;
/// 本次编译是“检测到旧辅助文件 → 自动清理”后的重试：再失败就不再清理，照常报错。
@property (nonatomic, assign) BOOL isRetryingAfterAutoClean;
/// 自动清理后重编仍失败的“主文件|辅助文件”：清理对它们没用，本次会话不再自动清理。
@property (nonatomic, strong) NSMutableSet<NSString *> *unhelpfulAutoCleans;
/// 状态栏“编译目标 · 引擎”的后台判断代次。
@property (nonatomic, assign) NSUInteger compileTargetGeneration;
/// 标题 1 对应 \chapter（book / report / 学位论文类）还是 \section；随编译目标一起在后台判断。
@property (nonatomic, assign) BOOL headingUsesChapters;
@property (nonatomic, assign) BOOL needsCompileAfterCurrent;
@property (nonatomic, strong, readwrite, nullable) NSURL *currentPDFURL;
@property (nonatomic, strong, readwrite, nullable) NSURL *projectRootURL;
@property (nonatomic, strong) TMCompletionProvider *completionProvider;
@property (nonatomic, strong, nullable) TMFileWatcher *fileWatcher;
/// 上次我们自己读 / 写磁盘文件时的修改时间，用来判断是否有外部改动。
@property (nonatomic, strong, nullable) NSDate *knownModificationDate;
@property (nonatomic, assign) BOOL isShowingExternalChangeAlert;
@property (nonatomic, strong, nullable) NSURL *scratchDirectoryURL;
@property (nonatomic, strong, nullable) TMFontFixController *fontFix;

@end

@implementation TMMainWindowController

- (instancetype)initWithDocument:(TMDocument *)document {
    return [self initWithDocument:document loadsDocument:YES];
}

- (instancetype)initForSessionRestore {
    return [self initWithDocument:[TMDocument documentWithBlankTemplate] loadsDocument:NO];
}

- (instancetype)initWithDocument:(TMDocument *)document loadsDocument:(BOOL)loadsDocument {
    NSRect screenRect = [NSScreen mainScreen].visibleFrame;
    CGFloat winWidth = MIN(1300.0, screenRect.size.width - 100);
    CGFloat winHeight = MIN(860.0, screenRect.size.height - 100);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, winWidth, winHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window center];
    window.minSize = NSMakeSize(750, 500);

    self = [super initWithWindow:window];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        _documentModel = document ?: [TMDocument documentWithDefaultTemplate];
        _currentCursorLine = 1;
        _currentCursorCol = 1;
        _unhelpfulAutoCleans = [NSMutableSet set];
        _wordCounter = [[TMWordCounter alloc] init];
        _autoCompileEnabled = [TMPreferences shared].autoCompileEnabled;
        window.delegate = self;

        [self setupUI];
        [self setupToolbar];
        [TMCompiler sharedCompiler].delegate = self;
        [self applyPreferences];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencesDidChange:)
                                                     name:TMPreferencesDidChangeNotification
                                                   object:nil];
        if (loadsDocument) [self loadDocumentIntoEditor];

        // 侧边栏折叠状态：等 UI 建好后再应用，避免动画
        self.sidebarItem.collapsed = [defaults boolForKey:kTMDefaultsOutlineCollapsed];

        // 窗口位置/大小交给系统自动保存
        [window setFrameAutosaveName:@"TMMainWindow"];
    }
    return self;
}

/// 未保存文档的暂存位置。每个窗口一个独立目录，两个未命名窗口不会互相覆盖。
- (NSURL *)scratchFileURLNamed:(NSString *)name {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TeXMini"];
    // 本进程第一次用暂存目录时，清掉上次退出或崩溃没来得及删的（同一时间只有一个 TeXMini 在跑）
    static dispatch_once_t sweepOnce;
    dispatch_once(&sweepOnce, ^{
        for (NSString *stale in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:nil]) {
            NSString *path = [root stringByAppendingPathComponent:stale];
            for (NSString *tex in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil]) {
                if ([tex.pathExtension isEqualToString:@"tex"]) {
                    [self removeBuildCacheForTeXFileURL:[NSURL fileURLWithPath:[path stringByAppendingPathComponent:tex]]];
                }
            }
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        }
    });
    if (!self.scratchDirectoryURL) {
        NSString *dir = [root stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        self.scratchDirectoryURL = [NSURL fileURLWithPath:dir isDirectory:YES];
    }
    return [self.scratchDirectoryURL URLByAppendingPathComponent:name];
}

- (void)removeBuildCacheForTeXFileURL:(NSURL *)texURL {
    [[NSFileManager defaultManager] removeItemAtURL:[TMCompiler auxiliaryDirectoryForTeXFileURL:texURL] error:nil];
}

/// 关窗时删掉这个窗口的暂存目录，以及其中 .tex 在缓存里对应的中间文件目录
- (void)removeScratchDirectory {
    NSURL *dir = self.scratchDirectoryURL;
    if (!dir) return;
    for (NSURL *file in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:dir includingPropertiesForKeys:nil options:0 error:nil]) {
        if ([file.pathExtension isEqualToString:@"tex"]) [self removeBuildCacheForTeXFileURL:file];
    }
    [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
    self.scratchDirectoryURL = nil;
}

- (void)setupUI {
    NSView *contentView = self.window.contentView;
    contentView.wantsLayer = YES;
    NSRect bounds = contentView.bounds;

    // 1. 外层分栏交给 NSSplitViewController：左大纲侧边栏 + 右工作区
    _mainSplitViewController = [[NSSplitViewController alloc] init];
    _mainSplitViewController.splitView.vertical = YES;
    _mainSplitViewController.splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _mainSplitViewController.splitView.autosaveName = @"TMMainSplit";
    _mainSplitViewController.view.translatesAutoresizingMaskIntoConstraints = NO;

    // 1.1 大纲侧边栏
    CGFloat sidebarWidth = 220.0;
    _outlineSidebarView = [[TMOutlineSidebarView alloc] initWithFrame:NSMakeRect(0, 0, sidebarWidth, bounds.size.height)];
    _outlineSidebarView.delegate = self;
    _outlineSidebarView.fileBrowserView.delegate = self;
    NSViewController *sidebarVC = [[NSViewController alloc] init];
    sidebarVC.view = _outlineSidebarView;
    _sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarVC];
    _sidebarItem.minimumThickness = 160.0;
    _sidebarItem.maximumThickness = 380.0;
    _sidebarItem.canCollapse = YES;
    _sidebarItem.collapseBehavior = NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings;
    _sidebarItem.holdingPriority = NSLayoutPriorityDefaultHigh;
    [_mainSplitViewController addSplitViewItem:_sidebarItem];

    // 1.2 内层工作区分栏 (ContentSplitView: 代码编辑 + PDF 预览)
    CGFloat contentWidth = MAX(400, bounds.size.width - sidebarWidth - 1.0);
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, contentWidth, bounds.size.height)];
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.delegate = self;
    _splitView.autosaveName = @"TMContentSplit";
    _splitView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat halfWidth = floor((contentWidth - 1.0) / 2.0);
    CGFloat initialHeight = bounds.size.height > 100 ? bounds.size.height - 30 : 600;

    // 1.2.1 代码编辑区 (ScrollView + Ruler + EditorTextView)
    _editorScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, halfWidth, initialHeight)];
    _editorScrollView.hasVerticalScroller = YES;
    _editorScrollView.hasHorizontalScroller = NO;
    _editorScrollView.borderType = NSNoBorder;
    _editorScrollView.hasVerticalRuler = YES;
    _editorScrollView.rulersVisible = YES;
    _editorScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _editorTextView = [[TMEditorTextView alloc] initWithFrame:_editorScrollView.bounds];
    _editorTextView.minSize = NSMakeSize(0.0, _editorScrollView.contentSize.height);
    _editorTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _editorTextView.verticallyResizable = YES;
    _editorTextView.horizontallyResizable = NO;
    _editorTextView.autoresizingMask = NSViewWidthSizable;
    _editorTextView.textContainer.containerSize = NSMakeSize(_editorScrollView.contentSize.width, FLT_MAX);
    _editorTextView.textContainer.widthTracksTextView = YES;
    _editorTextView.editorDelegate = self;
    _editorTextView.delegate = self;
    _completionProvider = [[TMCompletionProvider alloc] init];
    _editorTextView.completionProvider = _completionProvider;
    [_editorTextView setupEditor];

    _editorScrollView.documentView = _editorTextView;

    TMLineNumberRulerView *ruler = [[TMLineNumberRulerView alloc] initWithScrollView:_editorScrollView];
    _editorScrollView.verticalRulerView = ruler;
    _lineNumberRuler = ruler;
    __weak TMEditorTextView *indexedEditor = _editorTextView;
    ruler.lineIndexProvider = ^{ return indexedEditor.lineIndex; };

    [_splitView addSubview:_editorScrollView];

    // 1.2.2 右栏：PDF 预览容器 (含 PDFKit 及占位提示)
    _pdfContainerView = [[NSView alloc] initWithFrame:NSMakeRect(halfWidth + 1.0, 0, halfWidth, initialHeight)];
    _pdfContainerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _pdfContainerView.wantsLayer = YES;
    _pdfContainerView.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;

    _pdfView = [[TMPDFView alloc] initWithFrame:_pdfContainerView.bounds];
    _pdfView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_pdfView setupPDFView];
    _pdfView.syncDelegate = self;
    [_pdfContainerView addSubview:_pdfView];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pdfPageDidChange:) name:PDFViewPageChangedNotification object:_pdfView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pdfPageDidChange:) name:PDFViewDocumentChangedNotification object:_pdfView];

    // 占位视图 (当未编译出 PDF 时显示提示)
    [self setupPlaceholderView];
    [_pdfContainerView addSubview:_pdfPlaceholderView];
    [self setupPDFSearchBar];

    [_splitView addSubview:_pdfContainerView];

    // 将工作区分栏包成 NSSplitViewItem 加入外层
    // 外面再包一层容器，好把拖动条叠在分栏上方
    NSView *contentContainer = [[NSView alloc] initWithFrame:_splitView.frame];
    _splitView.frame = contentContainer.bounds;
    [contentContainer addSubview:_splitView];
    _dividerHandle = [[TMSplitDividerHandle alloc] initWithFrame:NSZeroRect];
    _dividerHandle.splitView = _splitView;
    [contentContainer addSubview:_dividerHandle positioned:NSWindowAbove relativeTo:_splitView];

    NSViewController *contentVC = [[NSViewController alloc] init];
    contentVC.view = contentContainer;
    NSSplitViewItem *contentItem = [NSSplitViewItem splitViewItemWithViewController:contentVC];
    contentItem.minimumThickness = 400.0;
    contentItem.holdingPriority = NSLayoutPriorityDefaultLow;
    [_mainSplitViewController addSplitViewItem:contentItem];

    NSView *mainSplitView = _mainSplitViewController.view;
    [contentView addSubview:mainSplitView];

    // 2. 抽屉式日志视图
    _logDrawer = [[TMLogDrawerView alloc] init];
    _logDrawer.delegate = self;
    _logDrawer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_logDrawer];

    // 3. 底部状态栏
    _statusBar = [[TMStatusBarView alloc] init];
    _statusBar.delegate = self;
    NSMutableArray<NSString *> *styleTitles = [NSMutableArray array];
    for (NSInteger style = TMParagraphStyleBody; style <= TMParagraphStyleQuote; style++) {
        [styleTitles addObject:[TMFormatActions displayNameForParagraphStyle:(TMParagraphStyle)style]];
    }
    [_statusBar setParagraphStyleTitles:styleTitles];
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_statusBar];

    // 1.2 首页：覆盖整个 contentView，处于最顶层，默认隐藏
    _welcomeView = [[TMWelcomeView alloc] initWithFrame:NSZeroRect];
    _welcomeView.delegate = self;
    _welcomeView.hidden = YES;
    _welcomeView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_welcomeView positioned:NSWindowAbove relativeTo:nil];

    // 自动布局约束
    [NSLayoutConstraint activateConstraints:@[
        [mainSplitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainSplitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainSplitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainSplitView.bottomAnchor constraintEqualToAnchor:_logDrawer.topAnchor],

        [_welcomeView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [_welcomeView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_welcomeView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_welcomeView.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],

        [_logDrawer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_logDrawer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_logDrawer.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor],

        [_statusBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_statusBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_statusBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [_statusBar.heightAnchor constraintEqualToConstant:28]
    ]];
}

- (void)setupPlaceholderView {
    _pdfPlaceholderView = [[NSView alloc] initWithFrame:_pdfContainerView.bounds];
    _pdfPlaceholderView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _pdfPlaceholderView.wantsLayer = YES;

    NSImageView *iconView = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"doc.text.magnifyingglass" accessibilityDescription:nil]];
    iconView.contentTintColor = [NSColor secondaryLabelColor];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfPlaceholderView addSubview:iconView];

    NSTextField *titleLabel = [NSTextField labelWithString:@"LaTeX PDF 实时预览"];
    titleLabel.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    titleLabel.textColor = [NSColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfPlaceholderView addSubview:titleLabel];

    NSTextField *subLabel = [NSTextField labelWithString:@"在左侧编辑代码，按 ⌘↩ 自动保存并编译"];
    subLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    subLabel.textColor = [NSColor secondaryLabelColor];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfPlaceholderView addSubview:subLabel];

    NSButton *compileBtn = [NSButton buttonWithTitle:@"▶ 立即编译预览 (⌘↩)" target:self action:@selector(compileCurrentDocument)];
    compileBtn.bezelStyle = NSBezelStyleRounded;
    compileBtn.controlSize = NSControlSizeRegular;
    compileBtn.keyEquivalent = @"\r";
    compileBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfPlaceholderView addSubview:compileBtn];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.centerXAnchor constraintEqualToAnchor:_pdfPlaceholderView.centerXAnchor],
        [iconView.centerYAnchor constraintEqualToAnchor:_pdfPlaceholderView.centerYAnchor constant:-60],
        [iconView.widthAnchor constraintEqualToConstant:64],
        [iconView.heightAnchor constraintEqualToConstant:64],

        [titleLabel.centerXAnchor constraintEqualToAnchor:_pdfPlaceholderView.centerXAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:iconView.bottomAnchor constant:12],

        [subLabel.centerXAnchor constraintEqualToAnchor:_pdfPlaceholderView.centerXAnchor],
        [subLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],

        [compileBtn.centerXAnchor constraintEqualToAnchor:_pdfPlaceholderView.centerXAnchor],
        [compileBtn.topAnchor constraintEqualToAnchor:subLabel.bottomAnchor constant:16]
    ]];
}

- (void)setupToolbar {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"TMMainWindowToolbar"];
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.delegate = self;
    self.window.toolbar = toolbar;
    self.window.toolbarStyle = NSWindowToolbarStyleUnified;
}

#pragma mark - PDF 内查找

static const CGFloat kTMPDFSearchBarHeight = 34.0;

- (void)setupPDFSearchBar {
    NSRect b = _pdfContainerView.bounds;
    _pdfSearchBar = [[NSView alloc] initWithFrame:NSMakeRect(0, NSMaxY(b) - kTMPDFSearchBarHeight, b.size.width, kTMPDFSearchBarHeight)];
    _pdfSearchBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _pdfSearchBar.wantsLayer = YES;
    _pdfSearchBar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    _pdfSearchBar.hidden = YES;

    _pdfSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _pdfSearchField.placeholderString = @"在 PDF 中查找";
    _pdfSearchField.controlSize = NSControlSizeSmall;
    _pdfSearchField.font = [NSFont systemFontOfSize:12];
    _pdfSearchField.sendsSearchStringImmediately = NO;
    _pdfSearchField.sendsWholeSearchString = YES;
    _pdfSearchField.target = self;
    _pdfSearchField.action = @selector(pdfSearchFieldAction:);
    _pdfSearchField.delegate = (id)self;
    _pdfSearchField.translatesAutoresizingMaskIntoConstraints = NO;

    _pdfSearchCountLabel = [NSTextField labelWithString:@""];
    _pdfSearchCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _pdfSearchCountLabel.textColor = [NSColor secondaryLabelColor];
    _pdfSearchCountLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *prev = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:@"上一个"] target:self action:@selector(pdfSearchPreviousAction:)];
    NSButton *next = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:@"下一个"] target:self action:@selector(pdfSearchNextAction:)];
    NSButton *done = [NSButton buttonWithTitle:@"完成" target:self action:@selector(hidePDFSearchBar)];
    for (NSButton *btn in @[prev, next, done]) {
        btn.bezelStyle = NSBezelStyleAccessoryBarAction;
        btn.controlSize = NSControlSizeSmall;
        btn.font = [NSFont systemFontOfSize:11];
        btn.translatesAutoresizingMaskIntoConstraints = NO;
        [_pdfSearchBar addSubview:btn];
    }
    prev.toolTip = @"上一个 (⇧⌘G)";
    next.toolTip = @"下一个 (⌘G)";
    [_pdfSearchBar addSubview:_pdfSearchField];
    [_pdfSearchBar addSubview:_pdfSearchCountLabel];

    NSBox *line = [[NSBox alloc] init];
    line.boxType = NSBoxSeparator;
    line.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfSearchBar addSubview:line];

    [NSLayoutConstraint activateConstraints:@[
        [_pdfSearchField.leadingAnchor constraintEqualToAnchor:_pdfSearchBar.leadingAnchor constant:8],
        [_pdfSearchField.centerYAnchor constraintEqualToAnchor:_pdfSearchBar.centerYAnchor],
        [_pdfSearchField.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [_pdfSearchCountLabel.leadingAnchor constraintEqualToAnchor:_pdfSearchField.trailingAnchor constant:8],
        [_pdfSearchCountLabel.centerYAnchor constraintEqualToAnchor:_pdfSearchBar.centerYAnchor],
        [prev.leadingAnchor constraintEqualToAnchor:_pdfSearchCountLabel.trailingAnchor constant:8],
        [prev.centerYAnchor constraintEqualToAnchor:_pdfSearchBar.centerYAnchor],
        [next.leadingAnchor constraintEqualToAnchor:prev.trailingAnchor constant:2],
        [next.centerYAnchor constraintEqualToAnchor:_pdfSearchBar.centerYAnchor],
        [done.trailingAnchor constraintEqualToAnchor:_pdfSearchBar.trailingAnchor constant:-8],
        [done.centerYAnchor constraintEqualToAnchor:_pdfSearchBar.centerYAnchor],
        [_pdfSearchField.trailingAnchor constraintLessThanOrEqualToAnchor:done.leadingAnchor constant:-120],
        [line.leadingAnchor constraintEqualToAnchor:_pdfSearchBar.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:_pdfSearchBar.trailingAnchor],
        [line.bottomAnchor constraintEqualToAnchor:_pdfSearchBar.bottomAnchor],
        [line.heightAnchor constraintEqualToConstant:1]
    ]];
    [_pdfContainerView addSubview:_pdfSearchBar];
}

- (void)showPDFSearchBar {
    if (!self.pdfView.document) {
        [self.statusBar showInfoMessage:@"还没有 PDF，请先 ⌘↩ 编译"];
        return;
    }
    if (self.pdfSearchBar.hidden) {
        self.pdfSearchBar.hidden = NO;
        NSRect f = self.pdfContainerView.bounds;
        f.size.height -= kTMPDFSearchBarHeight;
        self.pdfView.frame = f;
    }
    [self.window makeFirstResponder:self.pdfSearchField];
    [self.pdfSearchField selectText:nil];
}

- (void)hidePDFSearchBar {
    if (self.pdfSearchBar.hidden) return;
    self.pdfSearchBar.hidden = YES;
    self.pdfView.frame = self.pdfContainerView.bounds;
    self.pdfSearchResults = @[];
    self.pdfView.highlightedSelections = nil;
    [self.window makeFirstResponder:self.pdfView];
}

- (void)pdfViewDidRequestFindInterface {
    [self showPDFSearchBar];
}

- (void)pdfViewDidRequestFindNext:(BOOL)forward {
    if (self.pdfSearchBar.hidden || self.pdfSearchResults.count == 0) { [self showPDFSearchBar]; return; }
    [self stepPDFSearch:forward ? 1 : -1];
}

/// 逐字查找由 controlTextDidChange: 负责，回车由 doCommandBySelector: 负责；
/// 这里只剩点清除按钮（内容清空）的情况。
- (void)pdfSearchFieldAction:(id)sender {
    [self runPDFSearchScrollToFirst:YES];
}

- (void)controlTextDidChange:(NSNotification *)note {
    if (note.object == self.pdfSearchField) [self runPDFSearchScrollToFirst:YES];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control != self.pdfSearchField) return NO;
    if (commandSelector == @selector(cancelOperation:)) { [self hidePDFSearchBar]; return YES; }
    if (commandSelector == @selector(insertNewline:)) {
        NSEvent *ev = NSApp.currentEvent;
        if (self.pdfSearchResults.count == 0) [self runPDFSearchScrollToFirst:YES];
        else [self stepPDFSearch:(ev.modifierFlags & NSEventModifierFlagShift) ? -1 : 1];
        return YES;
    }
    return NO;
}

- (void)runPDFSearchScrollToFirst:(BOOL)scroll {
    NSString *query = self.pdfSearchField.stringValue;
    PDFDocument *doc = self.pdfView.document;
    if (!doc || query.length == 0) {
        self.pdfSearchResults = @[];
        self.pdfView.highlightedSelections = nil;
        self.pdfSearchCountLabel.stringValue = @"";
        return;
    }
    NSArray<PDFSelection *> *results = [doc findString:query withOptions:NSCaseInsensitiveSearch];
    self.pdfSearchResults = results;
    for (PDFSelection *s in results) s.color = [[NSColor systemYellowColor] colorWithAlphaComponent:0.5];
    self.pdfView.highlightedSelections = results;
    self.pdfSearchIndex = -1;
    if (results.count == 0) {
        self.pdfSearchCountLabel.stringValue = @"无结果";
        return;
    }
    if (scroll) {
        // 从当前页开始找第一个命中，而不是总跳回第一页
        PDFPage *current = self.pdfView.currentPage;
        NSUInteger currentIdx = current ? [doc indexForPage:current] : 0;
        NSInteger start = 0;
        for (NSUInteger i = 0; i < results.count; i++) {
            PDFPage *p = results[i].pages.firstObject;
            if (p && [doc indexForPage:p] >= currentIdx) { start = (NSInteger)i; break; }
        }
        self.pdfSearchIndex = start - 1;
        [self stepPDFSearch:1];
    }
}

- (void)stepPDFSearch:(NSInteger)delta {
    NSInteger n = (NSInteger)self.pdfSearchResults.count;
    if (n == 0) return;
    self.pdfSearchIndex = ((self.pdfSearchIndex + delta) % n + n) % n;
    PDFSelection *sel = self.pdfSearchResults[self.pdfSearchIndex];
    self.pdfView.currentSelection = sel;
    [self.pdfView scrollSelectionToVisible:nil];
    self.pdfSearchCountLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)self.pdfSearchIndex + 1, (long)n];
}

- (void)pdfSearchNextAction:(id)sender { [self stepPDFSearch:1]; }
- (void)pdfSearchPreviousAction:(id)sender { [self stepPDFSearch:-1]; }

#pragma mark - 偏好应用

- (void)preferencesDidChange:(NSNotification *)note {
    [self applyPreferences];
}

/// 把 TMPreferences 里的值整体应用到编辑器 / 编译器 / 状态栏。幂等，随时可调。
- (void)applyPreferences {
    TMPreferences *p = [TMPreferences shared];

    NSInteger engine = p.defaultEngine;
    if (engine < TMTeXEngineLatexmk || engine > TMTeXEngineLuaLaTeX) engine = TMTeXEngineLatexmk;
    [TMCompiler sharedCompiler].engine = (TMTeXEngine)engine;
    [TMCompiler sharedCompiler].shellEscapeEnabled = p.shellEscapeEnabled;
    [TMCompiler sharedCompiler].auxFilesBesideSource = p.auxFilesBesideSource;
    [TMCompiler sharedCompiler].extraArguments = [TMPreferences argumentsFromString:p.latexmkExtraArguments];
    [self.statusBar setSelectedEngine:(TMTeXEngine)engine];

    if (![self.editorTextView.editorFontName isEqualToString:p.editorFontName] ||
        fabs(self.editorTextView.editorFontSize - p.editorFontSize) > 0.01) {
        [TMLaTeXHighlighter setBaseFontSize:p.editorFontSize];
        self.editorTextView.editorFontName = p.editorFontName; // 内部会重排 + 重着色
    }
    if (self.editorTextView.softWrapEnabled != p.softWrapEnabled) {
        self.editorTextView.softWrapEnabled = p.softWrapEnabled;
    }
    self.pdfView.inverted = p.pdfInverted;
    self.editorTextView.highlightsCurrentLine = p.highlightsCurrentLine;
    self.outlineSidebarView.combinedMode = p.combinedSidebar;

    _autoCompileEnabled = p.autoCompileEnabled;
    if (!_autoCompileEnabled) {
        [self.autoCompileTimer invalidate];
        self.autoCompileTimer = nil;
    }
    [self refreshCompileTarget];
}

#pragma mark - NSSplitViewDelegate (内层 代码|PDF 分栏，保证永不塌陷)

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    return NO;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return 280.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    return splitView.bounds.size.width - 280.0;
}

/// 细分隔线只有 1pt，几乎抓不住；把可拖动区域向两侧各扩 4pt，光标靠近就会变成左右箭头。
- (NSRect)splitView:(NSSplitView *)splitView effectiveRect:(NSRect)proposedEffectiveRect forDrawnRect:(NSRect)drawnRect ofDividerAtIndex:(NSInteger)dividerIndex {
    return NSInsetRect(drawnRect, -4.0, 0);
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSRect bounds = splitView.bounds;
    CGFloat d = splitView.dividerThickness;
    if (splitView.subviews.count >= 2) {
        NSView *leftView = splitView.subviews[0];
        NSView *rightView = splitView.subviews[1];

        CGFloat leftWidth = leftView.frame.size.width;
        if (leftWidth < 200 || oldSize.width < 200) {
            leftWidth = floor((bounds.size.width - d) * 0.5);
        } else {
            CGFloat ratio = leftWidth / (oldSize.width - d);
            leftWidth = floor((bounds.size.width - d) * ratio);
        }

        leftWidth = MAX(280.0, MIN(leftWidth, bounds.size.width - d - 280.0));
        CGFloat rightWidth = bounds.size.width - d - leftWidth;

        leftView.frame = NSMakeRect(0, 0, leftWidth, bounds.size.height);
        rightView.frame = NSMakeRect(leftWidth + d, 0, rightWidth, bounds.size.height);
    } else {
        [splitView adjustSubviews];
    }
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    NSSplitView *splitView = notification.object;
    if (splitView != self.splitView || splitView.subviews.count < 2) return;
    CGFloat dividerMidX = NSMaxX(splitView.subviews[0].frame) + splitView.dividerThickness / 2.0;
    self.dividerHandle.frame = NSMakeRect(floor(dividerMidX - kTMDividerHandleWidth / 2.0), 0,
                                          kTMDividerHandleWidth, NSHeight(splitView.frame));
    [self.window invalidateCursorRectsForView:self.dividerHandle];
}

#pragma mark - 文档管理与加载

- (void)loadDocumentIntoEditor {
    [self.wordCounter cancel];
    if (self.documentModel) {
        self.editorTextView.completionDocumentKey = self.documentModel.isScratch ? nil : self.documentModel.fileURL.URLByStandardizingPath.path;
        // 先确定新文档语法，只失效扫描缓存，不用新语法重画即将被替换的旧正文。
        TMEditorSyntax syntax = [TMLaTeXHighlighter syntaxForFileURL:self.documentModel.isScratch ? nil : self.documentModel.fileURL];
        [TMLaTeXHighlighter setSyntax:syntax forTextStorage:self.editorTextView.textStorage];
        self.editorTextView.string = self.documentModel.content ?: @"";
        [self.editorTextView.undoManager removeAllActions];
        [self.editorTextView rehighlightAll];
        [self scheduleOutlineUpdateImmediate:YES];
        [self refreshWindowTitle];
        [self syncProjectRootWithDocument];
        [self startWatchingCurrentFile];
        [self refreshIssueMarks];
        [self refreshCompileTarget];
        // 预览主文件的 PDF：编辑 chapters/ch1.tex 时右侧仍应显示 main.pdf
        [self showPDFIfExistsAtURL:[self expectedPDFURLForMainFile]];
        [self hideWelcome];
        [self saveSessionState];
    }
}

- (nullable NSURL *)expectedPDFURLForMainFile {
    NSURL *main = [self mainFileURLForCompile];
    if (!main) return nil;
    NSString *base = main.lastPathComponent.stringByDeletingPathExtension;
    return [main.URLByDeletingLastPathComponent URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"pdf"]];
}

#pragma mark - 项目（文件夹）

/// 文档有正式路径时，让文件浏览器的根目录覆盖它：若当前根已包含该文件则保持不变
/// （在 chapters/ 里切换文件时不应把根跳到子目录），否则用文件所在目录。
- (void)syncProjectRootWithDocument {
    NSURL *fileURL = self.documentModel.fileURL;
    if (!fileURL || self.documentModel.isScratch) {
        // 未命名 / 暂存文档不属于旧项目，避免侧边栏继续显示上一个项目的文件。
        [self setProjectRootURL:nil reload:YES];
        [self.outlineSidebarView.fileBrowserView selectFileURL:nil];
        return;
    }
    NSString *filePath = fileURL.URLByStandardizingPath.path;
    NSString *rootPath = self.projectRootURL.URLByStandardizingPath.path;
    BOOL inside = rootPath && [filePath hasPrefix:[rootPath stringByAppendingString:@"/"]];
    if (!inside) {
        [self setProjectRootURL:fileURL.URLByDeletingLastPathComponent reload:YES];
    } else {
        [self.outlineSidebarView.fileBrowserView reload];
    }
    [self.outlineSidebarView.fileBrowserView selectFileURL:fileURL];
}

- (void)setProjectRootURL:(nullable NSURL *)url reload:(BOOL)reload {
    [self.editorTextView dismissCompletion];
    self.projectRootURL = url.URLByStandardizingPath;
    self.completionProvider.projectRootURL = self.projectRootURL;
    [self.completionProvider invalidate];
    if (reload) [self.outlineSidebarView.fileBrowserView setRootDirectoryURL:self.projectRootURL];
}

#pragma mark - 外部修改检测

- (nullable NSDate *)modificationDateOfCurrentFile {
    NSURL *url = self.documentModel.fileURL;
    if (!url || self.documentModel.isScratch) return nil;
    NSDate *date = nil;
    [url getResourceValue:&date forKey:NSURLContentModificationDateKey error:nil];
    return date;
}

- (void)rememberCurrentFileModificationDate {
    // 清掉 URL 资源缓存，否则可能拿到旧值
    [self.documentModel.fileURL removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    self.knownModificationDate = [self modificationDateOfCurrentFile];
}

- (void)startWatchingCurrentFile {
    [self.fileWatcher stop];
    self.fileWatcher = nil;
    [self rememberCurrentFileModificationDate];
    NSURL *url = self.documentModel.fileURL;
    if (!url || self.documentModel.isScratch) return;
    __weak typeof(self) weakSelf = self;
    self.fileWatcher = [[TMFileWatcher alloc] initWithFileURL:url handler:^{
        [weakSelf checkForExternalModification];
    }];
}

- (void)checkForExternalModification {
    if (self.isShowingExternalChangeAlert) return;
    NSURL *url = self.documentModel.fileURL;
    if (!url || self.documentModel.isScratch) return;
    [url removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    NSDate *onDisk = [self modificationDateOfCurrentFile];
    if (!onDisk) return; // 被删除 / 移动：保留编辑器内容，用户保存时会重新写出
    if (self.knownModificationDate && [onDisk compare:self.knownModificationDate] != NSOrderedDescending) return;

    NSString *diskContent = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (!diskContent) return;
    if ([diskContent isEqualToString:self.editorTextView.string]) {
        // 内容相同（比如 git checkout 回同一版本），只更新时间戳
        self.knownModificationDate = onDisk;
        return;
    }

    if (!self.documentModel.isDirty) {
        [self reloadDocumentFromDiskWithContent:diskContent modificationDate:onDisk];
        [self.statusBar showInfoMessage:[NSString stringWithFormat:@"%@ 已在磁盘上更新，已重新载入", url.lastPathComponent]];
        return;
    }

    self.isShowingExternalChangeAlert = YES;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"文件已在磁盘上被修改";
    alert.informativeText = [NSString stringWithFormat:@"“%@” 被其他程序修改，而编辑器里也有未保存的更改。\n\n重新载入会丢弃编辑器里的更改；保留则下次保存会覆盖磁盘上的版本。", url.lastPathComponent];
    [alert addButtonWithTitle:@"重新载入"];
    [alert addButtonWithTitle:@"保留我的更改"];
    NSModalResponse response = [alert runModal];
    self.isShowingExternalChangeAlert = NO;
    if (response == NSAlertFirstButtonReturn) {
        [self reloadDocumentFromDiskWithContent:diskContent modificationDate:onDisk];
    } else {
        self.knownModificationDate = onDisk; // 不再为同一次改动重复提醒
    }
}

/// 用磁盘内容替换编辑器文本，尽量保住光标与滚动位置。
- (void)reloadDocumentFromDiskWithContent:(NSString *)content modificationDate:(NSDate *)date {
    NSRange sel = self.editorTextView.selectedRange;
    NSRect visible = self.editorScrollView.contentView.bounds;

    self.documentModel.content = content;
    self.documentModel.isDirty = NO;
    self.editorTextView.string = content;
    [self.editorTextView.undoManager removeAllActions];
    [self.editorTextView rehighlightAll];

    NSUInteger loc = MIN(sel.location, content.length);
    [self.editorTextView setSelectedRange:NSMakeRange(loc, 0)];
    [self.editorScrollView.contentView scrollToPoint:visible.origin];
    [self.editorScrollView reflectScrolledClipView:self.editorScrollView.contentView];

    self.knownModificationDate = date;
    [self refreshWindowTitle];
    [self scheduleOutlineUpdateImmediate:YES];
    [self.completionProvider invalidate];
}

- (void)windowDidResignKey:(NSNotification *)notification {
    [self.editorTextView dismissCompletion];
    // 切到别的程序 / 窗口时立刻落盘，不等计时器
    [self.autoSaveTimer invalidate];
    self.autoSaveTimer = nil;
    [self autoSaveIfNeeded];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    // 切回来时立刻检查一次；vnode 事件偶尔会丢（例如网络盘）
    [self checkForExternalModification];
}

- (void)openFolderAtURL:(NSURL *)folderURL {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:folderURL.path isDirectory:&isDir] || !isDir) {
        [TMRecentFiles removeFolderURL:folderURL];
        return;
    }

    [self setProjectRootURL:folderURL reload:YES];
    [TMRecentFiles noteFolderURL:folderURL];
    [self hideWelcome];
    self.outlineSidebarView.mode = TMSidebarModeFiles;
    if (self.sidebarItem.isCollapsed) [self toggleOutlineSidebar];

    NSURL *main = [TMProject guessMainFileInDirectory:folderURL];
    if (main) {
        [self openDocumentAtURL:main];
    } else {
        [self.statusBar showInfoMessage:[NSString stringWithFormat:@"已打开文件夹 %@，未找到含 \\documentclass 的主文件", folderURL.lastPathComponent]];
        // 编辑器里还是之前的文件，它不属于这个项目，别记进会话
        [TMRecentFiles noteSessionFolderURL:folderURL fileURL:nil selection:0];
    }
}

/// 决定 ⌘↩ 实际编译哪个文件：暂存文档就是自己；否则按魔法注释 / \documentclass / 同目录引用推断。
- (NSURL *)mainFileURLForCompile {
    NSURL *fileURL = self.documentModel.fileURL;
    if (!fileURL || self.documentModel.isScratch) return fileURL;
    return [TMProject mainFileURLForDocumentURL:fileURL content:self.documentModel.content] ?: fileURL;
}

#pragma mark - TMFileBrowserViewDelegate

- (void)fileBrowserView:(TMFileBrowserView *)browser didSelectFileURL:(NSURL *)url {
    if ([url.URLByStandardizingPath isEqual:self.documentModel.fileURL.URLByStandardizingPath]) return;
    [self openDocumentAtURL:url];
    // 用户取消了保存提示时，把选中项拨回当前文件
    [browser selectFileURL:self.documentModel.isScratch ? nil : self.documentModel.fileURL];
}

- (void)fileBrowserView:(TMFileBrowserView *)browser didCreateFileURL:(NSURL *)url {
    [self openDocumentAtURL:url];
    [browser selectFileURL:self.documentModel.isScratch ? nil : self.documentModel.fileURL];
}

/// 当前文件（或其祖先目录）被改名：把 documentModel 的路径映射到新位置，避免下次保存写回旧路径。
- (void)fileBrowserView:(TMFileBrowserView *)browser didRenameItemAtURL:(NSURL *)oldURL toURL:(NSURL *)newURL {
    NSURL *current = self.documentModel.fileURL;
    if (!current || self.documentModel.isScratch) return;
    NSString *currentPath = current.URLByStandardizingPath.path;
    NSString *oldPath = oldURL.URLByStandardizingPath.path;
    NSString *mapped = nil;
    if ([currentPath isEqualToString:oldPath]) {
        mapped = newURL.URLByStandardizingPath.path;
    } else if ([currentPath hasPrefix:[oldPath stringByAppendingString:@"/"]]) {
        mapped = [newURL.URLByStandardizingPath.path stringByAppendingString:[currentPath substringFromIndex:oldPath.length]];
    }
    if (!mapped) return;
    self.documentModel.fileURL = [NSURL fileURLWithPath:mapped];
    [self refreshWindowTitle];
    [self startWatchingCurrentFile];
    [TMRecentFiles removeFileURL:oldURL];
    [TMRecentFiles noteFileURL:self.documentModel.fileURL];
    [browser selectFileURL:self.documentModel.fileURL];
    [self showPDFIfExistsAtURL:[self expectedPDFURLForMainFile]];
}

/// 当前文件被移到废纸篓：编辑器内容保留，变成未命名文档，下次 ⌘S 走另存为。
- (void)fileBrowserView:(TMFileBrowserView *)browser didTrashItemAtURL:(NSURL *)url {
    [TMRecentFiles removeFileURL:url];
    NSURL *current = self.documentModel.fileURL;
    if (!current || self.documentModel.isScratch) return;
    NSString *currentPath = current.URLByStandardizingPath.path;
    NSString *trashedPath = url.URLByStandardizingPath.path;
    BOOL affected = [currentPath isEqualToString:trashedPath] || [currentPath hasPrefix:[trashedPath stringByAppendingString:@"/"]];
    if (!affected) return;
    [self.fileWatcher stop];
    self.fileWatcher = nil;
    self.documentModel.content = self.editorTextView.string;
    self.documentModel.fileURL = nil;
    self.documentModel.isDirty = YES;
    [self refreshWindowTitle];
    [browser selectFileURL:nil];
    [self.statusBar showInfoMessage:[NSString stringWithFormat:@"%@ 已移到废纸篓，编辑器内容保留为未命名文档", url.lastPathComponent]];
}

/// 若 url 处已有 PDF 就载入预览并记为 currentPDFURL；否则显示占位提示。
- (void)showPDFIfExistsAtURL:(nullable NSURL *)url {
    if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        self.currentPDFURL = url;
        [self.pdfView loadPDFFromURL:url];
        self.pdfPlaceholderView.hidden = YES;
    } else {
        self.currentPDFURL = nil;
        self.pdfPlaceholderView.hidden = NO;
    }
}

- (void)refreshWindowTitle {
    NSString *key = self.documentModel.isScratch ? nil : self.documentModel.fileURL.URLByStandardizingPath.path;
    if (key ? ![key isEqualToString:self.editorTextView.completionDocumentKey] : self.editorTextView.completionDocumentKey.isAbsolutePath) {
        self.editorTextView.completionDocumentKey = key;
    }
    self.window.title = [NSString stringWithFormat:@"TeXMini - %@", self.documentModel.displayName];
    self.window.representedURL = self.documentModel.isScratch ? nil : self.documentModel.fileURL;
    self.window.documentEdited = self.documentModel.isDirty;
    // 标题跟着文件名变的地方（打开、另存为、重命名）也就是文件类型可能变的地方
    self.editorTextView.syntax = [TMLaTeXHighlighter syntaxForFileURL:self.documentModel.isScratch ? nil : self.documentModel.fileURL];
}

- (BOOL)hasUnsavedChanges {
    return self.documentModel.isDirty;
}

/// 在丢弃当前文档前询问用户。返回 YES 表示可以继续（已保存或用户选择不保存）。
- (BOOL)confirmDiscardChangesWithTitle:(NSString *)title {
    if (![self hasUnsavedChanges]) return YES;
    // 开着自动保存就直接存，不打断；暂存 / 未命名文档或保存失败才问
    if ([TMPreferences shared].autoSaveEnabled && [self autoSaveIfNeeded]) return YES;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = [NSString stringWithFormat:@"“%@” 有未保存的更改，不保存将丢失这些更改。", self.documentModel.displayName];
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"不保存"];
    [alert addButtonWithTitle:@"取消"];
    alert.buttons[2].keyEquivalent = @"\e";

    NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) {
        return [self saveCurrentDocument];
    } else if (response == NSAlertSecondButtonReturn) {
        return YES;
    }
    return NO;
}

- (void)openDocumentAtURL:(NSURL *)url {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir]) {
        [TMRecentFiles removeFileURL:url];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"文件不存在";
        alert.informativeText = [NSString stringWithFormat:@"找不到 “%@”，可能已被移动或删除。", url.path];
        [alert runModal];
        return;
    }
    if (isDir) {
        [self openFolderAtURL:url];
        return;
    }
    if (![TMProject isEditableFileURL:url]) {
        [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }
    if (![self confirmDiscardChangesWithTitle:@"打开其他文件前是否保存更改？"]) return;

    NSError *error = nil;
    TMDocument *newDoc = [TMDocument documentWithContentsOfURL:url error:&error];
    if (newDoc) {
        self.documentModel = newDoc;
        [self loadDocumentIntoEditor];
        [self.statusBar showReadyState];
        [TMRecentFiles noteFileURL:url];
    } else {
        NSAlert *alert = [NSAlert alertWithError:error];
        [alert runModal];
    }
}

- (BOOL)saveCurrentDocument {
    self.documentModel.content = self.editorTextView.string;

    if (!self.documentModel.fileURL || self.documentModel.isScratch) {
        return [self saveDocumentAs];
    }

    NSError *err = nil;
    if (![self.documentModel saveCurrentFileWithError:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return NO;
    }
    [self didWriteCurrentFile];
    [self refreshWindowTitle];
    return YES;
}

- (BOOL)saveDocumentAs {
    self.documentModel.content = self.editorTextView.string;

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"tex"] ?: UTTypePlainText];
    panel.nameFieldStringValue = self.documentModel.isScratch || !self.documentModel.fileURL
        ? @"document.tex"
        : self.documentModel.fileURL.lastPathComponent;
    if (!self.documentModel.isScratch && self.documentModel.fileURL) {
        panel.directoryURL = self.documentModel.fileURL.URLByDeletingLastPathComponent;
    }

    if ([panel runModal] != NSModalResponseOK || !panel.URL) return NO;

    NSError *err = nil;
    if (![self.documentModel saveToURL:panel.URL error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return NO;
    }
    [self refreshWindowTitle];
    [TMRecentFiles noteFileURL:panel.URL];
    [self syncProjectRootWithDocument];
    [self startWatchingCurrentFile];
    [self.completionProvider invalidate];
    // 换了目录后旧的 PDF 不再对应，重新判断预览
    [self showPDFIfExistsAtURL:[self expectedPDFURLForMainFile]];
    return YES;
}

#pragma mark - PDF 导出

- (BOOL)exportPDF {
    NSURL *pdfURL = self.currentPDFURL;
    if (!pdfURL || ![[NSFileManager defaultManager] fileExistsAtPath:pdfURL.path]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"尚未生成 PDF";
        alert.informativeText = @"请先按下 ⌘↩ 进行编译，成功生成 PDF 后方可导出。";
        [alert runModal];
        return NO;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePDF];
    panel.canCreateDirectories = YES;
    // 默认文件名跟随用户的 .tex 名字；暂存文档给一个友好名字而不是 TeXMini_Document.pdf
    if (self.documentModel.isScratch || !self.documentModel.fileURL) {
        panel.nameFieldStringValue = @"document.pdf";
    } else {
        panel.nameFieldStringValue = pdfURL.lastPathComponent;
        panel.directoryURL = self.documentModel.fileURL.URLByDeletingLastPathComponent;
    }

    if ([panel runModal] != NSModalResponseOK || !panel.URL) return NO;
    if ([panel.URL isEqual:pdfURL]) return YES; // 选了原位置，无需复制

    NSError *err = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:panel.URL.path]) {
        [fm removeItemAtURL:panel.URL error:nil];
    }
    if (![fm copyItemAtURL:pdfURL toURL:panel.URL error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return NO;
    }
    [self.statusBar showInfoMessage:[NSString stringWithFormat:@"已导出 %@", panel.URL.lastPathComponent]];
    return YES;
}

- (void)revealPDFInFinder {
    NSURL *pdfURL = self.currentPDFURL;
    if (!pdfURL || ![[NSFileManager defaultManager] fileExistsAtPath:pdfURL.path]) return;
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[pdfURL]];
}

#pragma mark - NSWindowDelegate

/// 两段式关闭：项目里点关闭 → 回到首页（方便换项目）；首页上再点关闭才真正关窗退出。
- (BOOL)windowShouldClose:(NSWindow *)sender {
    BOOL onWelcome = [self isShowingWelcome];
    if (![self confirmDiscardChangesWithTitle:onWelcome ? @"关闭窗口前是否保存更改？" : @"关闭项目前是否保存更改？"]) return NO;
    if (!onWelcome) {
        [self closeProjectAndShowWelcome];
        return NO;
    }
    // 用户已决定（保存或放弃），避免随后的 applicationShouldTerminate 再问一次
    self.documentModel.isDirty = NO;
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.wordCounter cancel];
    [self saveSessionState];
    // 计时器强引用 self：关窗时停掉，否则窗口关了还会触发编译 / 保存，控制器也释放不掉。
    // 不补做待执行的自动保存：用户可能刚在关闭确认里选了“不保存”。
    for (NSTimer *timer in @[self.autoSaveTimer ?: NSNull.null, self.autoCompileTimer ?: NSNull.null, self.outlineDebounceTimer ?: NSNull.null]) {
        if ([timer isKindOfClass:[NSTimer class]]) [timer invalidate];
    }
    self.autoSaveTimer = nil;
    self.autoCompileTimer = nil;
    self.outlineDebounceTimer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (!self.scratchDirectoryURL) return;
    // 正在编译的是本窗口的暂存文档：先停掉，免得编译器往被删的目录里写
    if (self.documentModel.isScratch && [self isCompiling]) [self cancelCompilation];
    [self removeScratchDirectory];
}

#pragma mark - 编译动作与回调

- (void)compileCurrentDocument {
    // 任何一次新编译都不是“自动清理后的重试”（重试会在调用本方法之后再把标记设上）
    self.isRetryingAfterAutoClean = NO;
    if ([self isShowingWelcome]) return;
    self.documentModel.content = self.editorTextView.string;

    // 如果还没有指定文件路径，暂存到临时工作空间，省去弹窗干扰
    if (!self.documentModel.fileURL) {
        NSURL *tmpURL = [self scratchFileURLNamed:@"TeXMini_Document.tex"];
        [self.documentModel saveScratchToURL:tmpURL error:nil];
    } else if (self.documentModel.isDirty || ![[NSFileManager defaultManager] fileExistsAtPath:self.documentModel.fileURL.path]) {
        // 没改动就不写盘：原子写会换 inode，白白触发一轮文件监听重挂
        [self.documentModel saveCurrentFileWithError:nil];
        [self didWriteCurrentFile];
        [self refreshWindowTitle];
    }

    [self.logDrawer clearLog];
    self.lastIssues = @[];
    [self refreshIssueMarks];
    [[TMCompiler sharedCompiler] compileFileAtURL:[self mainFileURLForCompile]];
}

#pragma mark - 状态栏：编译目标与引擎

static NSString *TMEngineDisplayName(NSString *engine) {
    return @{ @"xelatex": @"XeLaTeX", @"pdflatex": @"pdfLaTeX", @"lualatex": @"LuaLaTeX" }[engine] ?: engine;
}

/// 状态栏常驻“目标文件 · 实际引擎”：与 compileFileAtURL: 的决策一致（主文件推断 → 手选 / 魔法注释 / ctex 检测）。
- (void)refreshCompileTarget {
    if (!self.statusBar || !self.documentModel) return;
    NSURL *main = [self mainFileURLForCompile];
    NSURL *currentURL = self.documentModel.fileURL;
    BOOL isCurrent = !main || [main isEqual:currentURL];
    BOOL isScratch = self.documentModel.isScratch;
    NSString *editorText = isCurrent ? [self.editorTextView.string copy] : nil;
    NSString *currentText = editorText ?: [self.editorTextView.string copy];
    NSUInteger generation = ++self.compileTargetGeneration;
    __weak typeof(self) weakSelf = self;

    // 判断可能要读 .cls / 调 kpsewhich（首次约 0.2 秒），放后台，只采用最新一次的结果
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *content = editorText ?: ([NSString stringWithContentsOfURL:main encoding:NSUTF8StringEncoding error:nil] ?: @"");
        // 标题 1 对应 \chapter 还是 \section：看主文件的文档类
        BOOL usesChapters = [TMFormatActions usesChaptersForMainContent:content currentContent:currentText];
        NSString *reason = nil;
        NSString *engine = [[TMCompiler sharedCompiler] effectiveEngineNameForContent:content
                                                                         directoryURL:(main ?: currentURL).URLByDeletingLastPathComponent
                                                                               reason:&reason];
        BOOL hasLatexmk = [TMCompiler findExecutableNamed:@"latexmk"] != nil;

        NSString *fileName = (!main || isScratch) ? @"未命名文档" : main.lastPathComponent;
        NSMutableString *tip = [NSMutableString string];
        if (main && !isScratch) {
            [tip appendFormat:@"编译文件：%@\n", main.path.stringByAbbreviatingWithTildeInPath];
            if (!isCurrent) [tip appendFormat:@"（当前编辑的 %@ 不是主文件，⌘↩ 编译的是它）\n", currentURL.lastPathComponent];
        }
        [tip appendFormat:@"引擎：%@ — %@", TMEngineDisplayName(engine), reason];
        if (hasLatexmk) [tip appendString:@"\n由 latexmk 调度（自动处理多遍编译与参考文献）"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.compileTargetGeneration != generation) return;
            [weakSelf.statusBar setCompileTargetFileName:fileName engine:TMEngineDisplayName(engine) toolTip:tip];
            weakSelf.headingUsesChapters = usesChapters;
            [weakSelf refreshParagraphStyleIndicator];
        });
    });
}

#pragma mark - 问题列表与行号槽标记

/// 日志里的文件名（相对主文件目录，如 "./chapters/ch1.tex"）是否指向当前编辑的文件。
/// 文件名为空（TeX 原生 "! " 错误没有文件信息）时，按“属于主文件”处理。
- (BOOL)issueBelongsToCurrentDocument:(TMLogIssue *)issue {
    NSURL *current = self.documentModel.fileURL;
    if (!current) return NO;
    NSURL *target = [self fileURLForIssue:issue];
    if (!target) return YES;
    return [target.URLByStandardizingPath.URLByResolvingSymlinksInPath.path
            isEqualToString:current.URLByStandardizingPath.URLByResolvingSymlinksInPath.path];
}

- (nullable NSURL *)fileURLForIssue:(TMLogIssue *)issue {
    if (issue.filePath.length == 0) {
        return [self mainFileURLForCompile];
    }
    NSURL *main = [self mainFileURLForCompile];
    NSURL *base = main ? main.URLByDeletingLastPathComponent : self.projectRootURL;
    if (!base) return nil;
    return [NSURL fileURLWithPath:issue.filePath relativeToURL:base].URLByStandardizingPath;
}

- (void)refreshIssueMarks {
    NSMutableDictionary<NSNumber *, NSNumber *> *marks = [NSMutableDictionary dictionary];
    for (TMLogIssue *issue in self.lastIssues) {
        if (issue.line <= 0) continue;
        if (![self issueBelongsToCurrentDocument:issue]) continue;
        NSNumber *existing = marks[@(issue.line)];
        // 同一行多条时保留最严重的（错误 < 警告 < 坏盒子）
        if (!existing || issue.kind < existing.integerValue) marks[@(issue.line)] = @(issue.kind);
    }
    [self.lineNumberRuler setIssueMarks:marks];
}

- (void)logDrawerView:(TMLogDrawerView *)drawer didSelectIssue:(TMLogIssue *)issue {
    if (issue.line <= 0) return;
    NSURL *target = [self fileURLForIssue:issue];
    if (target && ![self issueBelongsToCurrentDocument:issue]) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:target.path] || ![TMProject isEditableFileURL:target]) {
            [self.statusBar showInfoMessage:[NSString stringWithFormat:@"该问题来自 %@，文件不可打开", target.lastPathComponent]];
            return;
        }
        [self openDocumentAtURL:target];
        if (![self issueBelongsToCurrentDocument:issue]) return; // 用户取消了切换
    }
    [self.editorTextView jumpToLine:issue.line column:1];
    [self.window makeFirstResponder:self.editorTextView];
}

/// 我们自己写完磁盘后调用：记住新的修改时间（避免误报外部修改），并让补全重新扫描。
- (void)didWriteCurrentFile {
    [self rememberCurrentFileModificationDate];
    [self.completionProvider invalidateFileAtURL:self.documentModel.fileURL];
    [self.editorTextView refreshCompletionIfNeeded];
}

- (void)cancelCompilation {
    [[TMCompiler sharedCompiler] cancelCompilation];
}

- (BOOL)isCompiling {
    return [TMCompiler sharedCompiler].isCompiling;
}

#pragma mark - 自动保存

- (void)scheduleAutoSave {
    if (![TMPreferences shared].autoSaveEnabled) return;
    [self.autoSaveTimer invalidate];
    self.autoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(autoSaveTimerFired)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)autoSaveTimerFired {
    self.autoSaveTimer = nil;
    [self autoSaveIfNeeded];
}

/// 只保存 .tex，不编译。未命名 / 暂存文档不自动保存；磁盘上的文件被删或被别的程序改过时不覆盖，
/// 交给外部修改提示。返回 YES 表示现在已没有未保存的更改。
- (BOOL)autoSaveIfNeeded {
    if (!self.documentModel.isDirty) return YES;
    if (![TMPreferences shared].autoSaveEnabled) return NO;
    if (!self.documentModel.fileURL || self.documentModel.isScratch || self.isShowingExternalChangeAlert) return NO;
    // 输入法还在组字（拼音未上屏）：别把半截拼音写进文件，稍后再存
    if (self.editorTextView.hasMarkedText) {
        [self scheduleAutoSave];
        return NO;
    }

    [self.documentModel.fileURL removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    NSDate *onDisk = [self modificationDateOfCurrentFile];
    if (!onDisk) return NO;
    if (self.knownModificationDate && [onDisk compare:self.knownModificationDate] == NSOrderedDescending) {
        [self checkForExternalModification];
        return NO;
    }

    self.documentModel.content = self.editorTextView.string;
    NSError *err = nil;
    if (![self.documentModel saveCurrentFileWithError:&err]) {
        [self.statusBar showInfoMessage:[NSString stringWithFormat:@"自动保存失败：%@", err.localizedDescription ?: @"未知错误"]];
        return NO;
    }
    [self didWriteCurrentFile];
    [self refreshWindowTitle];
    return YES;
}

#pragma mark - 自动编译

- (void)setAutoCompileEnabled:(BOOL)enabled {
    if (_autoCompileEnabled == enabled) return;
    _autoCompileEnabled = enabled;
    [TMPreferences shared].autoCompileEnabled = enabled; // 触发通知 → applyPreferences 收尾
}

- (void)scheduleAutoCompile {
    if (!self.autoCompileEnabled) return;
    [self.autoCompileTimer invalidate];
    self.autoCompileTimer = [NSTimer scheduledTimerWithTimeInterval:1.5
                                                             target:self
                                                           selector:@selector(autoCompileTimerFired)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)autoCompileTimerFired {
    self.autoCompileTimer = nil;
    if (!self.autoCompileEnabled) return;
    if ([self isCompiling]) {
        // 正在编译，等结束后补一次
        self.needsCompileAfterCurrent = YES;
        return;
    }
    [self compileCurrentDocument];
}

- (void)runPendingAutoCompileIfNeeded {
    if (self.needsCompileAfterCurrent && self.autoCompileEnabled) {
        self.needsCompileAfterCurrent = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self compileCurrentDocument];
        });
    } else {
        self.needsCompileAfterCurrent = NO;
    }
}

- (void)compilerDidStartCompilingDocument:(NSURL *)fileURL {
    NSString *content = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *engineName = [[TMCompiler sharedCompiler] effectiveEngineNameForContent:content directoryURL:fileURL.URLByDeletingLastPathComponent reason:NULL];
    if ([TMCompiler findExecutableNamed:@"latexmk"]) {
        engineName = [NSString stringWithFormat:@"latexmk · %@", engineName];
    }
    if (![fileURL isEqual:self.documentModel.fileURL]) {
        engineName = [NSString stringWithFormat:@"%@ · 主文件 %@", engineName, fileURL.lastPathComponent];
    }
    [self.statusBar showCompilingStateWithEngine:engineName];
}

- (void)compilerDidOutputLog:(NSString *)text {
    [self.logDrawer appendLogText:text];
}

- (void)compilerDidFinishSuccess:(double)durationSeconds pdfURL:(NSURL *)pdfURL issues:(NSArray<TMLogIssue *> *)issues {
    self.isRetryingAfterAutoClean = NO;
    NSUInteger warnings = [TMLogParser countOfKind:TMLogIssueWarning inIssues:issues];
    NSUInteger badBoxes = [TMLogParser countOfKind:TMLogIssueBadBox inIssues:issues];
    [self.statusBar showSuccessStateWithDuration:durationSeconds warnings:warnings badBoxes:badBoxes];
    self.lastIssues = issues;
    [self.logDrawer setIssues:issues];
    [self refreshIssueMarks];
    self.currentPDFURL = pdfURL;
    self.pdfPlaceholderView.hidden = YES;
    [self.pdfView loadPDFFromURL:pdfURL preservingViewport:YES];
    // 搜索栏开着时对新 PDF 重新查找，高亮不丢
    if (!self.pdfSearchBar.hidden) [self runPDFSearchScrollToFirst:NO];
    [self.outlineSidebarView.fileBrowserView reload];
    [self runPendingAutoCompileIfNeeded];
}

- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues {
    // 只在能从日志确认“第一个错误出在旧的辅助文件里”时自动清理并重编一次；其他失败照常报错，不多花一次编译。
    NSString *staleFile = [TMLogParser staleAuxiliaryFileInLog:log];
    BOOL wasRetry = self.isRetryingAfterAutoClean;
    self.isRetryingAfterAutoClean = NO;
    NSURL *main = [self mainFileURLForCompile];
    NSString *key = staleFile ? [NSString stringWithFormat:@"%@|%@", main.path, staleFile] : nil;
    NSString *hint = nil;
    if (staleFile && wasRetry) {
        // 从干净状态重编还在辅助文件里出错：是文档自己写坏了它，清理没用。本次会话不再为它自动清理
        [self.unhelpfulAutoCleans addObject:key];
        hint = [NSString stringWithFormat:@"清理后重编仍在 %@ 出错，问题出在文档本身，之后不再为它自动清理。", staleFile];
        staleFile = nil;
    } else if (staleFile && [self.unhelpfulAutoCleans containsObject:key]) {
        staleFile = nil;
    }
    BOOL keepBibliography = staleFile && main && ![TMProject canRegenerateBibliographyForTeXFileURL:main];
    if (staleFile && keepBibliography && [staleFile.pathExtension.lowercaseString isEqualToString:@"bbl"]) {
        // 找不到生成它的 .bib（arXiv 源码常见）：删了就再也生成不出来，不动它
        hint = [NSString stringWithFormat:@"错误出在 %@，但没找到能重新生成它的 .bib 文件，未自动清理（删掉就无法恢复）。", staleFile];
        staleFile = nil;
    }
    if (staleFile && ![self isShowingWelcome]) {
        [self cleanAuxiliaryFilesForMainFileKeepingBibliography:keepBibliography];
        [self compileCurrentDocument];
        // 在 compileCurrentDocument 之后设：重试被手动 ⌘↩ 顶掉时，新编译不会被误当成重试
        self.isRetryingAfterAutoClean = YES;
        NSString *note = [NSString stringWithFormat:@"%@ 是上次留下的旧文件，已清理辅助文件并重新编译", staleFile];
        [self.logDrawer appendLogText:[NSString stringWithFormat:@"TeXMini：第一个错误出在 %@（旧的辅助文件），已自动清理并重新编译。\n\n", staleFile]];
        [self.statusBar showCompilingStateWithEngine:note];
        return;
    }
    if (hint) [self.logDrawer appendLogText:[NSString stringWithFormat:@"\nTeXMini：%@\n", hint]];
    [self.statusBar showErrorStateWithMessage:summary line:lineNumber];
    self.lastIssues = issues;
    [self.logDrawer setIssues:issues];
    [self refreshIssueMarks];
    if (!self.logDrawer.isExpanded) {
        [self.logDrawer toggleAnimated];
    }
    [self.fontFix offerFontFixForLog:log];
    [self runPendingAutoCompileIfNeeded];
}

- (void)compilerDidCancel {
    self.isRetryingAfterAutoClean = NO;
    [self.statusBar showInfoMessage:@"已取消编译"];
    [self runPendingAutoCompileIfNeeded];
}

#pragma mark - SyncTeX 双向同步

- (void)forwardSyncToPDF {
    if (!self.documentModel.fileURL) return;
    if (!self.currentPDFURL || !self.pdfView.document) {
        [self.statusBar showInfoMessage:@"还没有 PDF，请先 ⌘↩ 编译"];
        return;
    }

    NSString *src = self.documentModel.fileURL.path;
    NSString *pdf = self.currentPDFURL.path;

    TMSyncTeXResult *res = [TMSyncTeX forwardSearchLine:self.currentCursorLine
                                                 column:self.currentCursorCol
                                             sourceFile:src
                                                pdfPath:pdf
                                               pdfView:self.pdfView];
    if (res) {
        [self.pdfView flashHighlightRect:res.targetRect onPageAtIndex:res.pageIndex];
    } else {
        NSString *syncFile = [self.currentPDFURL.URLByDeletingPathExtension URLByAppendingPathExtension:@"synctex.gz"].path;
        BOOL hasSync = [[NSFileManager defaultManager] fileExistsAtPath:syncFile];
        [self.statusBar showInfoMessage:hasSync
            ? [NSString stringWithFormat:@"第 %ld 行在 PDF 中没有对应位置（可能是注释或导言区）", (long)self.currentCursorLine]
            : @"缺少 .synctex.gz，重新编译一次即可启用同步"];
    }
}

- (void)editorTextViewDidRequestForwardSync {
    [self forwardSyncToPDF];
}

- (void)pdfViewDidRequestInverseSearchAtPoint:(NSPoint)pointOnPage pageIndex:(NSInteger)pageIndex pageBounds:(NSRect)pageBounds {
    if (!self.currentPDFURL) return;

    NSString *pdf = self.currentPDFURL.path;
    TMSyncTeXResult *res = [TMSyncTeX inverseSearchPoint:pointOnPage
                                               pageIndex:pageIndex
                                              pageBounds:pageBounds
                                                 pdfPath:pdf];
    if (!res || res.sourceLine <= 0) return;

    // SyncTeX 返回的文件名可能是相对 PDF 目录的路径；落在别的文件时直接切过去再跳行。
    if (res.sourceFilePath.length > 0 && self.documentModel.fileURL) {
        NSURL *pdfDir = self.currentPDFURL.URLByDeletingLastPathComponent;
        NSURL *target = [NSURL fileURLWithPath:res.sourceFilePath relativeToURL:pdfDir];
        NSString *targetPath = target.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
        NSString *currentPath = self.documentModel.fileURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
        if (targetPath && currentPath && ![targetPath isEqualToString:currentPath]) {
            NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
            if (![[NSFileManager defaultManager] fileExistsAtPath:targetPath] || ![TMProject isEditableFileURL:targetURL]) {
                NSBeep();
                [self.statusBar showInfoMessage:[NSString stringWithFormat:@"该位置来自 %@ 第 %ld 行，文件不可打开",
                                                 targetPath.lastPathComponent, (long)res.sourceLine]];
                return;
            }
            [self openDocumentAtURL:targetURL];
            if (![self.documentModel.fileURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path isEqualToString:targetPath]) {
                return; // 用户取消了切换
            }
        }
    }

    [self.editorTextView jumpToLine:res.sourceLine column:res.sourceColumn];
    [self.window makeFirstResponder:self.editorTextView];
}

#pragma mark - TMEditorTextViewDelegate & NSTextDelegate

- (void)textDidChange:(NSNotification *)notification {
    // 立即停止旧文本统计；新快照仍沿用大纲的 250 ms 防抖。
    [self.wordCounter cancel];
    if (!self.documentModel.isDirty) {
        self.documentModel.isDirty = YES;
        self.window.documentEdited = YES;
    }
    [self scheduleOutlineUpdateImmediate:NO];
    [self scheduleAutoSave];
    [self scheduleAutoCompile];
}

- (void)editorTextViewDidChangeCursorPositionToLine:(NSInteger)line column:(NSInteger)column {
    self.currentCursorLine = line;
    self.currentCursorCol = column;
    [self.statusBar setCursorLine:line column:column];
    [self.outlineSidebarView highlightItemForLineNumber:line];
    [self refreshParagraphStyleIndicator];
}

- (void)updateWordCount {
    __weak typeof(self) weakSelf = self;
    [self.wordCounter countText:self.editorTextView.string completion:^(NSUInteger words) {
        [weakSelf.statusBar setWordCount:words];
    }];
}

#pragma mark - 拖入图片 / 文件

/// 图片与 .tex 走这里：图片 → figure 骨架（项目外的图片先复制进 figures/），.tex → \input{}。其他类型交回系统。
- (BOOL)editorTextView:(NSTextView *)textView didDropFileURLs:(NSArray<NSURL *> *)urls atCharacterIndex:(NSUInteger)index {
    NSArray<NSString *> *imageExts = [TMEditActions droppableImageExtensions];
    NSMutableArray<NSURL *> *images = [NSMutableArray array];
    NSMutableArray<NSURL *> *texFiles = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSString *ext = url.pathExtension.lowercaseString;
        if ([imageExts containsObject:ext]) [images addObject:url];
        else if ([ext isEqualToString:@"tex"]) [texFiles addObject:url];
    }
    if (images.count == 0 && texFiles.count == 0) return NO;

    // 相对路径以主文件所在目录为基准（\includegraphics / \input 在 TeX 里就是这么解析的）
    NSURL *main = [self mainFileURLForCompile];
    if (!main || self.documentModel.isScratch) {
        [self.statusBar showInfoMessage:@"请先保存文档，再拖入图片（路径要相对于 .tex 文件）"];
        return YES;
    }
    NSURL *baseDir = main.URLByDeletingLastPathComponent;

    NSMutableString *snippet = [NSMutableString string];
    NSUInteger cursorOffset = NSNotFound;
    for (NSURL *img in images) {
        NSString *rel = [self relativePathForDroppedImage:img baseDirectory:baseDir];
        if (!rel) continue;
        NSUInteger off = 0;
        NSString *block = [TMEditActions figureSnippetForImagePath:rel
                                                             label:[TMEditActions labelSlugForFileName:rel.lastPathComponent]
                                                      cursorOffset:&off];
        if (cursorOffset == NSNotFound) cursorOffset = snippet.length + off;
        [snippet appendString:block];
    }
    for (NSURL *tex in texFiles) {
        NSString *rel = [TMEditActions relativePathFromDirectory:baseDir toFile:tex];
        if (!rel) { rel = tex.path; }
        [snippet appendFormat:@"\\input{%@}\n", rel.stringByDeletingPathExtension];
    }
    if (snippet.length == 0) return YES;

    // 落在行中间时先换行，保证 figure 独占整行
    NSString *text = self.editorTextView.string;
    NSUInteger loc = MIN(index, text.length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(loc, 0)];
    if (loc != lineRange.location) {
        [snippet insertString:@"\n" atIndex:0];
        if (cursorOffset != NSNotFound) cursorOffset += 1;
    }
    [self.editorTextView insertSnippet:snippet atLocation:loc cursorOffset:cursorOffset == NSNotFound ? snippet.length : cursorOffset];

    if (images.count > 0) [self ensurePackage:@"graphicx" loadedForMainFile:main];
    [self.outlineSidebarView.fileBrowserView reload];
    return YES;
}

/// 项目内的图片直接用相对路径；项目外的复制到主文件旁的 figures/，重名时加序号。
- (nullable NSString *)relativePathForDroppedImage:(NSURL *)image baseDirectory:(NSURL *)baseDir {
    NSString *rel = [TMEditActions relativePathFromDirectory:baseDir toFile:image];
    if (rel) return rel;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *figuresDir = [baseDir URLByAppendingPathComponent:@"figures" isDirectory:YES];
    NSError *err = nil;
    if (![fm createDirectoryAtURL:figuresDir withIntermediateDirectories:YES attributes:nil error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return nil;
    }
    NSString *name = image.lastPathComponent;
    NSURL *dest = [figuresDir URLByAppendingPathComponent:name];
    NSUInteger n = 2;
    while ([fm fileExistsAtPath:dest.path]) {
        NSString *candidate = [NSString stringWithFormat:@"%@-%lu.%@", name.stringByDeletingPathExtension, (unsigned long)n++, name.pathExtension];
        dest = [figuresDir URLByAppendingPathComponent:candidate];
    }
    if (![fm copyItemAtURL:image toURL:dest error:&err]) {
        [[NSAlert alertWithError:err] runModal];
        return nil;
    }
    [self.statusBar showInfoMessage:[NSString stringWithFormat:@"已复制 %@ 到 figures/", dest.lastPathComponent]];
    return [@"figures" stringByAppendingPathComponent:dest.lastPathComponent];
}

/// 当前编辑的就是主文件时直接在导言区插入 \usepackage{package}；否则只提示。
- (void)ensurePackage:(NSString *)package loadedForMainFile:(nullable NSURL *)main {
    BOOL editingMain = !main || [main.URLByStandardizingPath.path isEqualToString:self.documentModel.fileURL.URLByStandardizingPath.path];
    NSString *content = editingMain ? self.editorTextView.string
                                    : ([NSString stringWithContentsOfURL:main encoding:NSUTF8StringEncoding error:nil] ?: @"");
    // graphbox 也会加载 graphicx
    NSUInteger loc = [package isEqualToString:@"graphicx"] ? [TMEditActions graphicxInsertionLocationInContent:content]
                                                            : [TMFormatActions usepackageInsertionLocationForPackage:package inContent:content];
    if (loc == NSNotFound) return;
    if (!editingMain) {
        [self.statusBar showInfoMessage:[NSString stringWithFormat:@"主文件 %@ 尚未加载 %@，请在导言区加上 \\usepackage{%@}", main.lastPathComponent, package, package]];
        return;
    }
    NSRange sel = self.editorTextView.selectedRange;
    NSString *usepackage = [NSString stringWithFormat:@"\\usepackage{%@}\n", package];
    NSString *line = (loc > 0 && [content characterAtIndex:loc - 1] != '\n') ? [@"\n" stringByAppendingString:usepackage] : usepackage;
    [self.editorTextView insertSnippet:line atLocation:loc cursorOffset:0];
    // 插在光标之前，把光标和选区挪回原来的位置
    [self.editorTextView setSelectedRange:NSMakeRange(sel.location + (loc <= sel.location ? line.length : 0), sel.length)];
    [self.editorTextView scrollRangeToVisible:self.editorTextView.selectedRange];
}

#pragma mark - 格式菜单

- (BOOL)canApplyFormat {
    if ([self isShowingWelcome]) return NO;
    TMEditorSyntax syntax = self.editorTextView.syntax;
    return syntax == TMEditorSyntaxLaTeX || syntax == TMEditorSyntaxMarkdown;
}

- (BOOL)isEditingMarkdown {
    return self.editorTextView.syntax == TMEditorSyntaxMarkdown;
}

- (TMParagraphStyle)currentParagraphStyle {
    return [TMFormatActions paragraphStyleAtLocation:self.editorTextView.selectedRange.location inText:self.editorTextView.string
                                            markdown:[self isEditingMarkdown] usesChapters:self.headingUsesChapters];
}

- (void)applyFormatEdit:(nullable TMFormatEdit *)edit actionName:(NSString *)actionName {
    if (!edit || ![self canApplyFormat]) return;
    [self.window makeFirstResponder:self.editorTextView];
    [self.editorTextView replaceRange:edit.range withText:edit.replacement selection:edit.selection actionName:actionName];
    if (edit.requiredPackage) [self ensurePackage:edit.requiredPackage loadedForMainFile:[self mainFileURLForCompile]];
    [self refreshParagraphStyleIndicator];
}

- (void)applyParagraphStyle:(TMParagraphStyle)style {
    TMFormatEdit *edit = [TMFormatActions editForParagraphStyle:style selection:self.editorTextView.selectedRange inText:self.editorTextView.string
                                                       markdown:[self isEditingMarkdown] usesChapters:self.headingUsesChapters];
    [self applyFormatEdit:edit actionName:[TMFormatActions displayNameForParagraphStyle:style]];
}

- (void)applyInlineStyle:(TMInlineStyle)style {
    static NSString *const names[] = {@"加粗", @"斜体", @"下划线"};
    TMFormatEdit *edit = [TMFormatActions editForInlineStyle:style selection:self.editorTextView.selectedRange
                                                      inText:self.editorTextView.string markdown:[self isEditingMarkdown]];
    [self applyFormatEdit:edit actionName:names[style]];
}

- (void)insertFormat:(TMFormatInsertion)kind {
    static NSString *const names[] = {@"插入行内公式", @"插入公式块", @"插入表格", @"插入脚注", @"插入链接"};
    TMFormatEdit *edit = [TMFormatActions editForInsertion:kind selection:self.editorTextView.selectedRange
                                                    inText:self.editorTextView.string markdown:[self isEditingMarkdown]];
    [self applyFormatEdit:edit actionName:names[kind]];
}

- (void)insertImageFromPanel {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *ext in [TMEditActions droppableImageExtensions]) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type) [types addObject:type];
    }
    panel.allowedContentTypes = types;
    panel.allowsMultipleSelection = YES;
    panel.message = @"选择要插入的图片（项目外的图片会复制到 figures/）";
    NSURL *main = [self mainFileURLForCompile];
    if (main && !self.documentModel.isScratch) panel.directoryURL = main.URLByDeletingLastPathComponent;
    if ([panel runModal] != NSModalResponseOK || panel.URLs.count == 0) return;
    [self editorTextView:self.editorTextView didDropFileURLs:panel.URLs atCharacterIndex:self.editorTextView.selectedRange.location];
    [self.window makeFirstResponder:self.editorTextView];
}

/// 状态栏样式框跟随光标；停下来再算，连续打字 / 按方向键时不重复扫描
- (void)refreshParagraphStyleIndicator {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(updateParagraphStyleIndicatorNow) object:nil];
    [self performSelector:@selector(updateParagraphStyleIndicatorNow) withObject:nil afterDelay:0.15];
}

- (void)updateParagraphStyleIndicatorNow {
    [self.statusBar setParagraphStyle:[self canApplyFormat] ? [self currentParagraphStyle] : -1];
}

- (void)statusBarDidSelectParagraphStyle:(NSInteger)style {
    if (style == [self currentParagraphStyle]) return;
    [self applyParagraphStyle:(TMParagraphStyle)style];
}

#pragma mark - 首页与上次会话

- (BOOL)isShowingWelcome {
    return !self.welcomeView.hidden;
}

- (void)showWelcome {
    self.welcomeView.showsDismissButton = self.documentModel.fileURL != nil && !self.documentModel.isScratch;
    [self.welcomeView reload];
    self.window.toolbar.visible = NO;
    self.statusBar.hidden = YES;
    // 隐藏下面的编辑区：否则编辑器的 I 形光标区域会透过首页生效，鼠标到处显示成文本光标
    self.mainSplitViewController.view.hidden = YES;
    self.logDrawer.hidden = YES;
    self.welcomeView.hidden = NO;
    [self.window makeFirstResponder:self.welcomeView];
    self.window.title = @"TeXMini";
    self.window.representedURL = nil;
}

- (void)hideWelcome {
    if (![self isShowingWelcome]) return;
    self.welcomeView.hidden = YES;
    self.mainSplitViewController.view.hidden = NO;
    self.logDrawer.hidden = NO;
    self.window.toolbar.visible = YES;
    self.statusBar.hidden = NO;
    [self refreshWindowTitle];
    [self.window makeFirstResponder:self.editorTextView];
}

/// 记下当前项目文件夹、文件与光标；未命名文档会清除上一次启动会话。
- (void)saveSessionState {
    NSURL *file = self.documentModel.isScratch ? nil : self.documentModel.fileURL;
    if (!file && !self.projectRootURL) {
        // 当前是全新的未命名文档：不要把上一个项目留作下次启动的会话。
        [TMRecentFiles noteSessionFolderURL:nil fileURL:nil selection:0];
        return;
    }
    [TMRecentFiles noteSessionFolderURL:self.projectRootURL fileURL:file selection:self.editorTextView.selectedRange.location];
}

- (void)restoreLastSessionOrShowWelcome {
    BOOL restore = [TMPreferences shared].restoreLastSession;
    NSURL *file = restore ? [TMRecentFiles sessionFileURL] : nil;
    NSURL *folder = restore ? [TMRecentFiles sessionFolderURL] : nil;
    NSUInteger selection = [TMRecentFiles sessionSelection];

    TMDocument *doc = (file && [TMProject isEditableFileURL:file]) ? [TMDocument documentWithContentsOfURL:file error:nil] : nil;
    if (doc) {
        // 文件在上次的项目文件夹里：文件浏览器的根也回到那个文件夹，而不是文件所在的子目录
        if (folder && [file.URLByStandardizingPath.path hasPrefix:[folder.URLByStandardizingPath.path stringByAppendingString:@"/"]]) {
            [self setProjectRootURL:folder reload:YES];
        }
        self.documentModel = doc;
        [self loadDocumentIntoEditor];
        [TMRecentFiles noteFileURL:file];
        NSRange sel = NSMakeRange(MIN(selection, self.editorTextView.string.length), 0);
        [self.editorTextView setSelectedRange:sel];
        // 等窗口第一次布局完再滚动，否则算不出目标位置
        dispatch_async(dispatch_get_main_queue(), ^{ [self.editorTextView scrollRangeToVisible:sel]; });
        return;
    }
    // 没有可恢复的文件：先载入 initForSessionRestore 延后的空白文档，保证编辑器状态完整
    [self loadDocumentIntoEditor];
    if (folder) {
        [self openFolderAtURL:folder];
        return;
    }
    [self showWelcome];
}

- (void)closeProjectAndShowWelcome {
    // 先记下会话：关掉项目后在首页退出，下次启动仍回到这个项目
    [self saveSessionState];
    if ([self isCompiling]) [self cancelCompilation];
    [self.autoSaveTimer invalidate];
    self.autoSaveTimer = nil;
    [self.autoCompileTimer invalidate];
    self.autoCompileTimer = nil;
    self.needsCompileAfterCurrent = NO;
    [self.fileWatcher stop];
    self.fileWatcher = nil;
    [self removeScratchDirectory];

    [self setProjectRootURL:nil reload:YES];
    self.documentModel = [TMDocument documentWithBlankTemplate];
    [self loadDocumentIntoEditor];
    [self.logDrawer clearLog];
    self.lastIssues = @[];
    [self.logDrawer setIssues:@[]];
    [self refreshIssueMarks];
    [self hidePDFSearchBar];
    [self showPDFIfExistsAtURL:nil];
    [self.statusBar showReadyState];
    [self showWelcome];
    [self.wordCounter cancel];
}

#pragma mark - TMWelcomeViewDelegate

- (void)welcomeViewDidRequestNewDocument:(TMWelcomeView *)view {
    [self welcomeView:view didSelectTemplateAtIndex:2];
}

- (void)welcomeView:(TMWelcomeView *)view didSelectTemplateAtIndex:(NSInteger)index {
    if (![self confirmDiscardChangesWithTitle:@"创建新文档前是否保存当前文档的更改？"]) {
        return;
    }
    switch (index) {
        case 0: [self applyDefaultTemplate:nil]; break;
        case 1: [self applyChineseTemplate:nil]; break;
        case 2:
        default: [self applyBlankTemplate:nil]; break;
    }
    [self hideWelcome];
}

- (void)welcomeViewDidRequestTemplatePicker:(TMWelcomeView *)view {
    [self showTemplateMenuAction:nil];
}

- (void)welcomeViewDidRequestOpenFile:(TMWelcomeView *)view { [self openFileAction:nil]; }
- (void)welcomeViewDidRequestOpenFolder:(TMWelcomeView *)view { [self openFolderAction:nil]; }
- (void)welcomeViewDidRequestDismiss:(TMWelcomeView *)view { [self hideWelcome]; }

- (void)welcomeView:(TMWelcomeView *)view didSelectRecentURL:(NSURL *)url {
    [self openDocumentAtURL:url];
    // 打开失败（文件已不在）时列表要刷新
    if ([self isShowingWelcome]) [view reload];
}

#pragma mark - 文档字体（实现在 TMFontFixController）

/// 字体功能用到时才创建：多数会话里根本不会碰它。
- (TMFontFixController *)fontFix {
    if (!_fontFix) _fontFix = [[TMFontFixController alloc] initWithHost:self];
    return _fontFix;
}

- (void)showDocumentFontsSheet { [self.fontFix showDocumentFontsSheet]; }
- (nullable NSURL *)currentDocumentFileURL { return self.documentModel.fileURL; }
- (void)showInfoMessage:(NSString *)message { [self.statusBar showInfoMessage:message]; }

#pragma mark - 编辑器字号

- (void)increaseEditorFontSize {
    [TMPreferences shared].editorFontSize = self.editorTextView.editorFontSize + 1.0;
}

- (void)decreaseEditorFontSize {
    [TMPreferences shared].editorFontSize = self.editorTextView.editorFontSize - 1.0;
}

- (void)resetEditorFontSize {
    [TMPreferences shared].editorFontSize = 13.5;
}

#pragma mark - TMStatusBarViewDelegate

- (void)statusBarDidClickErrorLine:(NSInteger)line {
    [self.editorTextView jumpToLine:line column:1];
    [self.window makeFirstResponder:self.editorTextView];
}

- (void)statusBarDidToggleLogDrawer {
    [self toggleLogDrawer];
}

- (void)statusBarDidChangeEngine:(TMTeXEngine)engine {
    [TMPreferences shared].defaultEngine = engine; // 通知 → applyPreferences 更新编译器
}

#pragma mark - 大纲解析与侧边栏控制

- (void)scheduleOutlineUpdateImmediate:(BOOL)immediate {
    [self.outlineDebounceTimer invalidate];
    if (immediate) {
        [self updateOutline];
    } else {
        self.outlineDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                                     target:self
                                                                   selector:@selector(updateOutline)
                                                                   userInfo:nil
                                                                    repeats:NO];
    }
}

- (void)updateOutline {
    NSString *content = self.editorTextView.string;
    NSArray<TMOutlineItem *> *flatList = nil;
    NSArray<TMOutlineItem *> *rootItems;
    if (self.editorTextView.syntax == TMEditorSyntaxLaTeX) {
        rootItems = [TMOutlineParser parseOutlineFromScan:self.editorTextView.currentLaTeXScan
                                              lineIndex:self.editorTextView.lineIndex flatList:&flatList];
    } else {
        rootItems = [TMOutlineParser parseOutlineFromLaTeXString:content flatList:&flatList];
    }
    [self.outlineSidebarView updateWithRootItems:rootItems flatItems:flatList];
    [self.outlineSidebarView highlightItemForLineNumber:self.currentCursorLine];
    [self updateWordCount];
    [self refreshCompileTarget];
}

- (void)toggleOutlineSidebar {
    // 交给系统：带动画、自动隐藏分割线、宽度由 autosave 记住
    [self.mainSplitViewController toggleSidebar:nil];
    // toggleSidebar: 的动画结束后 collapsed 才更新，这里记录目标状态
    [[NSUserDefaults standardUserDefaults] setBool:!self.sidebarItem.isCollapsed forKey:kTMDefaultsOutlineCollapsed];
}

#pragma mark - TMOutlineSidebarViewDelegate

- (void)outlineSidebarView:(TMOutlineSidebarView *)sidebar didSelectItem:(TMOutlineItem *)item {
    if (item) {
        [self.editorTextView jumpToLine:item.lineNumber column:1];
        [self.window makeFirstResponder:self.editorTextView];
        // jumpToLine 已同步更新了 currentCursorLine，顺带把 PDF 也定位到该章节；没有 PDF 时静默跳过
        if (self.currentPDFURL && self.pdfView.document) {
            [self forwardSyncToPDF];
        }
    }
}

- (void)outlineSidebarViewDidRequestToggle:(TMOutlineSidebarView *)sidebar {
    [self toggleOutlineSidebar];
}

#pragma mark - 公共导航动作

- (void)promptGotoLine {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"跳转到行";
    alert.informativeText = [NSString stringWithFormat:@"当前第 %ld 行，请输入目标行号：", (long)self.currentCursorLine];
    [alert addButtonWithTitle:@"跳转"];
    [alert addButtonWithTitle:@"取消"];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    field.placeholderString = @"行号";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        NSInteger line = field.integerValue;
        if (line > 0) {
            [self.editorTextView jumpToLine:line column:1];
            [self.window makeFirstResponder:self.editorTextView];
        }
    }
}

- (IBAction)toggleSidebar:(nullable id)sender {
    [self toggleOutlineSidebar];
}

- (void)toggleLogDrawer {
    [self.logDrawer toggleAnimated];
}

- (void)zoomIn {
    [self.pdfView zoomIn:nil];
}

- (void)zoomOut {
    [self.pdfView zoomOut:nil];
}

#pragma mark - PDF 导航与打印

- (void)pdfPageDidChange:(NSNotification *)note {
    PDFDocument *doc = self.pdfView.document;
    if (!doc) {
        [self.statusBar setPageIndex:0 pageCount:0];
        return;
    }
    PDFPage *page = self.pdfView.currentPage;
    NSInteger idx = page ? [doc indexForPage:page] : 0;
    [self.statusBar setPageIndex:idx pageCount:(NSInteger)doc.pageCount];
}

- (void)pdfNextPage {
    if (self.pdfView.canGoToNextPage) [self.pdfView goToNextPage:nil];
}

- (void)pdfPreviousPage {
    if (self.pdfView.canGoToPreviousPage) [self.pdfView goToPreviousPage:nil];
}

- (void)pdfFitWidth {
    self.pdfView.fitMode = TMPDFFitWidth;
}

- (void)pdfFitPage {
    self.pdfView.fitMode = TMPDFFitPage;
}

- (void)pdfActualSize {
    self.pdfView.fitMode = TMPDFFitManual;
    self.pdfView.scaleFactor = 1.0;
}

- (BOOL)hasPDF {
    return self.pdfView.document != nil;
}

- (void)printPDF {
    if (!self.pdfView.document) return;
    NSPrintInfo *info = [[NSPrintInfo sharedPrintInfo] copy];
    info.horizontalPagination = NSPrintingPaginationModeFit;
    info.verticalPagination = NSPrintingPaginationModeFit;
    [self.pdfView printWithInfo:info autoRotate:YES];
}

#pragma mark - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}

/// 顺序：编译、新建、模板、打开、导出、清理、设置 | …… | 放大、缩小、整页、大纲（右上角）。
/// 左侧操作按钮保持连续，弹性空格只把 PDF 视图操作推到右侧。
/// 保存 / 同步 / 日志按钮已删：⌘S、双击、状态栏"编译日志"够用。
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        @"CompileDoc",
        @"NewDoc",
        @"TemplateDoc",
        @"OpenDoc",
        @"ExportPDF",
        @"CleanAux",
        @"Preferences",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ZoomIn",
        @"ZoomOut",
        @"FitPage",
        @"ToggleOutline"
    ];
}

- (nullable NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:NSToolbarToggleSidebarItemIdentifier] || [itemIdentifier isEqualToString:@"ToggleOutline"]) {
        item.label = @"大纲";
        item.paletteLabel = @"切换大纲视图";
        item.toolTip = @"显示或折叠左侧大纲 (⌘1)";
        item.image = [NSImage imageWithSystemSymbolName:@"sidebar.left" accessibilityDescription:@"Outline"];
        item.target = self;
        item.action = @selector(toggleOutlineSidebar);
    } else if ([itemIdentifier isEqualToString:@"NewDoc"]) {
        item.label = @"新建";
        item.paletteLabel = @"新建文档";
        item.toolTip = @"新建空白文档 (⌘N)";
        item.image = [NSImage imageWithSystemSymbolName:@"doc.badge.plus" accessibilityDescription:@"New"];
        item.target = self;
        item.action = @selector(newDocumentAction:);
    } else if ([itemIdentifier isEqualToString:@"TemplateDoc"]) {
        item.label = @"模板";
        item.paletteLabel = @"从模板新建";
        item.toolTip = @"从预置模板开始";
        item.image = [NSImage imageWithSystemSymbolName:@"square.grid.2x2" accessibilityDescription:@"Templates"];
        item.target = self;
        item.action = @selector(showTemplateMenuAction:);
    } else if ([itemIdentifier isEqualToString:@"OpenDoc"]) {
        item.label = @"打开";
        item.paletteLabel = @"打开文件";
        item.toolTip = @"打开本地 LaTeX 文件 (⌘O)";
        item.image = [NSImage imageWithSystemSymbolName:@"folder" accessibilityDescription:@"Open"];
        item.target = self;
        item.action = @selector(openFileAction:);
    } else if ([itemIdentifier isEqualToString:@"CompileDoc"]) {
        item.label = @"编译 (⌘↩)";
        item.paletteLabel = @"编译文档";
        item.toolTip = @"保存并自动编译生成 PDF (⌘↩)";
        item.image = [NSImage imageWithSystemSymbolName:@"play.circle.fill" accessibilityDescription:@"Compile"];
        item.target = self;
        item.action = @selector(compileCurrentDocument);
    } else if ([itemIdentifier isEqualToString:@"ExportPDF"]) {
        item.label = @"导出 PDF";
        item.paletteLabel = @"导出 PDF";
        item.toolTip = @"把编译好的 PDF 另存到指定位置 (⇧⌘E)";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:@"Export PDF"];
        item.target = self;
        item.action = @selector(exportPDFToolbarAction:);
    } else if ([itemIdentifier isEqualToString:@"CleanAux"]) {
        item.label = @"清理";
        item.paletteLabel = @"清理缓存文件";
        item.toolTip = @"清理 .aux、.log、.bbl 等辅助文件 (⌘K)；⌥⌘↩ 清理后重新编译";
        item.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"Clean"];
        item.target = self;
        item.action = @selector(cleanAuxFilesAction:);
    } else if ([itemIdentifier isEqualToString:@"Preferences"]) {
        item.label = @"设置";
        item.paletteLabel = @"偏好设置";
        item.toolTip = @"打开偏好设置 (⌘,)";
        item.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Preferences"];
        item.target = self;
        item.action = @selector(showPreferencesToolbarAction:);
    } else if ([itemIdentifier isEqualToString:@"ZoomIn"]) {
        item.label = @"放大";
        item.image = [NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:@"Zoom In"];
        item.target = self;
        item.action = @selector(zoomIn);
    } else if ([itemIdentifier isEqualToString:@"FitPage"]) {
        item.label = @"整页";
        item.toolTip = @"PDF 缩放到整页可见 (⌘9)";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.up.left.and.down.right.and.arrow.up.right.and.down.left" accessibilityDescription:@"Fit Page"]
                  ?: [NSImage imageWithSystemSymbolName:@"doc.viewfinder" accessibilityDescription:@"Fit Page"];
        item.target = self;
        item.action = @selector(pdfFitPage);
    } else if ([itemIdentifier isEqualToString:@"ZoomOut"]) {
        item.label = @"缩小";
        item.image = [NSImage imageWithSystemSymbolName:@"minus.magnifyingglass" accessibilityDescription:@"Zoom Out"];
        item.target = self;
        item.action = @selector(zoomOut);
    }

    return item;
}

#pragma mark - 模板与工具栏操作

- (void)newDocumentAction:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"新建文档前是否保存更改？"]) return;
    self.documentModel = [TMDocument documentWithBlankTemplate];
    [self loadDocumentIntoEditor];
}

/// 模板选择：一个简洁的 sheet，三个单选项 + 一句说明，回车即用。
- (void)showTemplateMenuAction:(id)sender {
    // 以后新增预设模板：在这里加一项，并在下面的 switch 里对应处理
    NSArray<TMTemplateItem *> *templates = @[
        [TMTemplateItem itemWithTitle:@"学术论文" subtitle:@"article · amsmath · pdfLaTeX，含标题、章节与公式示例" symbol:@"graduationcap"],
        [TMTemplateItem itemWithTitle:@"中文报告" subtitle:@"ctexart · 自动使用 XeLaTeX，含中文排版与操作提示" symbol:@"doc.richtext"],
        [TMTemplateItem itemWithTitle:@"空白文档" subtitle:@"最小 article 骨架，只有 document 环境" symbol:@"doc"],
    ];
    [TMTemplatePicker presentWithItems:templates forWindow:self.window completion:^(NSInteger index) {
        switch (index) {
            case 0: [self applyDefaultTemplate:nil]; break;
            case 1: [self applyChineseTemplate:nil]; break;
            default: [self applyBlankTemplate:nil]; break;
        }
    }];
}

- (void)applyDefaultTemplate:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"切换模板前是否保存更改？"]) return;
    self.documentModel = [TMDocument documentWithDefaultTemplate];
    [self loadDocumentIntoEditor];
    [self compileCurrentDocument];
}

- (void)applyChineseTemplate:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"切换模板前是否保存更改？"]) return;
    // 不强行切引擎：自动模式会根据 ctex 选 XeLaTeX，用户手选的引擎也不应被模板覆盖
    self.documentModel = [TMDocument documentWithChineseTemplate];
    [self loadDocumentIntoEditor];
    [self compileCurrentDocument];
}

- (void)applyBlankTemplate:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"切换模板前是否保存更改？"]) return;
    self.documentModel = [TMDocument documentWithBlankTemplate];
    [self loadDocumentIntoEditor];
}

- (void)openFileAction:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.message = @"选择 .tex / .bib / .sty 等文件，或直接选择一个项目文件夹";
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObject:UTTypeFolder];
    for (NSString *ext in [TMProject editableExtensions]) {
        UTType *t = [UTType typeWithFilenameExtension:ext];
        if (t) [types addObject:t];
    }
    [types addObject:UTTypePlainText];
    panel.allowedContentTypes = types;
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        [self openDocumentAtURL:panel.URL];
    }
}

- (void)openFolderAction:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.message = @"选择包含 .tex 文件的项目文件夹";
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        [self openFolderAtURL:panel.URL];
    }
}

- (void)cleanAuxFilesAction:(id)sender {
    [self cleanAuxiliaryFilesForMainFile];
    [self.statusBar showInfoMessage:@"已清理辅助文件"];
}

/// 清理的是实际编译的主文件（用 % !TEX root 或多文件项目时不是当前文件）。
- (void)cleanAuxiliaryFilesForMainFile {
    [self cleanAuxiliaryFilesForMainFileKeepingBibliography:NO];
}

/// keepBibliography：保留源文件旁的 .bbl（自动清理且它无法重新生成时）。
- (void)cleanAuxiliaryFilesForMainFileKeepingBibliography:(BOOL)keepBibliography {
    NSURL *main = [self mainFileURLForCompile];
    if (!main) return;
    // 缓存目录整个删掉；源文件旁的也清一遍（切换设置前或旧版本留下的）
    [[NSFileManager defaultManager] removeItemAtURL:[TMCompiler auxiliaryDirectoryForTeXFileURL:main] error:nil];
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:main keepingBibliography:keepBibliography];
    if (![main isEqual:self.documentModel.fileURL]) [self.documentModel cleanAuxiliaryFiles];
    [self.outlineSidebarView.fileBrowserView reload];
}

- (void)cleanAndRebuild {
    if ([self isCompiling]) [self cancelCompilation];
    [self cleanAuxiliaryFilesForMainFile];
    [self compileCurrentDocument];
}

- (void)exportPDFToolbarAction:(id)sender {
    [self exportPDF];
}

- (void)showPreferencesToolbarAction:(id)sender {
    [[TMPreferencesWindowController shared] showPreferences];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    // 首页上只留新建 / 模板 / 打开
    if ([self isShowingWelcome]) {
        return item.action == @selector(newDocumentAction:) || item.action == @selector(showTemplateMenuAction:) ||
               item.action == @selector(openFileAction:);
    }
    if (item.action == @selector(exportPDFToolbarAction:)) {
        return self.currentPDFURL != nil;
    }
    return YES;
}

@end
