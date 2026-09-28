#import "TMEditorTextView.h"
#import "TMLaTeXHighlighter.h"
#import "TMEditActions.h"
#import "TMCompletionPopup.h"

static NSString *const kTMIndentUnit = @"  ";

@implementation TMEditorTextView {
    /// 当前配对括号的两个 1 字符 range（临时属性），选区变化时清掉重画。
    NSRange _bracketRanges[2];
    BOOL _hasBracketHighlight;
    TMCompletionPopup *_completionPopup;
    /// 正在把候选写进正文，这期间的文字 / 选区变化不要再刷新浮窗
    BOOL _acceptingCompletion;
    /// 待高亮的范围（合并同一轮 runloop 内的多次编辑）；location == NSNotFound 表示没有。
    NSRange _pendingHighlightRange;
    BOOL _highlightScheduled;
    TMLineIndex *_lineIndex;
    NSUInteger _textRevision;
    NSUInteger _completionGeneration;
    BOOL _completionWanted;
    BOOL _completionRefreshScheduled;
    BOOL _completionInFlight;
}

- (void)setupEditor {
    _softWrapEnabled = YES;
    _pendingHighlightRange = NSMakeRange(NSNotFound, 0);
    _highlightsCurrentLine = YES;
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
    // 接收从访达拖进来的文件（图片 → figure，.tex → \input）
    NSMutableArray *types = [self.registeredDraggedTypes mutableCopy] ?: [NSMutableArray array];
    if (![types containsObject:NSPasteboardTypeFileURL]) [types addObject:NSPasteboardTypeFileURL];
    [self registerForDraggedTypes:types];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textStorageWillProcessEditingNotification:)
                                                 name:NSTextStorageWillProcessEditingNotification
                                               object:self.textStorage];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(textStorageDidProcessEditingNotification:)
                                                 name:NSTextStorageDidProcessEditingNotification
                                               object:self.textStorage];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (TMLineIndex *)lineIndex {
    if (!_lineIndex || _lineIndex.length != self.textStorage.length) {
        _lineIndex = [[TMLineIndex alloc] initWithString:self.string];
    }
    return _lineIndex;
}

- (void)textStorageWillProcessEditingNotification:(NSNotification *)note {
    // 在 didProcess / 选区及行号尺刷新之前失效，不依赖多个观察者的调用顺序。
    if (((NSTextStorage *)note.object).editedMask & NSTextStorageEditedCharacters) {
        _lineIndex = nil;
        _textRevision++;
        _completionGeneration++;
        _completionInFlight = NO;
    }
}

- (void)setString:(NSString *)string {
    [self dismissCompletion];
    [super setString:string];
}

- (void)setCompletionDocumentKey:(NSString *)key {
    [self dismissCompletion];
    _completionDocumentKey = [key copy] ?: NSUUID.UUID.UUIDString;
}

- (void)rehighlightAll {
    // 整篇已同步高亮，之前排队的局部高亮不必再做
    _pendingHighlightRange = NSMakeRange(NSNotFound, 0);
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

- (TMEditorSyntax)syntax {
    return [TMLaTeXHighlighter syntaxForTextStorage:self.textStorage];
}

- (void)setSyntax:(TMEditorSyntax)syntax {
    if (syntax == self.syntax) return;
    [TMLaTeXHighlighter setSyntax:syntax forTextStorage:self.textStorage];
    [self rehighlightAll];
}

- (BOOL)isLaTeX {
    return self.syntax == TMEditorSyntaxLaTeX;
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

/// 从 index 处的括号出发寻找配对括号，跳过被反斜杠转义的括号以及注释、代码块里的括号。找不到返回 NSNotFound。
- (NSUInteger)matchingBracketIndexForIndex:(NSUInteger)index {
    NSString *text = self.string;
    TMLaTeXScanResult *scan = [TMLaTeXHighlighter lastScanForTextStorage:self.textStorage];
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
            if (ch != c && ch != partner) continue;
            if ([scan isIgnorableAtIndex:i]) continue;
            if (ch == c) depth++;
            else if (--depth == 0) return i;
        }
    } else {
        NSUInteger start = index > limit ? index - limit : 0;
        for (NSInteger i = (NSInteger)index; i >= (NSInteger)start; i--) {
            unichar ch = [text characterAtIndex:(NSUInteger)i];
            if (i > 0 && [text characterAtIndex:(NSUInteger)i - 1] == '\\') continue;
            if (ch != c && ch != partner) continue;
            if ([scan isIgnorableAtIndex:(NSUInteger)i]) continue;
            if (ch == c) depth++;
            else if (--depth == 0) return (NSUInteger)i;
        }
    }
    return NSNotFound;
}

