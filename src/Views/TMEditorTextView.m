#import "TMEditorTextView.h"
#import "TMLaTeXHighlighter.h"
#import "TMEditActions.h"

static NSString *const kTMIndentUnit = @"  ";

@implementation TMEditorTextView

- (void)setupEditor {
    _softWrapEnabled = YES;
    self.allowsUndo = YES;
    self.automaticQuoteSubstitutionEnabled = NO;
    self.automaticDashSubstitutionEnabled = NO;
    self.automaticTextReplacementEnabled = NO;
    self.automaticSpellingCorrectionEnabled = NO;
    self.usesFindBar = YES;
    self.incrementalSearchingEnabled = YES;
    self.font = [TMLaTeXHighlighter baseFont];
    self.textColor = [NSColor textColor];
    self.backgroundColor = [NSColor textBackgroundColor];
    self.insertionPointColor = [NSColor controlAccentColor];

    self.textContainerInset = NSMakeSize(8, 8);
    self.textContainer.lineFragmentPadding = 4;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textStorageDidProcessEditingNotification:)
                                                 name:NSTextStorageDidProcessEditingNotification
                                               object:self.textStorage];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)rehighlightAll {
    if (self.textStorage.length > 0) {
        [TMLaTeXHighlighter highlightTextStorage:self.textStorage inRange:NSMakeRange(0, self.textStorage.length)];
    }
}

- (void)setEditorFontSize:(CGFloat)size {
    size = MAX(9.0, MIN(30.0, size));
    [TMLaTeXHighlighter setBaseFontSize:size];
    self.font = [TMLaTeXHighlighter baseFont];
    [self rehighlightAll];
    [self.enclosingScrollView.verticalRulerView setNeedsDisplay:YES];
}

- (CGFloat)editorFontSize {
    return [TMLaTeXHighlighter baseFontSize];
}

- (void)setEditorFontName:(NSString *)editorFontName {
    [TMLaTeXHighlighter setBaseFontName:editorFontName];
    self.font = [TMLaTeXHighlighter baseFont];
    [self rehighlightAll];
    [self.enclosingScrollView.verticalRulerView setNeedsDisplay:YES];
}

- (NSString *)editorFontName {
    return [TMLaTeXHighlighter baseFontName];
}

#pragma mark - 自动换行

- (void)setSoftWrapEnabled:(BOOL)softWrapEnabled {
    _softWrapEnabled = softWrapEnabled;
    NSScrollView *scrollView = self.enclosingScrollView;
    NSTextContainer *container = self.textContainer;
    if (softWrapEnabled) {
        self.horizontallyResizable = NO;
        self.autoresizingMask = NSViewWidthSizable;
        container.widthTracksTextView = YES;
        CGFloat width = scrollView ? scrollView.contentSize.width : self.bounds.size.width;
        container.containerSize = NSMakeSize(width, FLT_MAX);
        [self setFrameSize:NSMakeSize(width, self.frame.size.height)];
        scrollView.hasHorizontalScroller = NO;
    } else {
        container.widthTracksTextView = NO;
        container.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
        self.horizontallyResizable = YES;
        self.autoresizingMask = NSViewNotSizable;
        self.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
        scrollView.hasHorizontalScroller = YES;
    }
    [self.layoutManager ensureLayoutForTextContainer:container];
    [self sizeToFit];
    [self setNeedsDisplay:YES];
}

#pragma mark - 括号匹配

static BOOL TMIsOpenBracket(unichar c) { return c == '{' || c == '[' || c == '('; }
static BOOL TMIsCloseBracket(unichar c) { return c == '}' || c == ']' || c == ')'; }
static unichar TMMatchingBracket(unichar c) {
    switch (c) {
        case '{': return '}'; case '}': return '{';
        case '[': return ']'; case ']': return '[';
        case '(': return ')'; case ')': return '(';
        default: return 0;
    }
}

