#import "TMWelcomeView.h"
#import "TMRecentFiles.h"
#import "TMPreferences.h"

static const NSUInteger kTMWelcomeRecentLimit = 6;

@interface TMWelcomeView ()
@property (nonatomic, strong) NSStackView *recentStack;
@property (nonatomic, strong) NSButton *restoreCheck;
@property (nonatomic, strong) NSButton *dismissButton;
@property (nonatomic, copy) NSArray<NSURL *> *recentURLs;
@end

@implementation TMWelcomeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) [self buildUI];
    return self;
}

// 不透明底色，盖住下面的编辑器与 PDF；在 updateLayer 里取色以跟随深色模式
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { self.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor; }
- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)cancelOperation:(id)sender {
    if (self.showsDismissButton) [self.delegate welcomeViewDidRequestDismiss:self];
}

// 吞掉点击，别让它穿到下面的编辑器
- (void)mouseDown:(NSEvent *)event {}

#pragma mark - 构建界面

- (NSTextField *)sectionTitle:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    l.textColor = [NSColor secondaryLabelColor];
    return l;
}

/// 列表式按钮：悬停时才显示底色，图标在左，文字左对齐。
- (NSButton *)rowButtonWithTitle:(NSAttributedString *)title image:(NSImage *)image action:(SEL)action {
    NSButton *b = [[NSButton alloc] initWithFrame:NSZeroRect];
    b.bezelStyle = NSBezelStyleAccessoryBarAction;
    b.showsBorderOnlyWhileMouseInside = YES;
    b.attributedTitle = title;
    b.image = image;
    b.imagePosition = NSImageLeading;
    b.imageHugsTitle = YES;
    b.alignment = NSTextAlignmentLeft;
    b.target = self;
    b.action = action;
    [b setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return b;
}

- (NSButton *)actionButton:(NSString *)title symbol:(NSString *)symbol shortcut:(NSString *)shortcut action:(SEL)action {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:title attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:14], NSForegroundColorAttributeName: [NSColor controlAccentColor]}];
    if (shortcut.length) {
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:shortcut] attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:12], NSForegroundColorAttributeName: [NSColor tertiaryLabelColor]}]];
    }
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular];
    NSImage *img = [[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil] imageWithSymbolConfiguration:cfg];
    NSButton *b = [self rowButtonWithTitle:s image:img action:action];
    b.contentTintColor = [NSColor controlAccentColor];
    return b;
}

- (NSStackView *)column:(NSArray<NSView *> *)views {
    NSStackView *s = [NSStackView stackViewWithViews:views];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = 4;
    return s;
}

- (void)buildUI {
    self.wantsLayer = YES;

    NSImageView *icon = [NSImageView imageViewWithImage:NSApp.applicationIconImage ?: [NSImage imageNamed:NSImageNameApplicationIcon]];
    [icon.widthAnchor constraintEqualToConstant:56].active = YES;
    [icon.heightAnchor constraintEqualToConstant:56].active = YES;
    NSTextField *title = [NSTextField labelWithString:@"TeXMini"];
    title.font = [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    NSTextField *subtitle = [NSTextField labelWithString:@"轻量、极速、易用的 LaTeX 编辑器"];
    subtitle.textColor = [NSColor secondaryLabelColor];
    NSStackView *titles = [self column:@[title, subtitle]];
    titles.spacing = 2;
    NSStackView *header = [NSStackView stackViewWithViews:@[icon, titles]];
    header.spacing = 14;

    NSStackView *start = [self column:@[
        [self sectionTitle:@"开始"],
        [self actionButton:@"新建文档…" symbol:@"doc.badge.plus" shortcut:@"" action:@selector(newDocument:)],
        [self actionButton:@"打开文件…" symbol:@"doc" shortcut:@"⌘O" action:@selector(openFile:)],
        [self actionButton:@"打开文件夹…" symbol:@"folder" shortcut:@"⇧⌘O" action:@selector(openFolder:)],
    ]];
    [start setCustomSpacing:8 afterView:start.arrangedSubviews.firstObject];

    _recentStack = [self column:@[]];
    NSStackView *recent = [self column:@[[self sectionTitle:@"最近"], _recentStack]];
    recent.spacing = 8;

    NSStackView *columns = [NSStackView stackViewWithViews:@[start, recent]];
    columns.alignment = NSLayoutAttributeTop;
    columns.spacing = 48;
    [start.widthAnchor constraintEqualToConstant:200].active = YES;
    [recent.widthAnchor constraintEqualToConstant:380].active = YES;

    _restoreCheck = [NSButton checkboxWithTitle:@"启动时打开上次的项目" target:self action:@selector(restoreToggled:)];
    _restoreCheck.controlSize = NSControlSizeSmall;
    _restoreCheck.font = [NSFont systemFontOfSize:12];
    _dismissButton = [NSButton buttonWithTitle:@"返回编辑" target:self action:@selector(dismiss:)];
    _dismissButton.toolTip = @"Esc";
    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *footer = [NSStackView stackViewWithViews:@[_restoreCheck, spacer, _dismissButton]];

    NSStackView *content = [self column:@[header, columns, footer]];
    content.spacing = 32;
    [content setCustomSpacing:24 afterView:columns];
    [footer.widthAnchor constraintEqualToAnchor:columns.widthAnchor].active = YES;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        // 视觉中心略偏上
        [content.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-30],
        [content.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:24],
        [content.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:24],
    ]];
    [self reload];
}

