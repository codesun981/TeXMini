#import "TMEditorTextView.h"
#import "TMLaTeXHighlighter.h"

@implementation TMEditorTextView

- (void)setupEditor {
    self.allowsUndo = YES;
    self.automaticQuoteSubstitutionEnabled = NO;
    self.automaticDashSubstitutionEnabled = NO;
    self.automaticTextReplacementEnabled = NO;
    self.automaticSpellingCorrectionEnabled = NO;
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

#pragma mark - 智能符号配对与缩进

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    if ([string isKindOfClass:[NSString class]]) {
        NSString *str = (NSString *)string;
        NSString *closing = nil;
        if ([str isEqualToString:@"{"]) closing = @"}";
        else if ([str isEqualToString:@"["]) closing = @"]";
        else if ([str isEqualToString:@"("]) closing = @")";
        else if ([str isEqualToString:@"$"]) closing = @"$";

        if (closing) {
            NSString *pair = [str stringByAppendingString:closing];
            [super insertText:pair replacementRange:replacementRange];
            NSRange sel = self.selectedRange;
            if (sel.location > 0) {
                [self setSelectedRange:NSMakeRange(sel.location - 1, 0)];
            }
            return;
        }

        // 智能回车换行保持上一行缩进
        if ([str isEqualToString:@"\n"]) {
            NSRange sel = self.selectedRange;
            NSString *full = self.string;
            NSRange lineRange = [full lineRangeForRange:NSMakeRange(sel.location, 0)];
            NSString *currentLine = [full substringWithRange:lineRange];

            NSUInteger indentCount = 0;
            while (indentCount < currentLine.length && [currentLine characterAtIndex:indentCount] == ' ') {
                indentCount++;
            }

            [super insertText:@"\n" replacementRange:replacementRange];
            if (indentCount > 0) {
                NSString *indentStr = [@"" stringByPaddingToLength:indentCount withString:@" " startingAtIndex:0];
                [super insertText:indentStr replacementRange:NSMakeRange(self.selectedRange.location, 0)];
            }
            return;
        }
    }

    [super insertText:string replacementRange:replacementRange];
}

- (void)keyDown:(NSEvent *)event {
    // 处理 Tab 键为 2 个空格
    if (event.keyCode == 48) { // Tab key
        if (!(event.modifierFlags & NSEventModifierFlagShift)) {
            [self insertText:@"  " replacementRange:self.selectedRange];
            return;
        }
    }
    [super keyDown:event];
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