/// 从 index 处的括号出发寻找配对括号，跳过被反斜杠转义的括号。找不到返回 NSNotFound。
- (NSUInteger)matchingBracketIndexForIndex:(NSUInteger)index {
    NSString *text = self.string;
    if (index >= text.length) return NSNotFound;
    unichar c = [text characterAtIndex:index];
    unichar partner = TMMatchingBracket(c);
    if (partner == 0) return NSNotFound;

    const NSUInteger limit = 20000;
    NSInteger depth = 0;
    if (TMIsOpenBracket(c)) {
        NSUInteger end = MIN(text.length, index + limit);
        for (NSUInteger i = index; i < end; i++) {
            unichar ch = [text characterAtIndex:i];
            if (i > 0 && [text characterAtIndex:i - 1] == '\\') continue;
            if (ch == c) depth++;
            else if (ch == partner && --depth == 0) return i;
        }
    } else {
        NSUInteger start = index > limit ? index - limit : 0;
        for (NSInteger i = (NSInteger)index; i >= (NSInteger)start; i--) {
            unichar ch = [text characterAtIndex:(NSUInteger)i];
            if (i > 0 && [text characterAtIndex:(NSUInteger)i - 1] == '\\') continue;
            if (ch == c) depth++;
            else if (ch == partner && --depth == 0) return (NSUInteger)i;
        }
    }
    return NSNotFound;
}

- (void)flashMatchingBracketForCursorAt:(NSUInteger)loc {
    NSString *text = self.string;
    NSUInteger candidate = NSNotFound;
    // 优先看光标左边的字符（刚输入完的闭合括号），其次看右边
    if (loc > 0 && loc <= text.length) {
        unichar left = [text characterAtIndex:loc - 1];
        if (TMIsOpenBracket(left) || TMIsCloseBracket(left)) candidate = loc - 1;
    }
    if (candidate == NSNotFound && loc < text.length) {
        unichar right = [text characterAtIndex:loc];
        if (TMIsOpenBracket(right) || TMIsCloseBracket(right)) candidate = loc;
    }
    if (candidate == NSNotFound) return;
    if (candidate > 0 && [text characterAtIndex:candidate - 1] == '\\') return;

    NSUInteger match = [self matchingBracketIndexForIndex:candidate];
    if (match != NSNotFound) {
        [self showFindIndicatorForRange:NSMakeRange(match, 1)];
    }
}

- (void)textStorageDidProcessEditingNotification:(NSNotification *)note {
    NSTextStorage *storage = (NSTextStorage *)note.object;
    if (storage.editedMask & NSTextStorageEditedCharacters) {
        NSRange editedRange = storage.editedRange;
        dispatch_async(dispatch_get_main_queue(), ^{
            [TMLaTeXHighlighter highlightTextStorage:storage inRange:editedRange];
        });
    }
}

#pragma mark - 可撤销的整行替换

/// 把 range 所在的整行区域替换为 transform 的结果，注册撤销，并让选区覆盖替换后的文本。
- (void)transformLinesInSelectionUsing:(NSString *(^)(NSString *lines))transform {
    NSRange sel = self.selectedRange;
    NSString *full = self.string;
    NSRange lineRange = [full lineRangeForRange:sel];
    NSString *original = [full substringWithRange:lineRange];
    NSString *replacement = transform(original);
    if ([replacement isEqualToString:original]) return;

    if (![self shouldChangeTextInRange:lineRange replacementString:replacement]) return;
    [self.textStorage replaceCharactersInRange:lineRange withString:replacement];
    [self didChangeText];

    // 单光标：保持在同一行、按行首变化量偏移；多行选区：覆盖整个替换区域
    if (sel.length == 0) {
        NSInteger delta = (NSInteger)replacement.length - (NSInteger)original.length;
        NSInteger newLoc = (NSInteger)sel.location + delta;
        newLoc = MAX((NSInteger)lineRange.location, MIN(newLoc, (NSInteger)(lineRange.location + replacement.length)));
        [self setSelectedRange:NSMakeRange((NSUInteger)newLoc, 0)];
    } else {
        [self setSelectedRange:NSMakeRange(lineRange.location, replacement.length)];
    }
}

- (IBAction)toggleComment:(id)sender {
    [self transformLinesInSelectionUsing:^NSString *(NSString *lines) {
        return [TMEditActions toggledCommentForLines:lines];
    }];
}

- (IBAction)indentSelection:(id)sender {
    [self transformLinesInSelectionUsing:^NSString *(NSString *lines) {
        return [TMEditActions indentedLines:lines indent:kTMIndentUnit];
    }];
}

- (IBAction)outdentSelection:(id)sender {
    [self transformLinesInSelectionUsing:^NSString *(NSString *lines) {
        return [TMEditActions outdentedLines:lines width:kTMIndentUnit.length];
    }];
}