#pragma mark - 数据

- (void)reload {
    self.restoreCheck.state = [TMPreferences shared].restoreLastSession ? NSControlStateValueOn : NSControlStateValueOff;
    self.dismissButton.hidden = !self.showsDismissButton;

    for (NSView *v in self.recentStack.arrangedSubviews) [v removeFromSuperview];
    // 文件夹在前（“项目”），再是文件；不存在的项不列出
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray<NSURL *> *list in @[[TMRecentFiles recentFolderURLs], [TMRecentFiles recentFileURLs]]) {
        NSUInteger n = 0;
        for (NSURL *url in list) {
            if (n >= kTMWelcomeRecentLimit) break;
            if (![fm fileExistsAtPath:url.path]) continue;
            [urls addObject:url];
            n++;
        }
    }
    self.recentURLs = urls;

    if (urls.count == 0) {
        NSTextField *empty = [NSTextField labelWithString:@"还没有最近打开的项目"];
        empty.textColor = [NSColor tertiaryLabelColor];
        [self.recentStack addArrangedSubview:empty];
        return;
    }
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, BOOL *stop) {
        NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:url.lastPathComponent attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: [NSColor labelColor], NSParagraphStyleAttributeName: para}];
        NSString *parent = url.URLByDeletingLastPathComponent.path.stringByAbbreviatingWithTildeInPath;
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:parent] attributes:@{
            NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: [NSColor secondaryLabelColor], NSParagraphStyleAttributeName: para}]];
        NSImage *img = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
        img.size = NSMakeSize(16, 16);
        NSButton *b = [self rowButtonWithTitle:s image:img action:@selector(openRecent:)];
        b.tag = (NSInteger)idx;
        b.toolTip = url.path;
        [self.recentStack addArrangedSubview:b];
        [b.widthAnchor constraintLessThanOrEqualToAnchor:self.recentStack.widthAnchor].active = YES;
    }];
}

#pragma mark - 动作

- (void)newDocument:(id)sender { [self.delegate welcomeViewDidRequestNewDocument:self]; }
- (void)openFile:(id)sender { [self.delegate welcomeViewDidRequestOpenFile:self]; }
- (void)openFolder:(id)sender { [self.delegate welcomeViewDidRequestOpenFolder:self]; }
- (void)dismiss:(id)sender { [self.delegate welcomeViewDidRequestDismiss:self]; }

- (void)openRecent:(NSButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.recentURLs.count) return;
    [self.delegate welcomeView:self didSelectRecentURL:self.recentURLs[(NSUInteger)sender.tag]];
}

- (void)restoreToggled:(NSButton *)sender {
    [TMPreferences shared].restoreLastSession = sender.state == NSControlStateValueOn;
}

@end
