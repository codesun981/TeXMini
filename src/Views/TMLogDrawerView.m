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

    _textView = [[NSTextView alloc] init];
    _textView.editable = NO;
    _textView.selectable = YES;
    _textView.font = [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular];
    _textView.textColor = [NSColor secondaryLabelColor];
    _textView.backgroundColor = [NSColor textBackgroundColor];
    _textView.textContainerInset = NSMakeSize(8, 6);

    _scrollView.documentView = _textView;
    [self addSubview:_scrollView];

    _heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    _heightConstraint.active = YES;

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];
}

- (void)appendLogText:(NSString *)text {
    NSAttributedString *attr = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont monospacedSystemFontOfSize:11.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor labelColor]
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
