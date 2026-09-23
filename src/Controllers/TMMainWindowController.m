#import "TMMainWindowController.h"
#import "TMEditorTextView.h"
#import "TMLineNumberRulerView.h"
#import "TMPDFView.h"
#import "TMStatusBarView.h"
#import "TMLogDrawerView.h"
#import "TMCompiler.h"
#import "TMSyncTeX.h"
#import "TMOutlineSidebarView.h"
#import "TMOutlineParser.h"
#import "TMRecentFiles.h"
#import "TMProject.h"
#import "TMFileWatcher.h"
#import "TMPreferences.h"
#import "TMLaTeXHighlighter.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const kTMDefaultsOutlineCollapsed = @"TMOutlineCollapsed";

@interface TMMainWindowController () <NSToolbarDelegate, NSSplitViewDelegate, TMEditorTextViewDelegate, TMPDFViewDelegate, TMCompilerDelegate, TMStatusBarViewDelegate, TMOutlineSidebarViewDelegate, TMFileBrowserViewDelegate, TMLogDrawerViewDelegate>

// 外层：系统 NSSplitViewController 负责侧边栏折叠、分割线隐藏、宽度记忆
@property (nonatomic, strong) NSSplitViewController *mainSplitViewController;
@property (nonatomic, strong) NSSplitViewItem *sidebarItem;
@property (nonatomic, strong) TMOutlineSidebarView *outlineSidebarView;
// 内层：代码 | PDF
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) TMEditorTextView *editorTextView;
@property (nonatomic, strong) NSScrollView *editorScrollView;
@property (nonatomic, strong) TMLineNumberRulerView *lineNumberRuler;
/// 最近一次编译解析出的问题，切换文件时据此重画行号槽标记。
@property (nonatomic, copy) NSArray<TMLogIssue *> *lastIssues;
@property (nonatomic, strong) NSView *pdfContainerView;
@property (nonatomic, strong) TMPDFView *pdfView;
@property (nonatomic, strong) NSView *pdfPlaceholderView;
@property (nonatomic, strong) TMStatusBarView *statusBar;
@property (nonatomic, strong) TMLogDrawerView *logDrawer;

@property (nonatomic, assign) NSInteger currentCursorLine;
@property (nonatomic, assign) NSInteger currentCursorCol;
@property (nonatomic, strong, nullable) NSTimer *outlineDebounceTimer;
@property (nonatomic, strong, nullable) NSTimer *autoCompileTimer;
@property (nonatomic, assign) BOOL needsCompileAfterCurrent;
@property (nonatomic, strong, readwrite, nullable) NSURL *currentPDFURL;
@property (nonatomic, strong, readwrite, nullable) NSURL *projectRootURL;
@property (nonatomic, strong) TMCompletionProvider *completionProvider;
@property (nonatomic, strong, nullable) TMFileWatcher *fileWatcher;
/// 上次我们自己读 / 写磁盘文件时的修改时间，用来判断是否有外部改动。
@property (nonatomic, strong, nullable) NSDate *knownModificationDate;
@property (nonatomic, assign) BOOL isShowingExternalChangeAlert;

@end

@implementation TMMainWindowController