- (void)flashMatchingBracketForCursorAt:(NSUInteger)loc {
    [self clearBracketHighlight];
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
    // 光标处的括号本身在注释或代码块里：不配对
    if ([[TMLaTeXHighlighter lastScanForTextStorage:self.textStorage] isIgnorableAtIndex:candidate]) return;

    NSUInteger match = [self matchingBracketIndexForIndex:candidate];
    if (match != NSNotFound) {
        [self setBracketHighlightAt:candidate and:match];
    }
}

#pragma mark - 括号常驻高亮（临时属性，不进 textStorage / 撤销栈）

- (void)setBracketHighlightAt:(NSUInteger)a and:(NSUInteger)b {
    NSColor *bg = [[NSColor controlAccentColor] colorWithAlphaComponent:0.28];
    _bracketRanges[0] = NSMakeRange(a, 1);
    _bracketRanges[1] = NSMakeRange(b, 1);
    _hasBracketHighlight = YES;
    for (int i = 0; i < 2; i++) {
        [self.layoutManager addTemporaryAttribute:NSBackgroundColorAttributeName value:bg forCharacterRange:_bracketRanges[i]];
    }
}

- (void)clearBracketHighlight {
    if (!_hasBracketHighlight) return;
    _hasBracketHighlight = NO;
    NSUInteger len = self.string.length;
    for (int i = 0; i < 2; i++) {
        if (NSMaxRange(_bracketRanges[i]) <= len) {
            [self.layoutManager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:_bracketRanges[i]];
        }
    }
}

#pragma mark - 当前行高亮

- (void)setHighlightsCurrentLine:(BOOL)highlightsCurrentLine {
    _highlightsCurrentLine = highlightsCurrentLine;
    [self setNeedsDisplay:YES];
}

/// 光标所在视觉行（自动换行时是行片段）在视图坐标里的横贯整宽的矩形。
- (NSRect)currentLineRectForCharacterIndex:(NSUInteger)index {
    NSLayoutManager *lm = self.layoutManager;
    NSUInteger length = self.string.length;
    NSRect r;
    if (length == 0 || (index >= length && [self.string hasSuffix:@"\n"])) {
        r = lm.extraLineFragmentRect;
        if (NSIsEmptyRect(r)) {
            // 空文档：用字体行高凑一个
            r = NSMakeRect(0, 0, self.bounds.size.width, [lm defaultLineHeightForFont:self.font ?: [NSFont userFixedPitchFontOfSize:13]]);
        }
    } else {
        NSUInteger glyph = [lm glyphIndexForCharacterAtIndex:MIN(index, length - 1)];
        r = [lm lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    }
    r.origin.y += self.textContainerInset.height;
    r.origin.x = 0;
    r.size.width = MAX(self.bounds.size.width, self.enclosingScrollView.contentSize.width);
    return r;
}

- (void)drawViewBackgroundInRect:(NSRect)rect {
    [super drawViewBackgroundInRect:rect];
    if (!self.highlightsCurrentLine) return;
    NSRange sel = self.selectedRange;
    if (sel.length > 0) return;
    NSRect line = [self currentLineRectForCharacterIndex:sel.location];
    if (!NSIntersectsRect(line, rect)) return;
    [[[NSColor controlAccentColor] colorWithAlphaComponent:0.07] setFill];
    NSRectFillUsingOperation(line, NSCompositingOperationSourceOver);
}

- (void)invalidateCurrentLineHighlightForSelection:(NSRange)sel {
    if (!self.highlightsCurrentLine) return;
    [self setNeedsDisplayInRect:[self currentLineRectForCharacterIndex:sel.location]];
}

- (void)textStorageDidProcessEditingNotification:(NSNotification *)note {
    NSTextStorage *storage = (NSTextStorage *)note.object;
    if (storage.editedMask & NSTextStorageEditedCharacters) {
        NSRange edited = storage.editedRange;
        NSRange pending = _pendingHighlightRange;
        if (_highlightScheduled && pending.location != NSNotFound) {
            // 把上一次的待高亮范围换算到这次编辑后的坐标，再与本次合并
            NSInteger delta = storage.changeInLength;
            NSUInteger oldEditEnd = NSMaxRange(edited) - delta;
            if (pending.location >= oldEditEnd) {
                pending.location += delta;
            } else if (NSMaxRange(pending) > edited.location) {
                pending.length = (NSUInteger)MAX((NSInteger)pending.length + delta, 0);
            }
            _pendingHighlightRange = NSUnionRange(pending, edited);
        } else {
            _pendingHighlightRange = edited;
        }
        if (_highlightScheduled) return;
        _highlightScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf flushPendingHighlight];
        });
    }
}

