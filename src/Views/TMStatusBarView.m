#import "TMStatusBarView.h"

@implementation TMStatusBarView {
    NSTextField *_cursorLabel;
    NSTextField *_statusLabel;
    NSTextField *_pageLabel;
    NSTextField *_targetLabel;
    NSProgressIndicator *_spinner;
    NSButton *_errorButton;
    NSButton *_logButton;
    NSPopUpButton *_enginePopup;
    NSPopUpButton *_stylePopup;
    NSInteger _lastErrorLine;
    NSInteger _cursorLine;
    NSInteger _cursorColumn;
    NSUInteger _wordCount;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        _cursorLine = 1;
        _cursorColumn = 1;
        [self setupUI];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    // 绘制顶部分割线
    [[NSColor separatorColor] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(0, NSMaxY(self.bounds) - 0.5)
                              toPoint:NSMakePoint(NSMaxX(self.bounds), NSMaxY(self.bounds) - 0.5)];
}

- (void)setupUI {
    _cursorLabel = [NSTextField labelWithString:@"行 1, 列 1"];
    _cursorLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _cursorLabel.textColor = [NSColor secondaryLabelColor];
    _cursorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_cursorLabel];

    _stylePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _stylePopup.bezelStyle = NSBezelStyleInline;
    _stylePopup.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _stylePopup.target = self;
    _stylePopup.action = @selector(styleChanged:);
    _stylePopup.hidden = YES;
    _stylePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_stylePopup];

    _spinner = [[NSProgressIndicator alloc] init];
    _spinner.style = NSProgressIndicatorStyleSpinning;
    _spinner.controlSize = NSControlSizeSmall;
    _spinner.displayedWhenStopped = NO;
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_spinner];

    _statusLabel = [NSTextField labelWithString:@"就绪"];
    _statusLabel.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_statusLabel];

    _errorButton = [NSButton buttonWithTitle:@"" target:self action:@selector(errorButtonClicked:)];
    _errorButton.bezelStyle = NSBezelStyleInline;
    _errorButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    _errorButton.contentTintColor = [NSColor systemRedColor];
    _errorButton.hidden = YES;
    _errorButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_errorButton];

    _enginePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _enginePopup.bezelStyle = NSBezelStyleInline;
    _enginePopup.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    [_enginePopup addItemsWithTitles:@[@"自动 (latexmk)", @"xelatex", @"pdflatex", @"lualatex"]];
    _enginePopup.target = self;
    _enginePopup.action = @selector(engineChanged:);
    _enginePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_enginePopup];

    _logButton = [NSButton buttonWithTitle:@"编译日志" target:self action:@selector(logButtonClicked:)];
    _logButton.bezelStyle = NSBezelStyleInline;
    _logButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _logButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_logButton];

    _pageLabel = [NSTextField labelWithString:@""];
    _pageLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _pageLabel.textColor = [NSColor secondaryLabelColor];
    _pageLabel.hidden = YES;
    _pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_pageLabel];

    _targetLabel = [NSTextField labelWithString:@""];
    _targetLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _targetLabel.textColor = [NSColor secondaryLabelColor];
    _targetLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _targetLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_targetLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addSubview:_targetLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_cursorLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_cursorLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_stylePopup.leadingAnchor constraintEqualToAnchor:_cursorLabel.trailingAnchor constant:10],
        [_stylePopup.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_spinner.leadingAnchor constraintEqualToAnchor:_stylePopup.trailingAnchor constant:12],
        [_spinner.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_spinner.widthAnchor constraintEqualToConstant:14],
        [_spinner.heightAnchor constraintEqualToConstant:14],

        [_statusLabel.leadingAnchor constraintEqualToAnchor:_spinner.trailingAnchor constant:6],
        [_statusLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_errorButton.leadingAnchor constraintEqualToAnchor:_statusLabel.trailingAnchor constant:8],
        [_errorButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_logButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [_logButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_enginePopup.trailingAnchor constraintEqualToAnchor:_logButton.leadingAnchor constant:-10],
        [_enginePopup.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_targetLabel.trailingAnchor constraintEqualToAnchor:_enginePopup.leadingAnchor constant:-6],
        [_targetLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_targetLabel.widthAnchor constraintLessThanOrEqualToConstant:280],
        [_targetLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_errorButton.trailingAnchor constant:16],

        [_pageLabel.trailingAnchor constraintEqualToAnchor:_targetLabel.leadingAnchor constant:-14],
        [_pageLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
}

- (void)setCompileTargetFileName:(NSString *)fileName engine:(NSString *)engine toolTip:(nullable NSString *)toolTip {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:fileName attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor labelColor]}];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  ·  " stringByAppendingString:engine] attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}]];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [text addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, text.length)];
    _targetLabel.attributedStringValue = text;
    _targetLabel.toolTip = toolTip;
}

