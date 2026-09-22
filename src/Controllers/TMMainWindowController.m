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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface TMMainWindowController () <NSToolbarDelegate, NSSplitViewDelegate, TMEditorTextViewDelegate, TMPDFViewDelegate, TMCompilerDelegate, TMStatusBarViewDelegate, TMOutlineSidebarViewDelegate>

@property (nonatomic, strong) NSSplitView *mainSplitView;
@property (nonatomic, strong) TMOutlineSidebarView *outlineSidebarView;
@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) TMEditorTextView *editorTextView;
@property (nonatomic, strong) NSScrollView *editorScrollView;
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
@property (nonatomic, assign) CGFloat lastOutlineWidth;
@property (nonatomic, assign) BOOL isOutlineCollapsed;

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
        _documentModel = document ?: [TMDocument documentWithDefaultTemplate];
        _currentCursorLine = 1;
        _currentCursorCol = 1;
        _lastOutlineWidth = 220.0;
        _isOutlineCollapsed = NO;
        _autoCompileEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"TMAutoCompile"];
        window.delegate = self;

        [self setupUI];
        [self setupToolbar];
        [TMCompiler sharedCompiler].delegate = self;
        [self loadDocumentIntoEditor];

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

    _lastOutlineWidth = 220.0;

    // 1. 外层水平分栏 (MainSplitView: 左大纲侧边栏 + 右工作区分栏)
    _mainSplitView = [[NSSplitView alloc] initWithFrame:bounds];
    _mainSplitView.vertical = YES;
    _mainSplitView.dividerStyle = NSSplitViewDividerStyleThin;
    _mainSplitView.delegate = self;
    _mainSplitView.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_mainSplitView];

    // 1.1 大纲侧边栏
    _outlineSidebarView = [[TMOutlineSidebarView alloc] initWithFrame:NSMakeRect(0, 0, _lastOutlineWidth, bounds.size.height)];
    _outlineSidebarView.delegate = self;
    [_mainSplitView addSubview:_outlineSidebarView];

    // 1.2 内层工作区分栏 (ContentSplitView: 代码编辑 + PDF 预览)
    CGFloat contentWidth = MAX(400, bounds.size.width - _lastOutlineWidth - 1.0);
    _splitView = [[NSSplitView alloc] initWithFrame:NSMakeRect(_lastOutlineWidth + 1.0, 0, contentWidth, bounds.size.height)];
    _splitView.vertical = YES;
    _splitView.dividerStyle = NSSplitViewDividerStyleThin;
    _splitView.delegate = self;
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
    [_editorTextView setupEditor];

    _editorScrollView.documentView = _editorTextView;

    TMLineNumberRulerView *ruler = [[TMLineNumberRulerView alloc] initWithScrollView:_editorScrollView];
    _editorScrollView.verticalRulerView = ruler;

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

    // 占位视图 (当未编译出 PDF 时显示提示)
    [self setupPlaceholderView];
    [_pdfContainerView addSubview:_pdfPlaceholderView];

    [_splitView addSubview:_pdfContainerView];

    // 将工作区分栏加入外层主分栏
    [_mainSplitView addSubview:_splitView];

    // 设置侧边栏固定倾向、工作区拉伸倾向
    [_mainSplitView setHoldingPriority:NSLayoutPriorityDefaultHigh forSubviewAtIndex:0];
    [_mainSplitView setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];

    // 2. 抽屉式日志视图
    _logDrawer = [[TMLogDrawerView alloc] init];
    _logDrawer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_logDrawer];

    // 3. 底部状态栏
    _statusBar = [[TMStatusBarView alloc] init];
    _statusBar.delegate = self;
    _statusBar.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:_statusBar];

    // 自动布局约束
    [NSLayoutConstraint activateConstraints:@[
        [_mainSplitView.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [_mainSplitView.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_mainSplitView.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_mainSplitView.bottomAnchor constraintEqualToAnchor:_logDrawer.topAnchor],

        [_logDrawer.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_logDrawer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_logDrawer.bottomAnchor constraintEqualToAnchor:_statusBar.topAnchor],

        [_statusBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [_statusBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [_statusBar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [_statusBar.heightAnchor constraintEqualToConstant:28]
    ]];

    // 初始均分左右分栏与大纲侧边栏
    [self layoutMainSplitView];
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

#pragma mark - NSSplitView 分栏布局与控制

- (void)layoutMainSplitView {
    NSRect bounds = self.mainSplitView.bounds;
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return;

    CGFloat d = self.mainSplitView.dividerThickness;

    if (self.isOutlineCollapsed) {
        self.outlineSidebarView.hidden = YES;
        self.outlineSidebarView.frame = NSMakeRect(0, 0, 0, bounds.size.height);
        self.splitView.frame = bounds;
    } else {
        self.outlineSidebarView.hidden = NO;
        CGFloat sidebarW = self.lastOutlineWidth;
        if (sidebarW < 160.0 || sidebarW > 380.0) {
            sidebarW = 220.0;
        }
        if (bounds.size.width > 600.0) {
            sidebarW = MIN(sidebarW, bounds.size.width - 400.0);
        }
        CGFloat contentW = MAX(0, bounds.size.width - sidebarW - d);

        self.outlineSidebarView.frame = NSMakeRect(0, 0, sidebarW, bounds.size.height);
        self.splitView.frame = NSMakeRect(sidebarW + d, 0, contentW, bounds.size.height);
    }
    [self.splitView adjustSubviews];
}

#pragma mark - NSSplitViewDelegate (保证分栏永不塌陷、主侧边栏可折叠)

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    return NO;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex {
    if (splitView == self.mainSplitView && dividerIndex == 0) {
        return self.isOutlineCollapsed || self.outlineSidebarView.isHidden || self.outlineSidebarView.frame.size.width <= 0;
    }
    return NO;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.mainSplitView) {
        return 160.0;
    }
    return 280.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
    if (splitView == self.mainSplitView) {
        return 380.0;
    }
    return splitView.bounds.size.width - 280.0;
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    if (splitView == self.mainSplitView) {
        [self layoutMainSplitView];
    } else if (splitView == self.splitView) {
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
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    if (notification.object == self.mainSplitView && !self.isOutlineCollapsed) {
        CGFloat w = self.outlineSidebarView.frame.size.width;
        if (w >= 160.0 && w <= 380.0) {
            self.lastOutlineWidth = w;
        }
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

        // 判断是否存在对应 PDF
        if (self.documentModel.expectedPDFURL && [[NSFileManager defaultManager] fileExistsAtPath:self.documentModel.expectedPDFURL.path]) {
            [self.pdfView loadPDFFromURL:self.documentModel.expectedPDFURL];
            self.pdfPlaceholderView.hidden = YES;
        } else {
            self.pdfPlaceholderView.hidden = NO;
        }
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
    if (![self confirmDiscardChangesWithTitle:@"打开其他文件前是否保存更改？"]) return;

    NSError *error = nil;
    TMDocument *newDoc = [TMDocument documentWithContentsOfURL:url error:&error];
    if (newDoc) {
        self.documentModel = newDoc;
        [self loadDocumentIntoEditor];
        [self.statusBar showReadyState];
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
    // 换了目录后旧的 PDF 不再对应，重新判断预览
    if (self.documentModel.expectedPDFURL && [[NSFileManager defaultManager] fileExistsAtPath:self.documentModel.expectedPDFURL.path]) {
        [self.pdfView loadPDFFromURL:self.documentModel.expectedPDFURL];
        self.pdfPlaceholderView.hidden = YES;
    } else {
        self.pdfPlaceholderView.hidden = NO;
    }
    return YES;
}

#pragma mark - NSWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    return [self confirmDiscardChangesWithTitle:@"关闭窗口前是否保存更改？"];
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
        [self refreshWindowTitle];
    }

    [self.logDrawer clearLog];
    [[TMCompiler sharedCompiler] compileFileAtURL:self.documentModel.fileURL];
}

- (void)cancelCompilation {
    [[TMCompiler sharedCompiler] cancelCompilation];
}

- (BOOL)isCompiling {
    return [TMCompiler sharedCompiler].isCompiling;
}

#pragma mark - 自动编译

- (void)setAutoCompileEnabled:(BOOL)enabled {
    _autoCompileEnabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"TMAutoCompile"];
    if (!enabled) {
        [self.autoCompileTimer invalidate];
        self.autoCompileTimer = nil;
    }
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
    self.pdfPlaceholderView.hidden = YES;
    [self.pdfView loadPDFFromURL:pdfURL preservingViewport:YES];
    [self runPendingAutoCompileIfNeeded];
}

- (void)compilerDidFailWithError:(NSString *)summary line:(NSInteger)lineNumber fullLog:(NSString *)log issues:(NSArray<TMLogIssue *> *)issues {
    [self.statusBar showErrorStateWithMessage:summary line:lineNumber];
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
    if (!self.documentModel.fileURL || !self.documentModel.expectedPDFURL) return;

    NSString *src = self.documentModel.fileURL.path;
    NSString *pdf = self.documentModel.expectedPDFURL.path;

    TMSyncTeXResult *res = [TMSyncTeX forwardSearchLine:self.currentCursorLine
                                                 column:self.currentCursorCol
                                             sourceFile:src
                                                pdfPath:pdf
                                               pdfView:self.pdfView];
    if (res) {
        [self.pdfView flashHighlightRect:res.targetRect onPageAtIndex:res.pageIndex];
    }
}

- (void)pdfViewDidRequestInverseSearchAtPoint:(NSPoint)pointOnPage pageIndex:(NSInteger)pageIndex pageBounds:(NSRect)pageBounds {
    if (!self.documentModel.expectedPDFURL) return;

    NSString *pdf = self.documentModel.expectedPDFURL.path;
    TMSyncTeXResult *res = [TMSyncTeX inverseSearchPoint:pointOnPage
                                               pageIndex:pageIndex
                                              pageBounds:pageBounds
                                                 pdfPath:pdf];
    if (!res || res.sourceLine <= 0) return;

    // SyncTeX 返回的文件名可能是相对 PDF 目录的路径；与当前文档不一致时不能盲目跳行。
    if (res.sourceFilePath.length > 0 && self.documentModel.fileURL) {
        NSURL *pdfDir = self.documentModel.expectedPDFURL.URLByDeletingLastPathComponent;
        NSURL *target = [NSURL fileURLWithPath:res.sourceFilePath relativeToURL:pdfDir];
        NSString *targetPath = target.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
        NSString *currentPath = self.documentModel.fileURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
        if (targetPath && currentPath && ![targetPath isEqualToString:currentPath]) {
            NSBeep();
            [self.statusBar showInfoMessage:[NSString stringWithFormat:@"该位置来自 %@ 第 %ld 行（当前未打开）",
                                             targetPath.lastPathComponent, (long)res.sourceLine]];
            return;
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
    self.editorTextView.editorFontSize = self.editorTextView.editorFontSize + 1.0;
}

- (void)decreaseEditorFontSize {
    self.editorTextView.editorFontSize = self.editorTextView.editorFontSize - 1.0;
}

- (void)resetEditorFontSize {
    self.editorTextView.editorFontSize = 13.5;
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
    [TMCompiler sharedCompiler].engine = engine;
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
    if (!self.isOutlineCollapsed) {
        // 收起大纲
        CGFloat currentW = self.outlineSidebarView.frame.size.width;
        if (currentW >= 160.0 && currentW <= 380.0) {
            self.lastOutlineWidth = currentW;
        }
        self.isOutlineCollapsed = YES;
    } else {
        // 展开大纲
        self.isOutlineCollapsed = NO;
    }

    [self layoutMainSplitView];
    [self.mainSplitView adjustSubviews];
}

#pragma mark - TMOutlineSidebarViewDelegate

- (void)outlineSidebarView:(TMOutlineSidebarView *)sidebar didSelectItem:(TMOutlineItem *)item {
    if (item) {
        [self.editorTextView jumpToLine:item.lineNumber column:1];
        [self.window makeFirstResponder:self.editorTextView];
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
        item.toolTip = @"从代码光标跳转到 PDF 对应位置 (⌘J)";
        item.image = [NSImage imageWithSystemSymbolName:@"arrow.right.circle" accessibilityDescription:@"Sync to PDF"];
        item.target = self;
        item.action = @selector(forwardSyncToPDF);
    } else if ([itemIdentifier isEqualToString:@"CleanAux"]) {
        item.label = @"清理";
        item.paletteLabel = @"清理缓存文件";
        item.toolTip = @"清理 .aux、.log、.fls 等缓存文件";
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
    [self.statusBar setSelectedEngine:TMTeXEngineLatexmk];
    [TMCompiler sharedCompiler].engine = TMTeXEngineLatexmk;
    [self loadDocumentIntoEditor];
    [self compileCurrentDocument];
}

- (void)applyChineseTemplate:(id)sender {
    if (![self confirmDiscardChangesWithTitle:@"切换模板前是否保存更改？"]) return;
    self.documentModel = [TMDocument documentWithChineseTemplate];
    [self.statusBar setSelectedEngine:TMTeXEngineXeLaTeX];
    [TMCompiler sharedCompiler].engine = TMTeXEngineXeLaTeX;
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
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"tex"] ?: UTTypePlainText];
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        [self openDocumentAtURL:panel.URL];
    }
}

- (void)cleanAuxFilesAction:(id)sender {
    [self.documentModel cleanAuxiliaryFiles];
    [self.statusBar showReadyState];
}

@end