- (void)flushPendingHighlight {
    _highlightScheduled = NO;
    NSRange range = _pendingHighlightRange;
    _pendingHighlightRange = NSMakeRange(NSNotFound, 0);
    if (range.location == NSNotFound) return;
    // 手动夹到正文范围内（NSIntersectionRange 对空范围会返回 {0,0}，删除时会高亮错位置）
    NSUInteger length = self.textStorage.length;
    NSUInteger location = MIN(range.location, length);
    range = NSMakeRange(location, MIN(range.length, length - location));
    [TMLaTeXHighlighter highlightTextStorage:self.textStorage inRange:range];
}

- (TMLaTeXScanResult *)currentLaTeXScan {
    if (![self isLaTeX] || self.textStorage.length == 0) return nil;
    // 由高亮统一维护扫描与上一次着色的结构摘要；大纲不能提前覆盖该摘要。
    [self flushPendingHighlight];
    TMLaTeXScanResult *scan = [TMLaTeXHighlighter lastScanForTextStorage:self.textStorage];
    if (!scan) {
        [self rehighlightAll];
        scan = [TMLaTeXHighlighter lastScanForTextStorage:self.textStorage];
    }
    return scan;
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
        else if ([str isEqualToString:@"$"] && [self isLaTeX]) closing = @"$";

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
            if ([str isEqualToString:@"{"] && [self isLaTeX]) [self triggerArgumentCompletionIfNeeded];
            return;
        }

        // 3. 回车：保持缩进；若当前行有未闭合的 \begin{X}，自动补 \end{X}
        if ([str isEqualToString:@"\n"]) {
            NSString *full = self.string;
            NSRange lineRange = [full lineRangeForRange:NSMakeRange(sel.location, 0)];
            NSString *currentLine = [full substringWithRange:lineRange];
            NSString *indent = [TMEditActions leadingWhitespaceOfLine:currentLine];
            NSString *env = [self isLaTeX] ? [TMEditActions environmentToCloseInLine:currentLine] : nil;

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
    [self scheduleCommandCompletionIfNeeded];
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
    if ([self handleCompletionKey:event]) return;
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
        _completionWanted = YES;
        [self refreshCompletionIfNeeded];
    }
}

/// 输入 \ 加字母后停顿片刻，自动弹出命令候选；浮窗开着时每次编辑都会重新过滤。
/// 连续快速打完 \section 的人不会被弹窗打断：每敲一个键都会取消上一次还没弹出的请求。
- (void)scheduleCommandCompletionIfNeeded {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoCompleteCommand) object:nil];
    if (!self.completionProvider || ![self isLaTeX] || self.completionPopup.isVisible || self.hasMarkedText || self.selectedRange.length > 0) return;
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
    if (ctx.kind != TMCompletionKindCommand || ctx.partial.length < 2) return;
    [self performSelector:@selector(autoCompleteCommand) withObject:nil afterDelay:0.12];
}

- (void)autoCompleteCommand {
    // 延迟期间用户可能删掉或移走光标，弹之前再确认一次
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
    if (ctx.kind != TMCompletionKindCommand || ctx.partial.length < 2 || self.window.firstResponder != self) return;
    [self showCompletionPopup];
}

