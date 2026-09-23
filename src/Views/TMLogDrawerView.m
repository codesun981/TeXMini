#import "TMLogDrawerView.h"

static const CGFloat kTMDrawerHeight = 170.0;
static const CGFloat kTMDrawerHeaderHeight = 26.0;

@interface TMLogDrawerView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation TMLogDrawerView {
    NSTextView *_textView;
    NSScrollView *_scrollView;
    NSScrollView *_tableScrollView;
    NSTableView *_tableView;
    NSSegmentedControl *_modeControl;
    NSTextField *_summaryLabel;
    NSLayoutConstraint *_heightConstraint;
    NSArray<TMLogIssue *> *_issues;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _isExpanded = NO;
        _issues = @[];
        self.wantsLayer = YES;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 顶部 1px 分割线 + 一行页签
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:separator];

    _modeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"问题", @"原始日志"]
                                                     trackingMode:NSSegmentSwitchTrackingSelectOne
                                                           target:self
                                                           action:@selector(modeChanged:)];
    _modeControl.segmentStyle = NSSegmentStyleRounded;
    _modeControl.controlSize = NSControlSizeSmall;
    _modeControl.font = [NSFont systemFontOfSize:11];
    _modeControl.selectedSegment = 1;
    _modeControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_modeControl];

    _summaryLabel = [NSTextField labelWithString:@""];
    _summaryLabel.font = [NSFont systemFontOfSize:11];
    _summaryLabel.textColor = [NSColor secondaryLabelColor];
    _summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_summaryLabel];

    // 原始日志
    _scrollView = [[NSScrollView alloc] init];
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    // 必须给 NSTextView 一个非零 frame 并让它随 scroll view 宽度伸缩、纵向自增，
    // 否则文本虽然写进了 textStorage，但绘制区域是 0×0，抽屉看起来永远空白。
    NSSize contentSize = NSMakeSize(600, 150);
    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.richText = NO;
    _textView.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    _textView.textColor = [NSColor labelColor];
    _textView.backgroundColor = [NSColor textBackgroundColor];
    _textView.textContainerInset = NSMakeSize(8, 6);
    _textView.minSize = NSMakeSize(0, contentSize.height);
    _textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _textView.verticallyResizable = YES;
    _textView.horizontallyResizable = NO;
    _textView.autoresizingMask = NSViewWidthSizable;
    _textView.textContainer.containerSize = NSMakeSize(contentSize.width, FLT_MAX);
    _textView.textContainer.widthTracksTextView = YES;
    _scrollView.documentView = _textView;
    [self addSubview:_scrollView];

    // 问题列表
    _tableScrollView = [[NSScrollView alloc] init];
    _tableScrollView.hasVerticalScroller = YES;
    _tableScrollView.hasHorizontalScroller = NO;
    _tableScrollView.borderType = NSNoBorder;
    _tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableScrollView.hidden = YES;

    _tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 600, 150)];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.headerView = nil;
    _tableView.rowHeight = 22.0;
    _tableView.usesAlternatingRowBackgroundColors = YES;
    _tableView.allowsMultipleSelection = NO;
    _tableView.target = self;
    _tableView.action = @selector(rowClicked:);
    _tableView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;

    NSTableColumn *kindCol = [[NSTableColumn alloc] initWithIdentifier:@"kind"];
    kindCol.width = 56;
    kindCol.minWidth = 56;
    kindCol.maxWidth = 56;
    [_tableView addTableColumn:kindCol];
    NSTableColumn *lineCol = [[NSTableColumn alloc] initWithIdentifier:@"line"];
    lineCol.width = 64;
    lineCol.minWidth = 64;
    lineCol.maxWidth = 64;
    [_tableView addTableColumn:lineCol];
    NSTableColumn *msgCol = [[NSTableColumn alloc] initWithIdentifier:@"message"];
    msgCol.width = 400;
    [_tableView addTableColumn:msgCol];
    _tableScrollView.documentView = _tableView;
    [self addSubview:_tableScrollView];

    _heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    _heightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:self.topAnchor],
        [separator.heightAnchor constraintEqualToConstant:1],

        [_modeControl.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_modeControl.centerYAnchor constraintEqualToAnchor:self.topAnchor constant:1 + kTMDrawerHeaderHeight / 2.0],

        [_summaryLabel.leadingAnchor constraintEqualToAnchor:_modeControl.trailingAnchor constant:12],
        [_summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
        [_summaryLabel.centerYAnchor constraintEqualToAnchor:_modeControl.centerYAnchor],

        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor constant:1 + kTMDrawerHeaderHeight],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_tableScrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_tableScrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_tableScrollView.topAnchor constraintEqualToAnchor:self.topAnchor constant:1 + kTMDrawerHeaderHeight],
        [_tableScrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

#pragma mark - 模式

- (void)modeChanged:(id)sender {
    [self applyMode];
}

- (void)applyMode {
    BOOL showIssues = (_modeControl.selectedSegment == 0);
    _tableScrollView.hidden = !showIssues;
    _scrollView.hidden = showIssues;
}

- (void)showIssuesPage:(BOOL)issues {
    _modeControl.selectedSegment = issues ? 0 : 1;
    [self applyMode];
}

#pragma mark - 原始日志

- (void)appendLogText:(NSString *)text {
    NSFont *font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];

    // 逐行着色：错误红、警告橙、坏盒子黄，其余默认色。
    // 注意流式输出的 chunk 可能在行中间截断，只按前缀判断，误差可接受。
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL *stop) {
        NSColor *color = [NSColor labelColor];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([trimmed hasPrefix:@"! "] || [trimmed rangeOfString:@".tex:[0-9]+:" options:NSRegularExpressionSearch].location != NSNotFound) {
            color = [NSColor systemRedColor];
        } else if ([trimmed containsString:@"Warning:"]) {
            color = [NSColor systemOrangeColor];
        } else if ([trimmed hasPrefix:@"Overfull"] || [trimmed hasPrefix:@"Underfull"]) {
            color = [NSColor systemYellowColor];
        }
        NSString *piece = idx < lines.count - 1 ? [line stringByAppendingString:@"\n"] : line;
        [attr appendAttributedString:[[NSAttributedString alloc] initWithString:piece attributes:@{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color
        }]];
    }];

    [_textView.textStorage appendAttributedString:attr];
    [_textView scrollRangeToVisible:NSMakeRange(_textView.textStorage.length, 0)];
}