- (instancetype)initWithDocument:(TMDocument *)document {
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
        [self loadDocumentIntoEditor];

        // 侧边栏折叠状态：等 UI 建好后再应用，避免动画
        self.sidebarItem.collapsed = [defaults boolForKey:kTMDefaultsOutlineCollapsed];

        // 窗口位置/大小交给系统自动保存
        [window setFrameAutosaveName:@"TMMainWindow"];

        // 首次打开未命名欢迎模板时，暂存到临时目录并触发初次编译，让用户第一眼看到分栏预览。
        // 注意用 saveScratchToURL: 而非 saveToURL:，否则之后 ⌘S 会静默写回 /tmp。
        if (!_documentModel.fileURL) {
            NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TeXMini_Welcome.tex"];
            NSURL *tmpURL = [NSURL fileURLWithPath:tmpPath];
            [_documentModel saveScratchToURL:tmpURL error:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self compileCurrentDocument];
            });
        }
    }
    return self;
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

    [_splitView addSubview:_pdfContainerView];

    // 将工作区分栏包成 NSSplitViewItem 加入外层
    NSViewController *contentVC = [[NSViewController alloc] init];
    contentVC.view = _splitView;
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
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_statusBar];

    // 自动布局约束
    [NSLayoutConstraint activateConstraints:@[
        [mainSplitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [mainSplitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [mainSplitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [mainSplitView.bottomAnchor constraintEqualToAnchor:_logDrawer.topAnchor],

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

    NSTextField *subLabel = [NSTextField labelWithString:@"在左侧编辑代码，按 ⌘B 自动保存并编译"];
    subLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
    subLabel.textColor = [NSColor secondaryLabelColor];
    subLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_pdfPlaceholderView addSubview:subLabel];

    NSButton *compileBtn = [NSButton buttonWithTitle:@"▶ 立即编译预览 (⌘B)" target:self action:@selector(compileCurrentDocument)];
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

    _autoCompileEnabled = p.autoCompileEnabled;
    if (!_autoCompileEnabled) {
        [self.autoCompileTimer invalidate];
        self.autoCompileTimer = nil;
    }
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

#pragma mark - 文档管理与加载

- (void)loadDocumentIntoEditor {
    if (self.documentModel) {
        self.editorTextView.string = self.documentModel.content ?: @"";
        [self.editorTextView.undoManager removeAllActions];
        [self.editorTextView rehighlightAll];
        [self scheduleOutlineUpdateImmediate:YES];
        [self refreshWindowTitle];
        [self syncProjectRootWithDocument];
        [self startWatchingCurrentFile];
        [self refreshIssueMarks];
        // 预览主文件的 PDF：编辑 chapters/ch1.tex 时右侧仍应显示 main.pdf
        [self showPDFIfExistsAtURL:[self expectedPDFURLForMainFile]];
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
    self.outlineSidebarView.mode = TMSidebarModeFiles;
    if (self.sidebarItem.isCollapsed) [self toggleOutlineSidebar];

    NSURL *main = [TMProject guessMainFileInDirectory:folderURL];
    if (main) {
        [self openDocumentAtURL:main];
    } else {
        [self.statusBar showInfoMessage:[NSString stringWithFormat:@"已打开文件夹 %@，未找到含 \\documentclass 的主文件", folderURL.lastPathComponent]];
    }
}

/// 决定 ⌘B 实际编译哪个文件：暂存文档就是自己；否则按魔法注释 / \documentclass / 同目录引用推断。
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
    self.window.title = [NSString stringWithFormat:@"TeXMini - %@", self.documentModel.displayName];
    self.window.representedURL = self.documentModel.isScratch ? nil : self.documentModel.fileURL;
    self.window.documentEdited = self.documentModel.isDirty;
}

- (BOOL)hasUnsavedChanges {
    return self.documentModel.isDirty;
}

/// 在丢弃当前文档前询问用户。返回 YES 表示可以继续（已保存或用户选择不保存）。
- (BOOL)confirmDiscardChangesWithTitle:(NSString *)title {
    if (![self hasUnsavedChanges]) return YES;

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
        alert.informativeText = @"请先按下 ⌘B 进行编译，成功生成 PDF 后方可导出。";
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

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (![self confirmDiscardChangesWithTitle:@"关闭窗口前是否保存更改？"]) return NO;
    // 用户已决定（保存或放弃），避免随后的 applicationShouldTerminate 再问一次
    self.documentModel.isDirty = NO;
    return YES;
}

#pragma mark - 编译动作与回调

- (void)compileCurrentDocument {
    self.documentModel.content = self.editorTextView.string;

    // 如果还没有指定文件路径，暂存到临时工作空间，省去弹窗干扰
    if (!self.documentModel.fileURL) {
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"TeXMini_Document.tex"];
        NSURL *tmpURL = [NSURL fileURLWithPath:tmpPath];
        [self.documentModel saveScratchToURL:tmpURL error:nil];
    } else {
        [self.documentModel saveCurrentFileWithError:nil];
        [self didWriteCurrentFile];
        [self refreshWindowTitle];
    }

    [self.logDrawer clearLog];
    self.lastIssues = @[];
    [self refreshIssueMarks];
    [[TMCompiler sharedCompiler] compileFileAtURL:[self mainFileURLForCompile]];
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
    [self.completionProvider invalidate];
}

- (void)cancelCompilation {
    [[TMCompiler sharedCompiler] cancelCompilation];
}

- (BOOL)isCompiling {
    return [TMCompiler sharedCompiler].isCompiling;
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
    NSString *engineName = [[TMCompiler sharedCompiler] effectiveEngineNameForContent:content];
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
    NSUInteger warnings = [TMLogParser countOfKind:TMLogIssueWarning inIssues:issues];
    NSUInteger badBoxes = [TMLogParser countOfKind:TMLogIssueBadBox inIssues:issues];
    [self.statusBar showSuccessStateWithDuration:durationSeconds warnings:warnings badBoxes:badBoxes];
    self.lastIssues = issues;
    [self.logDrawer setIssues:issues];
    [self refreshIssueMarks];
    self.currentPDFURL = pdfURL;
    self.pdfPlaceholderView.hidden = YES;
    [self.pdfView loadPDFFromURL:pdfURL preservingViewport:YES];
    [self.outlineSidebarView.fileBrowserView reload];
    [self runPendingAutoCompileIfNeeded];
}

- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues {
    [self.statusBar showErrorStateWithMessage:summary line:lineNumber];
    self.lastIssues = issues;
    [self.logDrawer setIssues:issues];
    [self refreshIssueMarks];
    if (!self.logDrawer.isExpanded) {
        [self.logDrawer toggleAnimated];
    }
    [self runPendingAutoCompileIfNeeded];
}

- (void)compilerDidCancel {
    [self.statusBar showInfoMessage:@"已取消编译"];
    [self runPendingAutoCompileIfNeeded];
}

#pragma mark - SyncTeX 双向同步

- (void)forwardSyncToPDF {
    if (!self.documentModel.fileURL) return;
    if (!self.currentPDFURL || !self.pdfView.document) {
        [self.statusBar showInfoMessage:@"还没有 PDF，请先 ⌘B 编译"];
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
    if (!self.documentModel.isDirty) {
        self.documentModel.isDirty = YES;
        self.window.documentEdited = YES;
    }
    [self scheduleOutlineUpdateImmediate:NO];
    [self scheduleAutoCompile];
}

- (void)editorTextViewDidChangeCursorPositionToLine:(NSInteger)line column:(NSInteger)column {
    self.currentCursorLine = line;
    self.currentCursorCol = column;
    [self.statusBar setCursorLine:line column:column];
    [self.outlineSidebarView highlightItemForLineNumber:line];
}

- (void)updateWordCount {
    NSString *text = self.editorTextView.string;
    __block NSUInteger words = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length)
                             options:NSStringEnumerationByWords | NSStringEnumerationSubstringNotRequired
                          usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        words++;
    }];
    [self.statusBar setWordCount:words];
}

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
    NSArray<TMOutlineItem *> *rootItems = [TMOutlineParser parseOutlineFromLaTeXString:content flatList:&flatList];
    [self.outlineSidebarView updateWithRootItems:rootItems flatItems:flatList];
    [self.outlineSidebarView highlightItemForLineNumber:self.currentCursorLine];
    [self updateWordCount];
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
    self.pdfView.autoScales = YES;
}