- (TMCompletionPopup *)completionPopup {
    if (!_completionPopup) {
        _completionPopup = [[TMCompletionPopup alloc] init];
        __weak typeof(self) weakSelf = self;
        _completionPopup.onAccept = ^(NSString *item) { [weakSelf acceptCompletion:item]; };
    }
    return _completionPopup;
}

/// ⌃Space / Esc / F5 以及 \cite{ 之后的自动弹出，都走自己的浮窗而不是系统弹窗
- (void)complete:(id)sender {
    [self showCompletionPopup];
}

/// 按光标处的上下文重新计算候选；没有上下文或没有候选就收起。
- (void)dismissCompletion {
    _completionWanted = NO;
    _completionInFlight = NO;
    _completionGeneration++;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoCompleteCommand) object:nil];
    [_completionPopup hide];
}

- (void)refreshCompletionIfNeeded {
    if (!_completionWanted || _completionRefreshScheduled) return;
    _completionRefreshScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TMEditorTextView *editor = weakSelf;
        if (!editor) return;
        editor->_completionRefreshScheduled = NO;
        if (editor->_completionWanted) [editor showCompletionPopup];
    });
}

- (void)showCompletionPopup {
    if (!self.completionProvider || self.hasMarkedText || self.selectedRanges.count != 1 ||
        self.selectedRange.length > 0 || !self.window.isKeyWindow || self.window.firstResponder != self) {
        [self dismissCompletion];
        return;
    }
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
    if (ctx.kind == TMCompletionKindNone) { [self dismissCompletion]; return; }
    _completionWanted = YES;
    _completionInFlight = YES;
    NSUInteger generation = ++_completionGeneration;
    NSUInteger revision = _textRevision;
    NSRange selection = self.selectedRange;
    if (!_completionDocumentKey) _completionDocumentKey = NSUUID.UUID.UUIDString;
    NSString *key = self.completionDocumentKey;
    __weak typeof(self) weakSelf = self;
    [self.completionProvider requestCompletionsForContext:ctx currentText:self.string documentKey:key revision:revision
                                             completion:^(NSArray<NSString *> *items) {
        TMEditorTextView *editor = weakSelf;
        if (!editor || editor->_completionGeneration != generation || !editor->_completionWanted) return;
        if (editor->_textRevision != revision || ![editor.completionDocumentKey isEqualToString:key] ||
            !NSEqualRanges(editor.selectedRange, selection) || editor.selectedRanges.count != 1 ||
            editor.hasMarkedText || !editor.window.isKeyWindow || editor.window.firstResponder != editor) {
            [editor dismissCompletion];
            return;
        }
        editor->_completionInFlight = NO;
        if (items.count == 0) {
            [editor dismissCompletion];
        } else {
            NSRect anchor = [editor firstRectForCharacterRange:ctx.partialRange actualRange:NULL];
            [editor.completionPopup showItems:items partial:ctx.partial anchorOnScreen:anchor parentWindow:editor.window font:editor.font];
        }
    }];
}

- (void)didChangeText {
    [super didChangeText];
    if (self.hasMarkedText) { [self dismissCompletion]; return; }
    if (!_acceptingCompletion) [self refreshCompletionIfNeeded];
}

- (BOOL)resignFirstResponder {
    [self dismissCompletion];
    return [super resignFirstResponder];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    [self dismissCompletion];
    [super viewWillMoveToWindow:newWindow];
}

/// 浮窗开着时拦下 ↑↓ 回车 Tab Esc；返回 NO 表示这个键照常交给编辑器
- (BOOL)handleCompletionKey:(NSEvent *)event {
    if (self.hasMarkedText) { [self dismissCompletion]; return NO; }
    if (!_completionWanted && !_completionPopup.isVisible) return NO;
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) return NO;
    if (event.keyCode == 53) { [self dismissCompletion]; return YES; }
    if (_completionInFlight || _completionRefreshScheduled) {
        if (event.keyCode == 125 || event.keyCode == 126 || event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 48) {
            // 最新候选尚未到达，交回正常编辑，绝不吞键或接受旧候选。
            [self dismissCompletion];
            return NO;
        }
    }
    if (!_completionPopup.isVisible) return NO;
    switch (event.keyCode) {
        case 125: [self.completionPopup moveSelectionBy:1]; return YES;   // ↓
        case 126: [self.completionPopup moveSelectionBy:-1]; return YES;  // ↑
        case 36: case 76: case 48: {                                      // 回车 / 小键盘回车 / Tab
            NSString *item = self.completionPopup.selectedItem;
            if (!item) return NO;
            [self acceptCompletion:item];
            return YES;
        }
        case 53: [self dismissCompletion]; return YES;                  // Esc
        default: return NO;
    }
}

