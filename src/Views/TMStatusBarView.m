#import "TMStatusBarView.h"

@implementation TMStatusBarView {
    NSTextField *_cursorLabel;
    NSTextField *_statusLabel;
    NSProgressIndicator *_spinner;
    NSButton *_errorButton;
    NSButton *_logButton;
    NSPopUpButton *_enginePopup;
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
    [_enginePopup addItemsWithTitles:@[@"latexmk", @"xelatex", @"pdflatex"]];
    _enginePopup.target = self;
    _enginePopup.action = @selector(engineChanged:);
    _enginePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_enginePopup];

    _logButton = [NSButton buttonWithTitle:@"编译日志" target:self action:@selector(logButtonClicked:)];
    _logButton.bezelStyle = NSBezelStyleInline;
    _logButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _logButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_logButton];

    [NSLayoutConstraint activateConstraints:@[
        [_cursorLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [_cursorLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],

        [_spinner.leadingAnchor constraintEqualToAnchor:_cursorLabel.trailingAnchor constant:16],
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
        [_enginePopup.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
    ]];
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

- (void)showSuccessStateWithDuration:(double)duration {
    [_spinner stopAnimation:nil];
    _statusLabel.stringValue = [NSString stringWithFormat:@"✓ 编译完成 (%.2fs)", duration];
    _statusLabel.textColor = [NSColor systemGreenColor];
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