- (void)setPageIndex:(NSInteger)pageIndex pageCount:(NSInteger)pageCount {
    if (pageCount <= 0) {
        _pageLabel.hidden = YES;
        return;
    }
    _pageLabel.hidden = NO;
    _pageLabel.stringValue = [NSString stringWithFormat:@"第 %ld / %ld 页", (long)(pageIndex + 1), (long)pageCount];
}

- (void)setCursorLine:(NSInteger)line column:(NSInteger)column {
    _cursorLine = line;
    _cursorColumn = column;
    [self refreshCursorLabel];
}

- (void)setWordCount:(NSUInteger)words {
    _wordCount = words;
    [self refreshCursorLabel];
}

- (void)refreshCursorLabel {
    _cursorLabel.stringValue = [NSString stringWithFormat:@"行 %ld, 列 %ld  |  %lu 词",
                                (long)_cursorLine, (long)_cursorColumn, (unsigned long)_wordCount];
}

- (void)showCompilingStateWithEngine:(NSString *)engineName {
    [_spinner startAnimation:nil];
    _statusLabel.stringValue = [NSString stringWithFormat:@"正在编译 (%@)...", engineName];
    _statusLabel.textColor = [NSColor systemBlueColor];
    _errorButton.hidden = YES;
}

- (void)showSuccessStateWithDuration:(double)duration warnings:(NSUInteger)warnings badBoxes:(NSUInteger)badBoxes {
    [_spinner stopAnimation:nil];
    NSMutableString *text = [NSMutableString stringWithFormat:@"✓ 编译完成 (%.2fs)", duration];
    if (warnings > 0) [text appendFormat:@" · %lu 警告", (unsigned long)warnings];
    if (badBoxes > 0) [text appendFormat:@" · %lu 坏盒子", (unsigned long)badBoxes];
    _statusLabel.stringValue = text;
    _statusLabel.textColor = warnings > 0 ? [NSColor systemOrangeColor] : [NSColor systemGreenColor];
    _errorButton.hidden = YES;
}

- (void)showErrorStateWithMessage:(NSString *)message line:(NSInteger)line {
    [_spinner stopAnimation:nil];
    _statusLabel.stringValue = @"✗ 编译失败";
    _statusLabel.textColor = [NSColor systemRedColor];

    _lastErrorLine = line;
    if (line > 0) {
        _errorButton.title = [NSString stringWithFormat:@"定位错误: 第 %ld 行", (long)line];
        _errorButton.hidden = NO;
    } else {
        _errorButton.hidden = YES;
    }
}

- (void)showReadyState {
    [_spinner stopAnimation:nil];
    _statusLabel.stringValue = @"就绪";
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _errorButton.hidden = YES;
}

- (void)showInfoMessage:(NSString *)message {
    [_spinner stopAnimation:nil];
    _statusLabel.stringValue = message;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
}

- (void)setSelectedEngine:(TMTeXEngine)engine {
    [_enginePopup selectItemAtIndex:(NSInteger)engine];
}

- (void)setParagraphStyleTitles:(NSArray<NSString *> *)titles {
    [_stylePopup removeAllItems];
    [_stylePopup addItemsWithTitles:titles];
}

- (void)setParagraphStyle:(NSInteger)style {
    // 负数：当前文件没有段落样式（.bib / .txt），收起样式框
    _stylePopup.hidden = style < 0 || style >= _stylePopup.numberOfItems;
    if (!_stylePopup.hidden) [_stylePopup selectItemAtIndex:style];
}

- (void)styleChanged:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidSelectParagraphStyle:)]) {
        [self.delegate statusBarDidSelectParagraphStyle:_stylePopup.indexOfSelectedItem];
    }
}

- (void)engineChanged:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidChangeEngine:)]) {
        [self.delegate statusBarDidChangeEngine:(TMTeXEngine)_enginePopup.indexOfSelectedItem];
    }
}

- (void)errorButtonClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidClickErrorLine:)]) {
        [self.delegate statusBarDidClickErrorLine:_lastErrorLine];
    }
}

- (void)logButtonClicked:(id)sender {
    if ([self.delegate respondsToSelector:@selector(statusBarDidToggleLogDrawer)]) {
        [self.delegate statusBarDidToggleLogDrawer];
    }
}

@end
