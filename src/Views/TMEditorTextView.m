#import "TMEditorTextView.h"
#import "TMLaTeXHighlighter.h"
#import "TMEditActions.h"

static NSString *const kTMIndentUnit = @"  ";

@implementation TMEditorTextView

- (void)setupEditor {
    self.allowsUndo = YES;
    self.automaticQuoteSubstitutionEnabled = NO;
    self.automaticDashSubstitutionEnabled = NO;
    self.automaticTextReplacementEnabled = NO;
    self.automaticSpellingCorrectionEnabled = NO;
    self.usesFindBar = YES;
    self.incrementalSearchingEnabled = YES;
    self.font = [NSFont fontWithName:@"Menlo" size:13.5] ?: [NSFont monospacedSystemFontOfSize:13.5 weight:NSFontWeightRegular];
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
    [super keyDown:event];
}

- (void)insertBacktab:(id)sender {
    [self outdentSelection:sender];
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
        [self scrollRangeToVisible:NSMakeRange(targetLocation, targetLength)];
        [self showFindIndicatorForRange:NSMakeRange(targetLocation, targetLength > 0 ? targetLength : 1)];
    }
}

@end