- (void)pdfActualSize {
    self.pdfView.autoScales = NO;
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
    return @[
        NSToolbarToggleSidebarItemIdentifier,
        @"ToggleOutline",
        NSToolbarSpaceItemIdentifier,
        @"NewDoc",
        @"TemplateDoc",
        @"OpenDoc",
        @"SaveDoc",
        NSToolbarSpaceItemIdentifier,
        @"CompileDoc",
        @"ForwardSync",
        @"ExportPDF",
        @"CleanAux",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ZoomIn",
        @"ZoomOut",
        @"ToggleLog"
    ];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[
        NSToolbarToggleSidebarItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        @"NewDoc",
        @"TemplateDoc",
        @"OpenDoc",
        @"SaveDoc",
        NSToolbarSpaceItemIdentifier,
        @"CompileDoc",
        @"ForwardSync",
        @"ExportPDF",
        @"CleanAux",
        NSToolbarFlexibleSpaceItemIdentifier,
        @"ZoomIn",
        @"ZoomOut",
        @"ToggleLog"
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
    } else if ([itemIdentifier isEqualToString:@"SaveDoc"]) {
        item.label = @"保存";
        item.paletteLabel = @"保存文件";
        item.toolTip = @"保存当前代码 (⌘S)";
        item.image = [NSImage imageWithSystemSymbolName:@"square.and.arrow.down" accessibilityDescription:@"Save"];
        item.target = self;
        item.action = @selector(saveCurrentDocument);
    } else if ([itemIdentifier isEqualToString:@"CompileDoc"]) {
        item.label = @"编译 (⌘B)";
        item.paletteLabel = @"编译文档";
        item.toolTip = @"保存并自动编译生成 PDF (⌘B)";
        item.image = [NSImage imageWithSystemSymbolName:@"play.circle.fill" accessibilityDescription:@"Compile"];
        item.target = self;
        item.action = @selector(compileCurrentDocument);
    } else if ([itemIdentifier isEqualToString:@"ForwardSync"]) {
        item.label = @"同步 (⌘J)";
        item.paletteLabel = @"正向跳转至 PDF";
        item.toolTip = @"从代码光标跳转到 PDF 对应位置 (⌘J、双击或 ⌘+点击代码)";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.right.circle" accessibilityDescription:@"Sync to PDF"];
        item.target = self;
        item.action = @selector(forwardSyncToPDF);
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
        item.toolTip = @"清理 .aux、.log、.bbl 等辅助文件 (⌘K)；⌥⌘B 清理后重新编译";
        item.image = [NSImage imageWithSystemSymbolName:@"trash" accessibilityDescription:@"Clean"];
        item.target = self;
        item.action = @selector(cleanAuxFilesAction:);
    } else if ([itemIdentifier isEqualToString:@"ZoomIn"]) {
        item.label = @"放大";
        item.image = [NSImage imageWithSystemSymbolName:@"plus.magnifyingglass" accessibilityDescription:@"Zoom In"];
        item.target = self;
        item.action = @selector(zoomIn);
    } else if ([itemIdentifier isEqualToString:@"ZoomOut"]) {
        item.label = @"缩小";
        item.image = [NSImage imageWithSystemSymbolName:@"minus.magnifyingglass" accessibilityDescription:@"Zoom Out"];
        item.target = self;
        item.action = @selector(zoomOut);
    } else if ([itemIdentifier isEqualToString:@"ToggleLog"]) {
        item.label = @"日志";
        item.image = [NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:@"Toggle Log"];
        item.target = self;
        item.action = @selector(toggleLogDrawer);
    }

    return item;
}

#pragma mark - 模板与工具栏操作

- (void)newDocumentAction:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"新建文档前是否保存更改？"]) return;
    self.documentModel = [TMDocument documentWithBlankTemplate];
    [self loadDocumentIntoEditor];
}

- (void)showTemplateMenuAction:(id)sender {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Templates"];
    [menu addItemWithTitle:@"📄 学术论文模板 (Article / Math)" action:@selector(applyDefaultTemplate:) keyEquivalent:@""];
    [menu addItemWithTitle:@"🇨🇳 中文研究报告 (CTeX / XeLaTeX)" action:@selector(applyChineseTemplate:) keyEquivalent:@""];
    [menu addItemWithTitle:@"📝 纯净空白文档 (Blank)" action:@selector(applyBlankTemplate:) keyEquivalent:@""];

    NSView *targetView = [sender isKindOfClass:[NSView class]] ? sender : self.window.contentView;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(80, self.window.contentView.bounds.size.height - 40) inView:targetView];
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
    NSURL *main = [self mainFileURLForCompile];
    if (!main) return;
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:main];
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

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if (item.action == @selector(exportPDFToolbarAction:)) {
        return self.currentPDFURL != nil;
    }
    return YES;
}

@end
