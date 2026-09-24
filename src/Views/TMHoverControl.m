#import "TMHoverControl.h"

@implementation TMHoverControl

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        self.translatesAutoresizingMaskIntoConstraints = NO;
        [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                           options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInActiveApp | NSTrackingInVisibleRect)
                                                             owner:self
                                                          userInfo:nil]];
    }
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer {
    if (self.cardStyle) {
        NSColor *border = self.selected ? [NSColor controlAccentColor]
                        : self.isHovered ? [[NSColor controlAccentColor] colorWithAlphaComponent:0.45]
                                         : [[NSColor labelColor] colorWithAlphaComponent:0.08];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = self.selected ? 2 : 1;
        self.layer.borderColor = border.CGColor;
        self.layer.backgroundColor = (self.selected ? [[NSColor controlAccentColor] colorWithAlphaComponent:0.06]
                                                    : [[NSColor labelColor] colorWithAlphaComponent:self.isHovered ? 0.035 : 0.015]).CGColor;
    } else {
        self.layer.backgroundColor = self.isHovered ? [[NSColor labelColor] colorWithAlphaComponent:0.05].CGColor
                                                    : [NSColor clearColor].CGColor;
    }
}

- (void)setIsHovered:(BOOL)isHovered {
    _isHovered = isHovered;
    self.needsDisplay = YES;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    self.needsDisplay = YES;
}

- (void)mouseEntered:(NSEvent *)event { self.isHovered = YES; }
- (void)mouseExited:(NSEvent *)event  { self.isHovered = NO; }
- (void)mouseDown:(NSEvent *)event {}

- (void)mouseUp:(NSEvent *)event {
    if (!NSPointInRect([self convertPoint:event.locationInWindow fromView:nil], self.bounds)) return;
    if (event.clickCount == 2 && self.onDoubleClick) self.onDoubleClick();
    else if (event.clickCount == 1 && self.onClick) self.onClick();
}

- (void)resetCursorRects {
    [self addCursorRect:self.bounds cursor:[NSCursor pointingHandCursor]];
}

- (NSView *)hitTest:(NSPoint)point {
    NSView *v = [super hitTest:point];
    return (v && [v isDescendantOf:self]) ? self : v;
}

- (void)fillWithContent:(NSView *)content {
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.topAnchor constraintEqualToAnchor:self.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
}

@end
