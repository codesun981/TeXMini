#import "TMWelcomeView.h"
#import "TMRecentFiles.h"
#import "TMPreferences.h"
#import "TMCompiler.h"
#import "TMHoverControl.h"
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSUInteger kTMWelcomeRecentLimit = 20;
/// 最近列表最多同时露出的行数，超出部分滚动查看（不显示滚动条）。
static const NSUInteger kTMWelcomeVisibleRows = 6;
static const CGFloat kTMWelcomeRowHeight = 40;
static const CGFloat kTMWelcomeRowSpacing = 2;
static const CGFloat kTMWelcomeContentWidth = 676;

static NSString *TMRelativeDateString(NSDate *date) {
    if (!date) return @"";
    NSTimeInterval elapsed = -[date timeIntervalSinceNow];
    if (elapsed < 60)             return @"刚刚";
    if (elapsed < 3600)           return [NSString stringWithFormat:@"%ld 分钟前", (long)(elapsed / 60)];
    if (elapsed < 86400)          return [NSString stringWithFormat:@"%ld 小时前", (long)(elapsed / 3600)];
    if (elapsed < 86400 * 2)      return @"昨天";
    if (elapsed < 86400 * 7)      return [NSString stringWithFormat:@"%ld 天前", (long)(elapsed / 86400)];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy/MM/dd";
    return [df stringFromDate:date];
}

static NSImage *TMSymbol(NSString *name, CGFloat pointSize, NSFontWeight weight) {
    NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    return [img imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight]];
}

static NSImageView *TMSymbolView(NSString *name, CGFloat pointSize, NSColor *tint) {
    NSImageView *v = [NSImageView imageViewWithImage:TMSymbol(name, pointSize, NSFontWeightRegular)];
    v.contentTintColor = tint;
    return v;
}

/// 小圆角“键帽”标签：⌘N、Esc 等。
static NSTextField *TMKeyCapLabel(NSString *text) {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    f.textColor = [NSColor secondaryLabelColor];
    f.alignment = NSTextAlignmentCenter;
    f.wantsLayer = YES;
    f.layer.cornerRadius = 4;
    f.layer.borderWidth = 0.5;
    f.layer.borderColor = [NSColor separatorColor].CGColor;
    f.layer.backgroundColor = [[NSColor labelColor] colorWithAlphaComponent:0.04].CGColor;
    [f.widthAnchor constraintGreaterThanOrEqualToConstant:28].active = YES;
    [f.heightAnchor constraintEqualToConstant:18].active = YES;
    return f;
}

#pragma mark - 顶部对齐的滚动容器

/// 翻转坐标：列表从顶部开始排，内容不足时不会沉到底部。
@interface TMFlippedClipView : NSClipView
@end

@implementation TMFlippedClipView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - TMWelcomeView 主视图实现

@interface TMWelcomeView () <NSTextFieldDelegate>
@property (nonatomic, strong) NSStackView *recentStack;
@property (nonatomic, strong) NSTextField *recentCountLabel;
@property (nonatomic, strong) NSTextField *filterField;
@property (nonatomic, strong) NSScrollView *recentScroll;
@property (nonatomic, strong) NSLayoutConstraint *recentScrollHeight;
@property (nonatomic, strong) NSButton *restoreCheck;
@property (nonatomic, strong) NSStackView *escHint;
@property (nonatomic, strong) NSImageView *logoImageView;
@property (nonatomic, strong) NSTextField *engineStatusLabel;
@property (nonatomic, strong) NSView *engineDot;
@property (nonatomic, strong) NSView *dropHighlight;
@property (nonatomic, copy) NSArray<NSURL *> *recentURLs;
@end

@implementation TMWelcomeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self buildUI];
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer {
    self.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
}
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)cancelOperation:(id)sender {
    if (self.filterField.stringValue.length > 0) {
        self.filterField.stringValue = @"";
        [self rebuildRecentRows];
        [self.window makeFirstResponder:self];
        return;
    }
    if (self.showsDismissButton) [self.delegate welcomeViewDidRequestDismiss:self];
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if (!self.hidden && flags == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers isEqualToString:@"k"]) {
        [self.window makeFirstResponder:self.filterField];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)mouseDown:(NSEvent *)event {}