/// 用选中的候选替换光标处正在输入的那段
- (void)acceptCompletion:(NSString *)word {
    // 双击也不能接受仍在刷新中的旧候选。
    if (_completionInFlight || _completionRefreshScheduled) return;
    [self dismissCompletion];
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:self.string cursorLocation:self.selectedRange.location];
    if (ctx.kind == TMCompletionKindNone) return;
    NSRange range = ctx.partialRange;
    if (![self shouldChangeTextInRange:range replacementString:word]) return;
    _acceptingCompletion = YES;
    [self.textStorage replaceCharactersInRange:range withString:word];
    [self didChangeText];
    [self setSelectedRange:NSMakeRange(range.location + word.length, 0)];
    _acceptingCompletion = NO;
    if (ctx.kind == TMCompletionKindEnvironment) [self closeEnvironmentAfterCompleting:word atLocation:range.location];
}

/// 选定 \begin{env} 后，若下一行还没有 \end{env}，顺手补上，并把光标停在环境体内
- (void)closeEnvironmentAfterCompleting:(NSString *)word atLocation:(NSUInteger)location {
    NSString *full = self.string;
    NSRange lineRange = [full lineRangeForRange:NSMakeRange(location, 0)];
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
    [self dismissCompletion];
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

#pragma mark - 拖放文件

- (NSArray<NSURL *> *)fileURLsInDraggingInfo:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
                                                            options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    return urls ?: @[];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if ([self fileURLsInDraggingInfo:sender].count > 0) return NSDragOperationCopy;
    return [super draggingEntered:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    if ([self fileURLsInDraggingInfo:sender].count > 0) {
        // 让插入点跟随鼠标，用户能看到将插在哪一行
        NSPoint p = [self convertPoint:sender.draggingLocation fromView:nil];
        NSUInteger idx = [self characterIndexForInsertionAtPoint:p];
        [self setSelectedRange:NSMakeRange(MIN(idx, self.string.length), 0)];
        return NSDragOperationCopy;
    }
    return [super draggingUpdated:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray<NSURL *> *urls = [self fileURLsInDraggingInfo:sender];
    if (urls.count > 0 && [self.editorDelegate respondsToSelector:@selector(editorTextView:didDropFileURLs:atCharacterIndex:)]) {
        NSPoint p = [self convertPoint:sender.draggingLocation fromView:nil];
        NSUInteger idx = MIN([self characterIndexForInsertionAtPoint:p], self.string.length);
        if ([self.editorDelegate editorTextView:self didDropFileURLs:urls atCharacterIndex:idx]) {
            [self.window makeFirstResponder:self];
            return YES;
        }
    }
    return [super performDragOperation:sender];
}

/// 可撤销地在 location 插入文本并把光标放到 location + cursorOffset。
- (void)insertSnippet:(NSString *)snippet atLocation:(NSUInteger)location cursorOffset:(NSUInteger)cursorOffset {
    NSRange range = NSMakeRange(MIN(location, self.string.length), 0);
    if (![self shouldChangeTextInRange:range replacementString:snippet]) return;
    [self.textStorage replaceCharactersInRange:range withString:snippet];
    [self didChangeText];
    NSUInteger cursor = range.location + MIN(cursorOffset, snippet.length);
    [self setSelectedRange:NSMakeRange(cursor, 0)];
    [self scrollRangeToVisible:NSMakeRange(cursor, 0)];
}

- (void)replaceTextWith:(NSString *)newText actionName:(NSString *)actionName {
    NSString *old = self.string;
    if ([old isEqualToString:newText]) return;
    // 公共前缀 / 后缀之外的中间段才是改动
    NSUInteger prefix = 0, oldLen = old.length, newLen = newText.length;
    while (prefix < oldLen && prefix < newLen && [old characterAtIndex:prefix] == [newText characterAtIndex:prefix]) prefix++;
    NSUInteger suffix = 0;
    while (suffix < oldLen - prefix && suffix < newLen - prefix &&
           [old characterAtIndex:oldLen - 1 - suffix] == [newText characterAtIndex:newLen - 1 - suffix]) suffix++;
    NSRange changed = NSMakeRange(prefix, oldLen - prefix - suffix);
    NSString *replacement = [newText substringWithRange:NSMakeRange(prefix, newLen - prefix - suffix)];

    NSRange sel = self.selectedRange;
    if (![self shouldChangeTextInRange:changed replacementString:replacement]) return;
    [self.textStorage replaceCharactersInRange:changed withString:replacement];
    [self didChangeText];
    [self.undoManager setActionName:actionName];
    // 光标在改动段之后就跟着平移，在之前不动，落在改动段里就放到改动末尾
    NSUInteger cursor = sel.location;
    if (cursor >= NSMaxRange(changed)) cursor = cursor - changed.length + replacement.length;
    else if (cursor > changed.location) cursor = changed.location + replacement.length;
    [self setSelectedRange:NSMakeRange(MIN(cursor, newLen), 0)];
}

- (void)replaceRange:(NSRange)range withText:(NSString *)replacement selection:(NSRange)selection actionName:(NSString *)actionName {
    if (NSMaxRange(range) > self.string.length) return;
    if (![self shouldChangeTextInRange:range replacementString:replacement]) return;
    [self.textStorage replaceCharactersInRange:range withString:replacement];
    [self didChangeText];
    [self.undoManager setActionName:actionName];
    NSUInteger length = self.string.length;
    NSUInteger loc = MIN(selection.location, length);
    [self setSelectedRange:NSMakeRange(loc, MIN(selection.length, length - loc))];
    [self scrollRangeToVisible:self.selectedRange];
}

#pragma mark - 右键菜单

/// 系统的右键菜单后面接上「格式」子菜单（和菜单栏里的是同一组命令）
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSMenu *menu = [super menuForEvent:event];
    NSMenuItem *format = [NSApp.mainMenu itemWithTitle:@"格式"];
    if (menu && format.submenu && self.syntax != TMEditorSyntaxBibTeX && self.syntax != TMEditorSyntaxPlain) {
        [menu insertItem:[NSMenuItem separatorItem] atIndex:0];
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"格式" action:nil keyEquivalent:@""];
        item.submenu = [format.submenu copy];
        [menu insertItem:item atIndex:0];
    }
    return menu;
}