- (BOOL)selectionSpansMultipleLines {
    NSRange sel = self.selectedRange;
    if (sel.length == 0) return NO;
    NSRange r = [self.string rangeOfString:@"\n" options:0 range:sel];
    return r.location != NSNotFound && r.location < NSMaxRange(sel) - 1;
}

#pragma mark - 智能符号配对与缩进

- (unichar)characterAtOffset:(NSInteger)offset fromLocation:(NSUInteger)loc {
    NSInteger idx = (NSInteger)loc + offset;
    if (idx < 0 || idx >= (NSInteger)self.string.length) return 0;
    return [self.string characterAtIndex:(NSUInteger)idx];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    if ([string isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)string;
        NSRange sel = self.selectedRange;

        // 1. 输入闭合符号且下一字符正好是它：直接跳过
        if (sel.length == 0 && str.length == 1) {
            unichar typed = [str characterAtIndex:0];
            if ((typed == '}' || typed == ']' || typed == ')' || typed == '$') &&
                [self characterAtOffset:0 fromLocation:sel.location] == typed) {
                [self setSelectedRange:NSMakeRange(sel.location + 1, 0)];
                return;
            }
        }

        // 2. 输入开符号：自动补闭合（选区非空时包裹选区）
        NSString *closing = nil;
        if ([str isEqualToString:@"{"]) closing = @"}";
        else if ([str isEqualToString:@"["]) closing = @"]";
        else if ([str isEqualToString:@"("]) closing = @")";
        else if ([str isEqualToString:@"$"]) closing = @"$";

        if (closing) {
            if (sel.length > 0) {
                NSString *selected = [self.string substringWithRange:sel];
                NSString *wrapped = [NSString stringWithFormat:@"%@%@%@", str, selected, closing];
                [super insertText:wrapped replacementRange:sel];
                [self setSelectedRange:NSMakeRange(sel.location + 1, selected.length)];
                return;
            }
            // 光标前是反义的反斜杠（如 \{）时不配对
            if ([self characterAtOffset:-1 fromLocation:sel.location] == '\\') {
                [super insertText:str replacementRange:replacementRange];
                return;
            }
            NSString *pair = [str stringByAppendingString:closing];
            [super insertText:pair replacementRange:replacementRange];
            NSRange after = self.selectedRange;
            if (after.location > 0) {
                [self setSelectedRange:NSMakeRange(after.location - 1, 0)];
            }
            // \cite{ \ref{ \begin{ 之后自动弹出候选
            if ([str isEqualToString:@"{"]) [self triggerArgumentCompletionIfNeeded];
            return;
        }

        // 3. 回车：保持缩进；若当前行有未闭合的 \begin{X}，自动补 \end{X}
        if ([str isEqualToString:@"\n"]) {
            NSString *full = self.string;
            NSRange lineRange = [full lineRangeForRange:NSMakeRange(sel.location, 0)];
            NSString *currentLine = [full substringWithRange:lineRange];
            NSString *indent = [TMEditActions leadingWhitespaceOfLine:currentLine];
            NSString *env = [TMEditActions environmentToCloseInLine:currentLine];

            if (env && [self shouldAutoCloseEnvironment:env afterLineRange:lineRange]) {
                NSString *block = [NSString stringWithFormat:@"\n%@%@\n%@\\end{%@}", indent, kTMIndentUnit, indent, env];
                [super insertText:block replacementRange:replacementRange];
                // 光标放在中间行末尾
                NSUInteger cursor = self.selectedRange.location - (indent.length + 6 + env.length + 1);
                [self setSelectedRange:NSMakeRange(cursor, 0)];
                return;
            }

            [super insertText:[@"\n" stringByAppendingString:indent] replacementRange:replacementRange];
            return;
        }
    }

    [super insertText:string replacementRange:replacementRange];
}