#pragma mark - 构建界面

- (NSImage *)resolveAppLogoImage {
    NSImage *img = [[NSBundle mainBundle] imageForResource:@"icon"];
    if (!img) img = NSApp.applicationIconImage ?: [NSImage imageNamed:NSImageNameApplicationIcon];
    return img;
}

- (void)buildUI {
    self.wantsLayer = YES;

    // ── Logo + 标题区 ──────────────────────────────────────────
    _logoImageView = [NSImageView imageViewWithImage:[self resolveAppLogoImage]];
    _logoImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _logoImageView.wantsLayer = YES;
    _logoImageView.shadow = [[NSShadow alloc] init];
    _logoImageView.layer.shadowColor = [NSColor blackColor].CGColor;
    _logoImageView.layer.shadowOpacity = 0.18;
    _logoImageView.layer.shadowRadius = 10;
    _logoImageView.layer.shadowOffset = CGSizeMake(0, -4);
    [_logoImageView.widthAnchor constraintEqualToConstant:84].active = YES;
    [_logoImageView.heightAnchor constraintEqualToConstant:84].active = YES;

    NSTextField *appName = [NSTextField labelWithString:@"TeXMini"];
    appName.font = [NSFont systemFontOfSize:28 weight:NSFontWeightBold];
    appName.textColor = [NSColor labelColor];

    NSTextField *appTagline = [NSTextField labelWithString:@"轻量 · 极速 · LaTeX 编辑器"];
    appTagline.font = [NSFont systemFontOfSize:14];
    appTagline.textColor = [NSColor secondaryLabelColor];

    NSStackView *headerStack = [NSStackView stackViewWithViews:@[_logoImageView, appName, appTagline]];
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.alignment = NSLayoutAttributeCenterX;
    headerStack.spacing = 8;
    [headerStack setCustomSpacing:14 afterView:_logoImageView];

    // ── 三张新建卡片 ─────────────────────────────────────────
    __weak typeof(self) weakSelf = self;
    NSView *cardBlank = [self cardWithSymbol:@"plus" accent:YES title:@"新建空白文档" subtitle:@"纯净起步，快速书写"
                                    shortcut:@"⌘N" onClick:^{ [weakSelf selectTemplate:2]; }];
    NSView *cardTemplate = [self cardWithSymbol:@"square.grid.2x2" accent:NO title:@"从模板开始" subtitle:@"学术论文 · 中文报告 · 更多预设"
                                       shortcut:nil onClick:^{ [weakSelf.delegate welcomeViewDidRequestTemplatePicker:weakSelf]; }];
    NSStackView *cardRow = [NSStackView stackViewWithViews:@[cardBlank, cardTemplate]];
    cardRow.distribution = NSStackViewDistributionFillEqually;
    cardRow.spacing = 16;

    // ── 最近工程标题行 + 过滤 ────────────────────────────────
    NSTextField *recentTitle = [NSTextField labelWithString:@"最近工程"];
    recentTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    recentTitle.textColor = [NSColor secondaryLabelColor];
    _recentCountLabel = [NSTextField labelWithString:@""];
    _recentCountLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _recentCountLabel.textColor = [NSColor tertiaryLabelColor];

    NSView *searchPill = [self searchPill];

    NSView *titleSpacer = [[NSView alloc] init];
    [titleSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *recentHeader = [NSStackView stackViewWithViews:@[recentTitle, _recentCountLabel, titleSpacer, searchPill]];
    recentHeader.spacing = 8;
    recentHeader.alignment = NSLayoutAttributeCenterY;

    _recentStack = [[NSStackView alloc] init];
    _recentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _recentStack.alignment = NSLayoutAttributeLeading;
    _recentStack.spacing = kTMWelcomeRowSpacing;
    _recentStack.translatesAutoresizingMaskIntoConstraints = NO;

    // 可滚动但不显示滚动条：触控板 / 滚轮照常滚动
    _recentScroll = [[NSScrollView alloc] init];
    _recentScroll.hasVerticalScroller = NO;
    _recentScroll.hasHorizontalScroller = NO;
    _recentScroll.drawsBackground = NO;
    _recentScroll.borderType = NSNoBorder;
    _recentScroll.verticalScrollElasticity = NSScrollElasticityAllowed;
    _recentScroll.horizontalScrollElasticity = NSScrollElasticityNone;
    NSClipView *clip = [[TMFlippedClipView alloc] init];
    clip.drawsBackground = NO;
    _recentScroll.contentView = clip;
    _recentScroll.documentView = _recentStack;
    [NSLayoutConstraint activateConstraints:@[
        [_recentStack.topAnchor constraintEqualToAnchor:clip.topAnchor],
        [_recentStack.leadingAnchor constraintEqualToAnchor:clip.leadingAnchor],
        [_recentStack.widthAnchor constraintEqualToAnchor:clip.widthAnchor],
    ]];
    _recentScrollHeight = [_recentScroll.heightAnchor constraintEqualToConstant:kTMWelcomeRowHeight];
    _recentScrollHeight.active = YES;

    // ── 打开按钮 + 引擎状态 ──────────────────────────────────
    NSView *btnOpenFile   = [self plainButtonWithSymbol:@"doc" title:@"打开文件…"   onClick:^{ [weakSelf.delegate welcomeViewDidRequestOpenFile:weakSelf]; }];
    NSView *btnOpenFolder = [self plainButtonWithSymbol:@"folder" title:@"打开文件夹…" onClick:^{ [weakSelf.delegate welcomeViewDidRequestOpenFolder:weakSelf]; }];
    NSView *openSpacer = [[NSView alloc] init];
    [openSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *openRow = [NSStackView stackViewWithViews:@[btnOpenFile, btnOpenFolder, openSpacer, [self engineStatusPill]]];
    openRow.spacing = 16;
    openRow.alignment = NSLayoutAttributeCenterY;

    // ── 拖拽提示 ──────────────────────────────────────────────
    NSTextField *dropText = [NSTextField labelWithString:@""];
    NSMutableAttributedString *dropString = [[NSMutableAttributedString alloc] initWithString:@"可直接将 " attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}];
    [dropString appendAttributedString:[[NSAttributedString alloc] initWithString:@".tex" attributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium], NSForegroundColorAttributeName: [NSColor labelColor]}]];
    [dropString appendAttributedString:[[NSAttributedString alloc] initWithString:@" 文件或工程文件夹拖拽至窗口任意位置打开" attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}]];
    dropText.attributedStringValue = dropString;
    NSStackView *dropHint = [NSStackView stackViewWithViews:@[TMSymbolView(@"square.and.arrow.up", 12, [NSColor tertiaryLabelColor]), dropText]];
    dropHint.spacing = 8;
    dropHint.alignment = NSLayoutAttributeCenterY;

    // ── 底部：启动选项 + Esc 提示 ─────────────────────────────
    _restoreCheck = [NSButton checkboxWithTitle:@"启动时自动打开上次的项目" target:self action:@selector(restoreToggled:)];
    _restoreCheck.font = [NSFont systemFontOfSize:12];

    NSTextField *escPre = [NSTextField labelWithString:@"按"];
    NSTextField *escPost = [NSTextField labelWithString:@"返回编辑"];
    for (NSTextField *f in @[escPre, escPost]) {
        f.font = [NSFont systemFontOfSize:12];
        f.textColor = [NSColor tertiaryLabelColor];
    }
    _escHint = [NSStackView stackViewWithViews:@[escPre, TMKeyCapLabel(@"Esc"), escPost]];
    _escHint.spacing = 6;
    _escHint.alignment = NSLayoutAttributeCenterY;

    NSView *footerSpacer = [[NSView alloc] init];
    [footerSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer = [NSStackView stackViewWithViews:@[_restoreCheck, footerSpacer, _escHint]];
    footer.alignment = NSLayoutAttributeCenterY;

    // ── 总布局 ────────────────────────────────────────────────
    NSStackView *content = [NSStackView stackViewWithViews:@[headerStack, cardRow, recentHeader, _recentScroll, openRow, dropHint, footer]];
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.alignment = NSLayoutAttributeCenterX;
    content.spacing = 16;
    [content setCustomSpacing:32 afterView:headerStack];
    [content setCustomSpacing:14 afterView:cardRow];
    [content setCustomSpacing:8 afterView:recentHeader];
    [content setCustomSpacing:24 afterView:_recentScroll];
    [content setCustomSpacing:28 afterView:openRow];
    [content setCustomSpacing:36 afterView:dropHint];

    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
        [content.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [content.widthAnchor constraintEqualToConstant:kTMWelcomeContentWidth],
    ]];
    NSLayoutConstraint *topLimit = [content.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:24];
    [constraints addObject:topLimit];
    for (NSView *v in @[cardRow, recentHeader, _recentScroll, openRow, footer]) {
        [constraints addObject:[v.widthAnchor constraintEqualToAnchor:content.widthAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];

    // 拖入文件时的整窗高亮框
    _dropHighlight = [[NSView alloc] init];
    _dropHighlight.wantsLayer = YES;
    _dropHighlight.layer.cornerRadius = 14;
    _dropHighlight.layer.borderWidth = 2;
    _dropHighlight.hidden = YES;
    _dropHighlight.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_dropHighlight];
    [NSLayoutConstraint activateConstraints:@[
        [_dropHighlight.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [_dropHighlight.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10],
        [_dropHighlight.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [_dropHighlight.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
    ]];
    // 数据由 reload 填充：首页每次显示前都会调用，这里不提前做（直接恢复项目时首页根本不显示）
}

#pragma mark - 辅助构建方法

- (NSView *)cardWithSymbol:(NSString *)symbol accent:(BOOL)accent title:(NSString *)title subtitle:(NSString *)subtitle
                  shortcut:(nullable NSString *)shortcut onClick:(void (^)(void))onClick {
    TMHoverControl *card = [[TMHoverControl alloc] init];
    card.cardStyle = YES;
    card.onClick = onClick;

    // 图标方块
    NSColor *tint = accent ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    NSImageView *icon = TMSymbolView(symbol, 13, tint);
    NSView *badge = [[NSView alloc] init];
    badge.wantsLayer = YES;
    badge.layer.cornerRadius = 7;
    badge.layer.backgroundColor = (accent ? [[NSColor controlAccentColor] colorWithAlphaComponent:0.12]
                                          : [[NSColor labelColor] colorWithAlphaComponent:0.06]).CGColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [badge addSubview:icon];
    [NSLayoutConstraint activateConstraints:@[
        [badge.widthAnchor constraintEqualToConstant:32],
        [badge.heightAnchor constraintEqualToConstant:32],
        [icon.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [icon.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],
    ]];

    NSView *topSpacer = [[NSView alloc] init];
    [topSpacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSMutableArray<NSView *> *topViews = [NSMutableArray arrayWithObjects:badge, topSpacer, nil];
    if (shortcut.length) [topViews addObject:TMKeyCapLabel(shortcut)];
    NSStackView *topRow = [NSStackView stackViewWithViews:topViews];
    topRow.alignment = NSLayoutAttributeCenterY;

    NSTextField *t = [NSTextField labelWithString:title];
    t.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    t.textColor = [NSColor labelColor];
    NSTextField *s = [NSTextField labelWithString:subtitle];
    s.font = [NSFont systemFontOfSize:12];
    s.textColor = [NSColor secondaryLabelColor];
    s.lineBreakMode = NSLineBreakByTruncatingTail;

    NSStackView *inner = [NSStackView stackViewWithViews:@[topRow, t, s]];
    inner.orientation = NSUserInterfaceLayoutOrientationVertical;
    inner.alignment = NSLayoutAttributeLeading;
    inner.spacing = 4;
    [inner setCustomSpacing:14 afterView:topRow];
    inner.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [card fillWithContent:inner];
    [topRow.widthAnchor constraintEqualToAnchor:inner.widthAnchor constant:-32].active = YES;
    return card;
}

/// 搜索框：放大镜 + 无边框输入框的圆角胶囊（NSSearchField 去掉边框后图标会压住占位文字和光标）。
- (NSView *)searchPill {
    NSImageView *glass = TMSymbolView(@"magnifyingglass", 11, [NSColor tertiaryLabelColor]);
    [glass setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    _filterField = [[NSTextField alloc] init];
    _filterField.placeholderString = @"搜索";
    _filterField.font = [NSFont systemFontOfSize:12];
    _filterField.bezeled = NO;
    _filterField.bordered = NO;
    _filterField.drawsBackground = NO;
    _filterField.focusRingType = NSFocusRingTypeNone;
    _filterField.usesSingleLineMode = YES;
    _filterField.cell.scrollable = YES;
    _filterField.delegate = self;

    NSTextField *shortcut = TMKeyCapLabel(@"⌘K");

    NSStackView *pill = [NSStackView stackViewWithViews:@[glass, _filterField, shortcut]];
    pill.spacing = 6;
    pill.alignment = NSLayoutAttributeCenterY;
    pill.edgeInsets = NSEdgeInsetsMake(0, 10, 0, 5);
    pill.wantsLayer = YES;
    pill.layer.cornerRadius = 7;
    pill.layer.backgroundColor = [[NSColor labelColor] colorWithAlphaComponent:0.05].CGColor;
    [pill.widthAnchor constraintEqualToConstant:190].active = YES;
    [pill.heightAnchor constraintEqualToConstant:28].active = YES;
    return pill;
}

- (NSView *)plainButtonWithSymbol:(NSString *)symbol title:(NSString *)title onClick:(void (^)(void))onClick {
    TMHoverControl *btn = [[TMHoverControl alloc] init];
    btn.onClick = onClick;
    NSTextField *t = [NSTextField labelWithString:title];
    t.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    t.textColor = [NSColor labelColor];
    NSStackView *inner = [NSStackView stackViewWithViews:@[TMSymbolView(symbol, 13, [NSColor secondaryLabelColor]), t]];
    inner.spacing = 8;
    inner.alignment = NSLayoutAttributeCenterY;
    inner.edgeInsets = NSEdgeInsetsMake(6, 10, 6, 10);
    [btn fillWithContent:inner];
    return btn;
}

- (NSView *)engineStatusPill {
    _engineDot = [[NSView alloc] init];
    _engineDot.wantsLayer = YES;
    _engineDot.layer.cornerRadius = 3.5;
    [_engineDot.widthAnchor constraintEqualToConstant:7].active = YES;
    [_engineDot.heightAnchor constraintEqualToConstant:7].active = YES;

    _engineStatusLabel = [NSTextField labelWithString:@"正在检测 TeX…"];
    _engineStatusLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    _engineStatusLabel.textColor = [NSColor secondaryLabelColor];

    NSStackView *pill = [NSStackView stackViewWithViews:@[_engineDot, _engineStatusLabel]];
    pill.spacing = 8;
    pill.alignment = NSLayoutAttributeCenterY;
    pill.edgeInsets = NSEdgeInsetsMake(6, 12, 6, 12);
    pill.wantsLayer = YES;
    pill.layer.cornerRadius = 14;
    pill.layer.backgroundColor = [[NSColor labelColor] colorWithAlphaComponent:0.04].CGColor;
    return pill;
}

- (NSView *)recentRowForURL:(NSURL *)url {
    NSNumber *isDirNum = nil;
    [url getResourceValue:&isDirNum forKey:NSURLIsDirectoryKey error:nil];
    BOOL isDirectory = isDirNum.boolValue;

    NSImageView *icon = TMSymbolView(isDirectory ? @"folder" : @"doc.text", 15,
                                     isDirectory ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor]);
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;

    NSTextField *nameField = [NSTextField labelWithString:url.lastPathComponent];
    nameField.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    nameField.textColor = [NSColor labelColor];
    nameField.lineBreakMode = NSLineBreakByTruncatingTail;
    [nameField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSString *parent = url.URLByDeletingLastPathComponent.path.stringByAbbreviatingWithTildeInPath;
    NSTextField *pathField = [NSTextField labelWithString:parent];
    pathField.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    pathField.textColor = [NSColor tertiaryLabelColor];
    pathField.lineBreakMode = NSLineBreakByTruncatingHead;
    [pathField setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [pathField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSDate *modDate = nil;
    [url getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil];
    NSTextField *dateField = [NSTextField labelWithString:TMRelativeDateString(modDate)];
    dateField.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    dateField.textColor = [NSColor secondaryLabelColor];
    dateField.alignment = NSTextAlignmentRight;
    [dateField setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSStackView *inner = [NSStackView stackViewWithViews:@[icon, nameField, pathField, dateField]];
    inner.spacing = 10;
    inner.alignment = NSLayoutAttributeCenterY;
    inner.edgeInsets = NSEdgeInsetsMake(0, 4, 0, 8);

    TMHoverControl *row = [[TMHoverControl alloc] init];
    __weak typeof(self) weakSelf = self;
    row.onClick = ^{ [weakSelf.delegate welcomeView:weakSelf didSelectRecentURL:url]; };
    row.toolTip = url.path;
    [row fillWithContent:inner];
    [row.heightAnchor constraintEqualToConstant:kTMWelcomeRowHeight].active = YES;
    return row;
}

#pragma mark - 数据刷新

- (void)reload {
    _restoreCheck.state = [TMPreferences shared].restoreLastSession ? NSControlStateValueOn : NSControlStateValueOff;
    _escHint.hidden = !self.showsDismissButton;

    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray<NSURL *> *list in @[[TMRecentFiles recentFolderURLs], [TMRecentFiles recentFileURLs]]) {
        for (NSURL *url in list) {
            if (urls.count >= kTMWelcomeRecentLimit) break;
            if (![fm fileExistsAtPath:url.path]) continue;
            if ([urls containsObject:url]) continue;
            [urls addObject:url];
        }
    }
    self.recentURLs = urls;
    _recentCountLabel.stringValue = urls.count ? [NSString stringWithFormat:@"%lu", (unsigned long)urls.count] : @"";
    [self rebuildRecentRows];
    [self refreshEngineStatus];
}

- (void)rebuildRecentRows {
    for (NSView *v in _recentStack.arrangedSubviews) [v removeFromSuperview];

    NSString *query = self.filterField.stringValue;
    NSMutableArray<NSURL *> *shown = [NSMutableArray array];
    for (NSURL *url in self.recentURLs) {
        if (query.length == 0 || [url.path rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [shown addObject:url];
        }
    }

    if (shown.count == 0) {
        NSTextField *empty = [NSTextField labelWithString:self.recentURLs.count ? @"没有匹配的项目" : @"没有最近打开的项目"];
        empty.font = [NSFont systemFontOfSize:12];
        empty.textColor = [NSColor tertiaryLabelColor];
        [_recentStack addArrangedSubview:empty];
        [self fitRecentScrollToRowCount:1];
        return;
    }
    for (NSURL *url in shown) {
        NSView *row = [self recentRowForURL:url];
        [_recentStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_recentStack.widthAnchor].active = YES;
    }
    [self fitRecentScrollToRowCount:shown.count];
}

/// 列表区高度：最多露出 kTMWelcomeVisibleRows 行，其余滚动；每次重建后回到顶部。
- (void)fitRecentScrollToRowCount:(NSUInteger)count {
    NSUInteger rows = MAX((NSUInteger)1, MIN(count, kTMWelcomeVisibleRows));
    self.recentScrollHeight.constant = rows * kTMWelcomeRowHeight + (rows - 1) * kTMWelcomeRowSpacing;
    [self.recentScroll.contentView scrollToPoint:NSZeroPoint];
    [self.recentScroll reflectScrolledClipView:self.recentScroll.contentView];
}

/// 在后台查找默认引擎的可执行文件，显示“引擎 · TeX Live 年份 就绪”。
- (void)refreshEngineStatus {
    TMTeXEngine engine = (TMTeXEngine)[TMPreferences shared].defaultEngine;
    NSString *engineName = @{ @(TMTeXEngineXeLaTeX): @"XeLaTeX",
                              @(TMTeXEnginePDFLaTeX): @"pdfLaTeX",
                              @(TMTeXEngineLuaLaTeX): @"LuaLaTeX" }[@(engine)] ?: @"latexmk";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *path = [TMCompiler findExecutablePathForEngine:engine];
        NSString *resolved = path.stringByResolvingSymlinksInPath;
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/(20\\d\\d)/" options:0 error:nil];
        NSTextCheckingResult *m = resolved ? [re firstMatchInString:resolved options:0 range:NSMakeRange(0, resolved.length)] : nil;
        NSString *year = m ? [resolved substringWithRange:[m rangeAtIndex:1]] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (path) {
                self.engineStatusLabel.stringValue = year ? [NSString stringWithFormat:@"%@ · %@ 就绪", engineName, year]
                                                          : [NSString stringWithFormat:@"%@ 就绪", engineName];
                self.engineDot.layer.backgroundColor = [NSColor systemGreenColor].CGColor;
            } else {
                self.engineStatusLabel.stringValue = @"未找到 TeX 环境";
                self.engineDot.layer.backgroundColor = [NSColor systemOrangeColor].CGColor;
            }
        });
    });
}

#pragma mark - 过滤

- (void)controlTextDidChange:(NSNotification *)obj {
    if (obj.object == self.filterField) [self rebuildRecentRows];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (control != self.filterField) return NO;
    if (commandSelector == @selector(cancelOperation:)) {
        [self cancelOperation:nil];
        return YES;
    }
    if (commandSelector == @selector(insertNewline:)) {
        // 回车打开第一个匹配项
        for (NSURL *url in self.recentURLs) {
            NSString *q = self.filterField.stringValue;
            if (q.length == 0 || [url.path rangeOfString:q options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [self.delegate welcomeView:self didSelectRecentURL:url];
                break;
            }
        }
        return YES;
    }
    return NO;
}

#pragma mark - 拖拽打开

- (nullable NSURL *)droppableURLFromDraggingInfo:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if (isDir.boolValue || [url.pathExtension.lowercaseString isEqualToString:@"tex"]) return url;
    }
    return nil;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (![self droppableURLFromDraggingInfo:sender]) return NSDragOperationNone;
    _dropHighlight.layer.borderColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.6].CGColor;
    _dropHighlight.layer.backgroundColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.04].CGColor;
    _dropHighlight.hidden = NO;
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender { _dropHighlight.hidden = YES; }
- (void)draggingEnded:(id<NSDraggingInfo>)sender  { _dropHighlight.hidden = YES; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    _dropHighlight.hidden = YES;
    NSURL *url = [self droppableURLFromDraggingInfo:sender];
    if (!url) return NO;
    [self.delegate welcomeView:self didSelectRecentURL:url];
    return YES;
}

#pragma mark - 用户交互

- (void)selectTemplate:(NSInteger)index {
    if ([self.delegate respondsToSelector:@selector(welcomeView:didSelectTemplateAtIndex:)])
        [self.delegate welcomeView:self didSelectTemplateAtIndex:index];
    else
        [self.delegate welcomeViewDidRequestNewDocument:self];
}

- (void)restoreToggled:(NSButton *)sender {
    [TMPreferences shared].restoreLastSession = sender.state == NSControlStateValueOn;
}

@end