- (void)clearLog {
    _textView.string = @"";
    _issues = @[];
    [_tableView reloadData];
    _summaryLabel.stringValue = @"正在编译…";
    [self showIssuesPage:NO];
}

#pragma mark - 问题列表

- (void)setIssues:(NSArray<TMLogIssue *> *)issues {
    // 错误排在最前，其余保持日志顺序
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *others = [NSMutableArray array];
    for (TMLogIssue *issue in issues) {
        [(issue.kind == TMLogIssueError ? errors : others) addObject:issue];
    }
    _issues = [errors arrayByAddingObjectsFromArray:others];
    [_tableView reloadData];

    NSUInteger e = [TMLogParser countOfKind:TMLogIssueError inIssues:issues];
    NSUInteger w = [TMLogParser countOfKind:TMLogIssueWarning inIssues:issues];
    NSUInteger b = [TMLogParser countOfKind:TMLogIssueBadBox inIssues:issues];
    if (issues.count == 0) {
        _summaryLabel.stringValue = @"没有错误或警告";
    } else {
        NSMutableArray *parts = [NSMutableArray array];
        if (e) [parts addObject:[NSString stringWithFormat:@"%lu 错误", (unsigned long)e]];
        if (w) [parts addObject:[NSString stringWithFormat:@"%lu 警告", (unsigned long)w]];
        if (b) [parts addObject:[NSString stringWithFormat:@"%lu 坏盒子", (unsigned long)b]];
        _summaryLabel.stringValue = [[parts componentsJoinedByString:@" · "] stringByAppendingString:@"，点击一条跳到对应行"];
    }
    [self showIssuesPage:issues.count > 0];
}

- (void)rowClicked:(id)sender {
    NSInteger row = _tableView.clickedRow;
    if (row < 0 || row >= (NSInteger)_issues.count) return;
    if ([self.delegate respondsToSelector:@selector(logDrawerView:didSelectIssue:)]) {
        [self.delegate logDrawerView:self didSelectIssue:_issues[row]];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_issues.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, 22)];
        cell.identifier = identifier;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.font = [NSFont systemFontOfSize:11.5];
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        cell.textField = label;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:4],
            [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }

    TMLogIssue *issue = _issues[row];
    if ([identifier isEqualToString:@"kind"]) {
        cell.textField.stringValue = issue.kindLabel;
        cell.textField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
        switch (issue.kind) {
            case TMLogIssueError: cell.textField.textColor = [NSColor systemRedColor]; break;
            case TMLogIssueWarning: cell.textField.textColor = [NSColor systemOrangeColor]; break;
            case TMLogIssueBadBox: cell.textField.textColor = [NSColor systemYellowColor]; break;
        }
    } else if ([identifier isEqualToString:@"line"]) {
        cell.textField.stringValue = issue.line > 0 ? [NSString stringWithFormat:@"第 %ld 行", (long)issue.line] : @"—";
        cell.textField.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        cell.textField.textColor = [NSColor secondaryLabelColor];
    } else {
        NSString *file = issue.filePath.lastPathComponent;
        cell.textField.stringValue = file.length ? [NSString stringWithFormat:@"%@  ·  %@", file, issue.message] : issue.message;
        cell.textField.font = [NSFont systemFontOfSize:11.5];
        cell.textField.textColor = [NSColor labelColor];
        cell.textField.toolTip = issue.message;
    }
    return cell;
}

#pragma mark - 展开 / 收起

- (void)toggleAnimated {
    self.isExpanded = !self.isExpanded;
    CGFloat targetHeight = self.isExpanded ? kTMDrawerHeight : 0.0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.25;
        context.allowsImplicitAnimation = YES;
        self->_heightConstraint.constant = targetHeight;
        [self.superview layoutSubtreeIfNeeded];
    }];
}

@end
