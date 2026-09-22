#import "TMLogDrawerView.h"

@implementation TMLogDrawerView {
    NSTextView *_textView;
    NSScrollView *_scrollView;
    NSLayoutConstraint *_heightConstraint;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _isExpanded = NO;
        self.wantsLayer = YES;
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
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

    // 顶部 1px 分割线，让抽屉与编辑区在视觉上分开
    NSBox *separator = [[NSBox alloc] init];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:separator];

    _heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    _heightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [separator.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [separator.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [separator.topAnchor constraintEqualToAnchor:self.topAnchor],
        [separator.heightAnchor constraintEqualToConstant:1],

        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:separator.bottomAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

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
}

- (void)toggleAnimated {
    self.isExpanded = !self.isExpanded;
    CGFloat targetHeight = self.isExpanded ? 150.0 : 0.0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.25;
        context.allowsImplicitAnimation = YES;
        self->_heightConstraint.constant = targetHeight;
        [self.superview layoutSubtreeIfNeeded];
    }];
}

@end