/// 若紧接着的下一行已经是 \end{env}，说明用户只是在环境内部换行，不再重复补全。
- (BOOL)shouldAutoCloseEnvironment:(NSString *)env afterLineRange:(NSRange)lineRange {
    NSString *full = self.string;
    NSUInteger next = NSMaxRange(lineRange);
    if (next >= full.length) return YES;
    NSRange nextLineRange = [full lineRangeForRange:NSMakeRange(next, 0)];
    NSString *nextLine = [[full substringWithRange:nextLineRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *endToken = [NSString stringWithFormat:@"\\end{%@}", env];
    return ![nextLine hasPrefix:endToken];
}

- (void)deleteBackward:(id)sender {
    NSRange sel = self.selectedRange;
    if (sel.length == 0 && sel.location > 0) {
        unichar prev = [self characterAtOffset:-1 fromLocation:sel.location];
        unichar next = [self characterAtOffset:0 fromLocation:sel.location];
        BOOL isPair = (prev == '{' && next == '}') || (prev == '[' && next == ']') ||
                      (prev == '(' && next == ')') || (prev == '$' && next == '$');
        if (isPair) {
            NSRange pairRange = NSMakeRange(sel.location - 1, 2);
            if ([self shouldChangeTextInRange:pairRange replacementString:@""]) {
                [self.textStorage replaceCharactersInRange:pairRange withString:@""];
                [self didChangeText];
                [self setSelectedRange:NSMakeRange(sel.location - 1, 0)];
            }
            return;
        }
    }
    [super deleteBackward:sender];
}

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 48) { // Tab
        BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
        if (shift) {
            [self outdentSelection:nil];
            return;
        }
        if ([self selectionSpansMultipleLines]) {
            [self indentSelection:nil];
            return;
        }
        [self insertText:kTMIndentUnit replacementRange:self.selectedRange];
        return;
    }
    // ⌃Space：手动触发补全（系统默认的 Esc / F5 依然可用）
    if (event.keyCode == 49 && (event.modifierFlags & NSEventModifierFlagControl)) {
        [self complete:nil];
        return;
    }
    [super keyDown:event];
}

#pragma mark - 补全

- (void)triggerArgumentCompletionIfNeeded {
    if (!self.completionProvider) return;
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
    if (ctx.kind == TMCompletionKindCitation || ctx.kind == TMCompletionKindReference || ctx.kind == TMCompletionKindEnvironment) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self complete:nil];
        });
    }
}

- (NSRange)rangeForUserCompletion {
    if (self.completionProvider) {
        TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
        if (ctx.kind != TMCompletionKindNone) return ctx.partialRange;
    }
    return [super rangeForUserCompletion];
}

- (NSArray<NSString *> *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index {
    if (self.completionProvider) {
        TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:NSMaxRange(charRange)];
        if (ctx.kind != TMCompletionKindNone) {
            if (index) *index = 0;
            return [self.completionProvider completionsForContext:ctx currentText:self.string];
        }
    }
    return [super completionsForPartialWordRange:charRange indexOfSelectedItem:index];
}

- (void)insertCompletion:(NSString *)word forPartialWordRange:(NSRange)charRange movement:(NSInteger)movement isFinal:(BOOL)flag {
    [super insertCompletion:word forPartialWordRange:charRange movement:movement isFinal:flag];
    if (!flag || !self.completionProvider) return;
    // 选定 \begin{env} 后，若下一行还没有 \end{env}，顺手补上，并把光标停在环境体内
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:charRange.location];
    if (ctx.kind != TMCompletionKindEnvironment) return;
    NSString *full = self.string;
    NSRange lineRange = [full lineRangeForRange:NSMakeRange(charRange.location, 0)];
    NSString *line = [full substringWithRange:lineRange];
    if ([line containsString:@"\\end{"]) return;
    NSString *env = [TMEditActions environmentToCloseInLine:line];
    if (!env || ![env isEqualToString:word]) return;
    if (![self shouldAutoCloseEnvironment:env afterLineRange:lineRange]) return;

    // 跳过紧随的 “}”，在行尾插入 换行 + 缩进 + \end{env}
    NSString *indent = [TMEditActions leadingWhitespaceOfLine:line];
    NSUInteger lineEnd = NSMaxRange(lineRange);
    if (lineEnd > lineRange.location && [full characterAtIndex:lineEnd - 1] == '\n') lineEnd--;
    NSString *block = [NSString stringWithFormat:@"\n%@%@\n%@\\end{%@}", indent, kTMIndentUnit, indent, env];
    NSRange insertAt = NSMakeRange(lineEnd, 0);
    if (![self shouldChangeTextInRange:insertAt replacementString:block]) return;
    [self.textStorage replaceCharactersInRange:insertAt withString:block];
    [self didChangeText];
    [self setSelectedRange:NSMakeRange(lineEnd + 1 + indent.length + kTMIndentUnit.length, 0)];
}