#pragma mark - 光标行列位置更新

- (void)setSelectedRanges:(NSArray<NSValue *> *)selectedRanges affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelecting {
    NSRange previous = self.selectedRange;
    [super setSelectedRanges:selectedRanges affinity:affinity stillSelecting:stillSelecting];

    // 光标左右移出了正在补全的词，就收起补全浮窗（放到下一轮，等文字和选区都更新完）
    if (_completionWanted && !_acceptingCompletion) {
        if (!NSEqualRanges(previous, self.selectedRange)) {
            _completionGeneration++;
            _completionInFlight = NO;
        }
        if (selectedRanges.count != 1 || self.selectedRange.length || stillSelecting) [self dismissCompletion];
        else [self refreshCompletionIfNeeded];
    }

    if (selectedRanges.count > 0) {
        NSRange sel = selectedRanges.firstObject.rangeValue;
        NSString *text = self.string;
        NSUInteger loc = MIN(sel.location, text.length);

        // 旧行与新行都要重画底色
        [self invalidateCurrentLineHighlightForSelection:NSMakeRange(MIN(previous.location, text.length), 0)];
        [self invalidateCurrentLineHighlightForSelection:NSMakeRange(loc, 0)];

        TMLineIndex *index = self.lineIndex;
        NSUInteger line = [index lineNumberForCharacterIndex:loc];
        NSUInteger col = loc - [index startOfLine:line] + 1;

        if ([self.editorDelegate respondsToSelector:@selector(editorTextViewDidChangeCursorPositionToLine:column:)]) {
            [self.editorDelegate editorTextViewDidChangeCursorPositionToLine:line column:col];
        }

        if (sel.length == 0 && !stillSelecting) {
            [self flashMatchingBracketForCursorAt:loc];
        } else {
            [self clearBracketHighlight];
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
