#import "TMLineNumberRulerView.h"

@implementation TMLineNumberRulerView {
    NSDictionary *_attributes;
    NSDictionary<NSNumber *, NSNumber *> *_issueMarks;
}

- (void)setIssueMarks:(NSDictionary<NSNumber *, NSNumber *> *)marks {
    _issueMarks = marks.count ? [marks copy] : nil;
    [self setNeedsDisplay:YES];
}

- (void)drawIssueMarkForLine:(NSUInteger)lineNumber inLineRect:(NSRect)lineRect atY:(CGFloat)y {
    NSNumber *kind = _issueMarks[@(lineNumber)];
    if (!kind) return;
    NSColor *color;
    switch (kind.integerValue) {
        case 0: color = [NSColor systemRedColor]; break;
        case 1: color = [NSColor systemOrangeColor]; break;
        default: color = [NSColor systemYellowColor]; break;
    }
    CGFloat d = 6.0;
    NSRect dot = NSMakeRect(5.0, y + (lineRect.size.height - d) / 2.0, d, d);
    [color setFill];
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
}

- (instancetype)initWithScrollView:(NSScrollView *)scrollView {
    self = [super initWithScrollView:scrollView orientation:NSVerticalRuler];
    if (self) {
        self.clientView = scrollView.documentView;
        self.ruleThickness = 42.0;

        NSFont *font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
        NSColor *color = [NSColor secondaryLabelColor];
        _attributes = @{
            NSFontAttributeName: font,
            NSForegroundColorAttributeName: color
        };

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(textDidChange:)
                                                     name:NSTextDidChangeNotification
                                                   object:scrollView.documentView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(frameDidChange:)
                                                     name:NSViewFrameDidChangeNotification
                                                   object:scrollView.documentView];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(boundsDidChange:)
                                                     name:NSViewBoundsDidChangeNotification
                                                   object:scrollView.contentView];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)textDidChange:(NSNotification *)notification {
    [self updateThickness];
    [self setNeedsDisplay:YES];
}

- (void)frameDidChange:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
}

- (void)boundsDidChange:(NSNotification *)notification {
    [self setNeedsDisplay:YES];
}

- (void)updateThickness {
    NSTextView *textView = (NSTextView *)self.clientView;
    if (![textView isKindOfClass:[NSTextView class]]) return;

    NSString *text = textView.string;
    NSUInteger length = text.length;
    if (length == 0) return;

    NSUInteger numberOfLines = 1;
    for (NSUInteger i = 0; i < length; i++) {
        if ([text characterAtIndex:i] == '\n') {
            numberOfLines++;
        }
    }

    NSString *sample = [NSString stringWithFormat:@"%lu", (unsigned long)numberOfLines];
    NSSize size = [sample sizeWithAttributes:_attributes];
    CGFloat required = MAX(42.0, size.width + 16.0);
    if (fabs(self.ruleThickness - required) > 1.0) {
        self.ruleThickness = required;
    }
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView *textView = (NSTextView *)self.clientView;
    if (![textView isKindOfClass:[NSTextView class]]) return;

    NSLayoutManager *layoutManager = textView.layoutManager;
    NSTextContainer *textContainer = textView.textContainer;
    NSString *text = textView.string;
    if (!layoutManager || !textContainer || !text) return;

    // 标尺背景及右侧分割线
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);
    [[NSColor separatorColor] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMaxX(self.bounds) - 0.5, 0)
                              toPoint:NSMakePoint(NSMaxX(self.bounds) - 0.5, NSMaxY(self.bounds))];

    NSRect visibleRect = textView.enclosingScrollView.contentView.bounds;
    NSRange visibleGlyphRange = [layoutManager glyphRangeForBoundingRect:visibleRect inTextContainer:textContainer];
    if (visibleGlyphRange.length == 0 && text.length > 0) return;

    NSRange visibleCharRange = [layoutManager characterRangeForGlyphRange:visibleGlyphRange actualGlyphRange:NULL];

    // 计算起始行号
    NSUInteger lineNumber = 1;
    for (NSUInteger idx = 0; idx < visibleCharRange.location && idx < text.length; idx++) {
        if ([text characterAtIndex:idx] == '\n') {
            lineNumber++;
        }
    }

    NSUInteger charIndex = visibleCharRange.location;
    NSUInteger maxCharIndex = NSMaxRange(visibleCharRange);

    // 严密循环：确保严格递增且永远不会陷入死循环
    while (charIndex < text.length && charIndex <= maxCharIndex) {
        NSUInteger glyphIndex = [layoutManager glyphIndexForCharacterAtIndex:charIndex];
        NSRect lineRect = [layoutManager lineFragmentRectForGlyphAtIndex:glyphIndex effectiveRange:NULL];

        NSPoint viewPoint = [self convertPoint:NSMakePoint(0, lineRect.origin.y + textView.textContainerInset.height) fromView:textView];
        CGFloat y = viewPoint.y;

        NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize labelSize = [label sizeWithAttributes:_attributes];

        NSRect labelRect = NSMakeRect(self.ruleThickness - labelSize.width - 8.0,
                                      y + (lineRect.size.height - labelSize.height) / 2.0,
                                      labelSize.width,
                                      labelSize.height);

        [label drawInRect:labelRect withAttributes:_attributes];
        if (_issueMarks) [self drawIssueMarkForLine:lineNumber inLineRect:lineRect atY:y];

        NSRange lineRange = [text lineRangeForRange:NSMakeRange(charIndex, 0)];
        if (lineRange.length == 0) {
            break;
        }
        charIndex = NSMaxRange(lineRange);
        lineNumber++;
    }

    // 末尾回车行的行号绘制
    if ([text hasSuffix:@"\n"] && (maxCharIndex >= text.length || text.length == 0)) {
        NSRect extraRect = [layoutManager extraLineFragmentRect];
        NSPoint viewPoint = [self convertPoint:NSMakePoint(0, extraRect.origin.y + textView.textContainerInset.height) fromView:textView];
        NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
        NSSize labelSize = [label sizeWithAttributes:_attributes];
        NSRect labelRect = NSMakeRect(self.ruleThickness - labelSize.width - 8.0,
                                      viewPoint.y + (extraRect.size.height - labelSize.height) / 2.0,
                                      labelSize.width,
                                      labelSize.height);
        [label drawInRect:labelRect withAttributes:_attributes];
    }
}

@end