- (void)insertBacktab:(id)sender {
    [self outdentSelection:sender];
}

- (void)mouseDown:(NSEvent *)event {
    if ((event.modifierFlags & NSEventModifierFlagCommand) && event.clickCount == 1) {
        // 先把光标放到点击处，再让控制器按新光标行做正向同步
        NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
        NSUInteger idx = [self characterIndexForInsertionAtPoint:p];
        [self setSelectedRange:NSMakeRange(MIN(idx, self.string.length), 0)];
        if ([self.editorDelegate respondsToSelector:@selector(editorTextViewDidRequestForwardSync)]) {
            [self.editorDelegate editorTextViewDidRequestForwardSync];
        }
        return;
    }
    [super mouseDown:event];
    // 双击：保留系统的选词行为，同时把 PDF 同步到这一行
    if (event.clickCount == 2 && [self.editorDelegate respondsToSelector:@selector(editorTextViewDidRequestForwardSync)]) {
        [self.editorDelegate editorTextViewDidRequestForwardSync];
    }
}

#pragma mark - 光标行列位置更新

- (void)setSelectedRanges:(NSArray<NSValue *> *)selectedRanges affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting {
    [super setSelectedRanges:selectedRanges affinity:affinity stillSelecting:stillSelecting];

    if (selectedRanges.count > 0) {
        NSRange sel = selectedRanges.firstObject.rangeValue;
        NSString *text = self.string;
        NSUInteger loc = MIN(sel.location, text.length);

        NSUInteger line = 1;
        NSUInteger col = 1;
        NSUInteger lastLineStart = 0;

        for (NSUInteger i = 0; i < loc; i++) {
            if ([text characterAtIndex:i] == '\n') {
                line++;
                lastLineStart = i + 1;
            }
        }
        col = (loc - lastLineStart) + 1;

        if ([self.editorDelegate respondsToSelector:@selector(editorTextViewDidChangeCursorPositionToLine:column:)]) {
            [self.editorDelegate editorTextViewDidChangeCursorPositionToLine:line column:col];
        }

        if (sel.length == 0 && !stillSelecting) {
            [self flashMatchingBracketForCursorAt:loc];
        }
    }
}

#pragma mark - 行跳转

- (void)jumpToLine:(NSInteger)lineNumber column:(NSInteger)column {
    NSString *text = self.string;
    if (text.length == 0) return;

    NSUInteger currentLine = 1;
    NSUInteger charIndex = 0;
    NSUInteger targetLocation = 0;
    NSUInteger targetLength = 0;

    while (charIndex < text.length) {
        NSRange lineRange = [text lineRangeForRange:NSMakeRange(charIndex, 0)];
        if (currentLine == (NSUInteger)lineNumber) {
            targetLocation = lineRange.location;
            targetLength = lineRange.length;
            if (column > 1 && (NSUInteger)column <= lineRange.length) {
                targetLocation += (column - 1);
                targetLength = 0;
            }
            break;
        }
        charIndex = NSMaxRange(lineRange);
        currentLine++;
    }

    if (targetLocation <= text.length) {
        [self setSelectedRange:NSMakeRange(targetLocation, targetLength)];
        [self scrollLocationToCenter:targetLocation];
        [self showFindIndicatorForRange:NSMakeRange(targetLocation, targetLength > 0 ? targetLength : 1)];
    }
}

/// 把 location 所在行滚到编辑器视口垂直居中（与 PDF 端的定位行为对称）。
- (void)scrollLocationToCenter:(NSUInteger)location {
    NSScrollView *scrollView = self.enclosingScrollView;
    if (!scrollView) {
        [self scrollRangeToVisible:NSMakeRange(location, 0)];
        return;
    }
    NSUInteger glyph = [self.layoutManager glyphIndexForCharacterAtIndex:MIN(location, self.string.length)];
    NSRect lineRect = [self.layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    lineRect.origin.y += self.textContainerInset.height;

    NSClipView *clip = scrollView.contentView;
    NSRect visible = clip.bounds;
    CGFloat y = NSMidY(lineRect) - NSHeight(visible) / 2.0;
    y = MAX(0, MIN(y, NSHeight(self.bounds) - NSHeight(visible)));
    [clip scrollToPoint:NSMakePoint(visible.origin.x, y)];
    [scrollView reflectScrolledClipView:clip];
}

@end
