#import "TMFormatActions.h"

@implementation TMFormatEdit

+ (instancetype)editWithRange:(NSRange)range replacement:(NSString *)replacement selection:(NSRange)selection {
    TMFormatEdit *edit = [[TMFormatEdit alloc] init];
    edit.range = range;
    edit.replacement = replacement;
    edit.selection = selection;
    return edit;
}

@end

#pragma mark - 一行 LaTeX 的结构

/// 缩进 + 可选的 \item + 可选的标题命令 + 正文。标题只认同一行里括号配对的写法。
@interface TMLaTeXLine : NSObject
@property (nonatomic, copy) NSString *indent;
@property (nonatomic, copy) NSString *itemPrefix;      // "\item " 或 ""
@property (nonatomic, copy, nullable) NSString *headingCommand;
@property (nonatomic, assign) BOOL starred;
@property (nonatomic, copy) NSString *content;         // 标题花括号里的文字，或 \item 之后的正文
@property (nonatomic, copy) NSString *trailing;        // 标题 } 之后的内容（常见的是 \label{…}）
@property (nonatomic, assign) NSUInteger contentOffset; // content 在行内的起点
@end

@implementation TMLaTeXLine
@end

static BOOL TMIsASCIILetter(unichar c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

/// open 处的 { 配对的 } 位置（跳过 \{ \}），到 limit 为止都没找到返回 NSNotFound
static NSUInteger TMMatchBrace(NSString *s, NSUInteger open, NSUInteger limit) {
    NSInteger depth = 0;
    for (NSUInteger i = open; i < limit; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '\\') { i++; continue; }
        if (c == '{') depth++;
        else if (c == '}' && --depth == 0) return i;
    }
    return NSNotFound;
}

static NSSet<NSString *> *TMHeadingCommandNames(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithArray:@[@"part", @"chapter", @"section", @"subsection", @"subsubsection", @"paragraph"]]; });
    return set;
}

static TMLaTeXLine *TMParseLaTeXLine(NSString *line) {
    TMLaTeXLine *info = [[TMLaTeXLine alloc] init];
    NSUInteger n = line.length, i = 0;
    while (i < n && ([line characterAtIndex:i] == ' ' || [line characterAtIndex:i] == '\t')) i++;
    info.indent = [line substringToIndex:i];
    info.itemPrefix = @"";
    info.trailing = @"";

    if ([[line substringFromIndex:i] hasPrefix:@"\\item"] && (i + 5 >= n || !TMIsASCIILetter([line characterAtIndex:i + 5]))) {
        NSUInteger j = i + 5;
        if (j < n && [line characterAtIndex:j] == '[') {
            NSRange close = [line rangeOfString:@"]" options:0 range:NSMakeRange(j, n - j)];
            if (close.location != NSNotFound) j = NSMaxRange(close);
        }
        while (j < n && [line characterAtIndex:j] == ' ') j++;
        info.itemPrefix = [line substringWithRange:NSMakeRange(i, j - i)];
        i = j;
    }

    if (i < n && [line characterAtIndex:i] == '\\') {
        NSUInteger j = i + 1;
        while (j < n && TMIsASCIILetter([line characterAtIndex:j])) j++;
        NSString *name = [line substringWithRange:NSMakeRange(i + 1, j - i - 1)];
        if ([TMHeadingCommandNames() containsObject:name]) {
            BOOL starred = j < n && [line characterAtIndex:j] == '*';
            if (starred) j++;
            while (j < n && [line characterAtIndex:j] == ' ') j++;
            if (j < n && [line characterAtIndex:j] == '[') {
                NSRange close = [line rangeOfString:@"]" options:0 range:NSMakeRange(j, n - j)];
                j = close.location == NSNotFound ? n : NSMaxRange(close);
                while (j < n && [line characterAtIndex:j] == ' ') j++;
            }
            NSUInteger close = (j < n && [line characterAtIndex:j] == '{') ? TMMatchBrace(line, j, n) : NSNotFound;
            if (close != NSNotFound) {
                info.headingCommand = name;
                info.starred = starred;
                info.content = [line substringWithRange:NSMakeRange(j + 1, close - j - 1)];
                info.trailing = [line substringFromIndex:close + 1];
                info.contentOffset = j + 1;
                return info;
            }
        }
    }
    info.content = [line substringFromIndex:i];
    info.contentOffset = i;
    return info;
}

@implementation TMFormatActions

#pragma mark - 名称与标题层级

+ (NSString *)displayNameForParagraphStyle:(TMParagraphStyle)style {
    switch (style) {
        case TMParagraphStyleBody: return @"正文";
        case TMParagraphStyleHeading1: return @"标题 1";
        case TMParagraphStyleHeading2: return @"标题 2";
        case TMParagraphStyleHeading3: return @"标题 3";
        case TMParagraphStyleHeading4: return @"标题 4";
        case TMParagraphStyleBulletList: return @"无序列表";
        case TMParagraphStyleNumberedList: return @"有序列表";
        case TMParagraphStyleQuote: return @"引用";
    }
    return @"正文";
}

+ (BOOL)usesChaptersForMainContent:(nullable NSString *)mainContent currentContent:(NSString *)currentContent {
    static NSRegularExpression *classRegex, *chapterRegex;
    static NSSet *chapterClasses;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        classRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*\\\\documentclass(?:\\[[^\\]]*\\])?\\{([^}]+)\\}"
                                                               options:NSRegularExpressionAnchorsMatchLines error:nil];
        chapterRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*\\\\chapter\\*?\\s*[\\[{]"
                                                                 options:NSRegularExpressionAnchorsMatchLines error:nil];
        chapterClasses = [NSSet setWithArray:@[@"book", @"report", @"ctexbook", @"ctexrep", @"memoir", @"scrbook", @"scrreprt", @"elegantbook"]];
    });
    NSString *main = mainContent ?: currentContent;
    NSTextCheckingResult *m = [classRegex firstMatchInString:main options:0 range:NSMakeRange(0, main.length)];
    if (m) {
        NSString *cls = [[main substringWithRange:[m rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // 学位论文模板（thuthesis、ustcthesis …）都按章组织
        if ([chapterClasses containsObject:cls] || [cls.lowercaseString containsString:@"thesis"]) return YES;
    }
    for (NSString *s in @[main, currentContent]) {
        if ([chapterRegex firstMatchInString:s options:0 range:NSMakeRange(0, s.length)]) return YES;
    }
    return NO;
}

+ (NSArray<NSString *> *)headingCommandsUsingChapters:(BOOL)chapters {
    return chapters ? @[@"chapter", @"section", @"subsection", @"subsubsection"]
                    : @[@"section", @"subsection", @"subsubsection", @"paragraph"];
}

+ (TMParagraphStyle)headingStyleForCommand:(NSString *)command usesChapters:(BOOL)chapters {
    NSUInteger idx = [[self headingCommandsUsingChapters:chapters] indexOfObject:command];
    if (idx != NSNotFound) return TMParagraphStyleHeading1 + (TMParagraphStyle)idx;
    return [command isEqualToString:@"paragraph"] ? TMParagraphStyleHeading4 : TMParagraphStyleHeading1; // part / 文章类里的 chapter
}

static BOOL TMIsHeading(TMParagraphStyle style) {
    return style >= TMParagraphStyleHeading1 && style <= TMParagraphStyleHeading4;
}

#pragma mark - 所在环境

/// 光标外层最近的 names 之一的环境：返回名字，并给出 \begin 行和 \end 行的范围。只看前后 5 万字。
+ (nullable NSString *)enclosingEnvironment:(NSSet<NSString *> *)names inText:(NSString *)text location:(NSUInteger)loc
                                  beginLine:(NSRange *)beginLine endLine:(NSRange *)endLine {
    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(begin|end)\\{([A-Za-z*]+)\\}" options:0 error:nil];
    });
    NSUInteger windowStart = loc > 50000 ? loc - 50000 : 0;
    NSUInteger windowEnd = MIN(text.length, loc + 50000);
    NSMutableArray<NSTextCheckingResult *> *matches = [NSMutableArray array];
    [regex enumerateMatchesInString:text options:0 range:NSMakeRange(windowStart, windowEnd - windowStart)
                         usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        if (![names containsObject:[text substringWithRange:[m rangeAtIndex:2]]]) return;
        // 注释掉的不算
        NSRange line = [text lineRangeForRange:NSMakeRange(m.range.location, 0)];
        NSString *before = [text substringWithRange:NSMakeRange(line.location, m.range.location - line.location)];
        NSRange pct = [before rangeOfString:@"%"];
        if (pct.location != NSNotFound && (pct.location == 0 || [before characterAtIndex:pct.location - 1] != '\\')) return;
        [matches addObject:m];
    }];

    NSInteger depth = 0;
    NSInteger found = -1;
    for (NSInteger k = (NSInteger)matches.count - 1; k >= 0; k--) {
        NSTextCheckingResult *m = matches[(NSUInteger)k];
        if (NSMaxRange(m.range) > loc) continue;
        BOOL isEnd = [[text substringWithRange:[m rangeAtIndex:1]] isEqualToString:@"end"];
        if (isEnd) { depth++; continue; }
        if (depth == 0) { found = k; break; }
        depth--;
    }
    if (found < 0) return nil;

    NSString *name = [text substringWithRange:[matches[(NSUInteger)found] rangeAtIndex:2]];
    depth = 0;
    for (NSUInteger k = (NSUInteger)found + 1; k < matches.count; k++) {
        NSTextCheckingResult *m = matches[k];
        if (![[text substringWithRange:[m rangeAtIndex:2]] isEqualToString:name]) continue;
        BOOL isEnd = [[text substringWithRange:[m rangeAtIndex:1]] isEqualToString:@"end"];
        if (!isEnd) { depth++; continue; }
        if (depth > 0) { depth--; continue; }
        if (m.range.location < loc) return nil; // \end 在光标之前：光标不在里面
        if (beginLine) *beginLine = [text lineRangeForRange:NSMakeRange(matches[(NSUInteger)found].range.location, 0)];
        if (endLine) *endLine = [text lineRangeForRange:NSMakeRange(m.range.location, 0)];
        return name;
    }
    return nil;
}

+ (NSSet<NSString *> *)listEnvironments {
    return [NSSet setWithArray:@[@"itemize", @"enumerate", @"description"]];
}

+ (NSSet<NSString *> *)quoteEnvironments {
    return [NSSet setWithArray:@[@"quote", @"quotation"]];
}

/// 行的范围（不含换行符）
static NSRange TMLineContentRange(NSString *text, NSUInteger loc) {
    NSUInteger start = 0, contentsEnd = 0;
    [text getLineStart:&start end:NULL contentsEnd:&contentsEnd forRange:NSMakeRange(MIN(loc, text.length), 0)];
    return NSMakeRange(start, contentsEnd - start);
}

static BOOL TMIsBlank(NSString *s) {
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0;
}

#pragma mark - 段落样式

+ (TMParagraphStyle)paragraphStyleAtLocation:(NSUInteger)location inText:(NSString *)text
                                    markdown:(BOOL)markdown usesChapters:(BOOL)usesChapters {
    NSString *line = [text substringWithRange:TMLineContentRange(text, location)];
    if (markdown) return [self markdownStyleOfLine:line];

    TMLaTeXLine *info = TMParseLaTeXLine(line);
    if (info.headingCommand) return [self headingStyleForCommand:info.headingCommand usesChapters:usesChapters];
    NSString *list = [self enclosingEnvironment:[self listEnvironments] inText:text location:location beginLine:NULL endLine:NULL];
    if (list) return [list isEqualToString:@"enumerate"] ? TMParagraphStyleNumberedList : TMParagraphStyleBulletList;
    if ([self enclosingEnvironment:[self quoteEnvironments] inText:text location:location beginLine:NULL endLine:NULL]) return TMParagraphStyleQuote;
    return TMParagraphStyleBody;
}

+ (nullable TMFormatEdit *)editForParagraphStyle:(TMParagraphStyle)style selection:(NSRange)selection inText:(NSString *)text
                                        markdown:(BOOL)markdown usesChapters:(BOOL)usesChapters {
    if (NSMaxRange(selection) > text.length) return nil;
    TMParagraphStyle current = [self paragraphStyleAtLocation:selection.location inText:text markdown:markdown usesChapters:usesChapters];
    BOOL togglesItself = !markdown && (style == TMParagraphStyleBulletList || style == TMParagraphStyleNumberedList || style == TMParagraphStyleQuote);
    if (style == current && !togglesItself) {
        if (style == TMParagraphStyleBody) return nil;
        style = TMParagraphStyleBody; // 再按一次取消
    }
    if (markdown) return [self markdownEditForStyle:style selection:selection inText:text];

    if (style == TMParagraphStyleBulletList || style == TMParagraphStyleNumberedList) {
        return [self listEditForStyle:style selection:selection inText:text];
    }
    if (style == TMParagraphStyleQuote) return [self quoteEditForSelection:selection inText:text];

    // 标题 / 正文：只改光标所在的一行
    NSRange lineRange = TMLineContentRange(text, selection.location);
    TMLaTeXLine *info = TMParseLaTeXLine([text substringWithRange:lineRange]);
    NSUInteger caretInContent = selection.location >= lineRange.location + info.contentOffset
        ? MIN(selection.location - lineRange.location - info.contentOffset, info.content.length) : 0;

    NSString *body;
    NSUInteger bodyCaret;
    if (TMIsHeading(style)) {
        NSString *command = [self headingCommandsUsingChapters:usesChapters][(NSUInteger)(style - TMParagraphStyleHeading1)];
        NSString *open = [NSString stringWithFormat:@"\\%@%@{", command, info.starred ? @"*" : @""];
        body = [NSString stringWithFormat:@"%@%@}%@", open, info.content, info.trailing];
        bodyCaret = open.length + caretInContent;
    } else {
        body = [info.content stringByAppendingString:info.trailing];
        bodyCaret = caretInContent;
    }

    // 列表里的一项改成标题 / 正文：把它从列表里拿出来
    if (current == TMParagraphStyleBulletList || current == TMParagraphStyleNumberedList) {
        NSRange beginLine, endLine;
        if ([self enclosingEnvironment:[self listEnvironments] inText:text location:selection.location beginLine:&beginLine endLine:&endLine]) {
            return [self editExtractingLine:[text lineRangeForRange:lineRange] asText:body caret:bodyCaret
                          fromEnvironmentBegin:beginLine end:endLine inText:text];
        }
    }
    // 引用里的一段改成正文：去掉整个引用
    if (current == TMParagraphStyleQuote && style == TMParagraphStyleBody) {
        return [self quoteEditForSelection:selection inText:text];
    }

    NSString *prefix = [info.indent stringByAppendingString:info.itemPrefix];
    NSString *newLine = [prefix stringByAppendingString:body];
    return [TMFormatEdit editWithRange:lineRange replacement:newLine
                             selection:NSMakeRange(lineRange.location + prefix.length + bodyCaret, 0)];
}

/// 把环境里的一行拿出来变成独立段落：前后还有别的项就把环境拆成两段，空行隔开
+ (TMFormatEdit *)editExtractingLine:(NSRange)line asText:(NSString *)newText caret:(NSUInteger)caret
                fromEnvironmentBegin:(NSRange)beginLine end:(NSRange)endLine inText:(NSString *)text {
    NSString *beginText = [text substringWithRange:beginLine];
    if (![beginText hasSuffix:@"\n"]) beginText = [beginText stringByAppendingString:@"\n"];
    NSString *endText = [text substringWithRange:endLine];
    if (![endText hasSuffix:@"\n"]) endText = [endText stringByAppendingString:@"\n"];
    NSString *before = [text substringWithRange:NSMakeRange(NSMaxRange(beginLine), line.location - NSMaxRange(beginLine))];
    NSString *after = [text substringWithRange:NSMakeRange(NSMaxRange(line), endLine.location - NSMaxRange(line))];

    NSMutableString *out = [NSMutableString string];
    if (!TMIsBlank(before)) [out appendFormat:@"%@%@%@\n", beginText, before, endText];
    NSUInteger caretLocation = beginLine.location + out.length + caret;
    [out appendFormat:@"%@\n", newText];
    if (!TMIsBlank(after)) [out appendFormat:@"\n%@%@%@", beginText, after, endText];
    return [TMFormatEdit editWithRange:NSMakeRange(beginLine.location, NSMaxRange(endLine) - beginLine.location)
                           replacement:out selection:NSMakeRange(caretLocation, 0)];
}

+ (TMFormatEdit *)listEditForStyle:(TMParagraphStyle)style selection:(NSRange)selection inText:(NSString *)text {
    NSString *envName = style == TMParagraphStyleNumberedList ? @"enumerate" : @"itemize";
    NSRange beginLine, endLine;
    NSString *existing = [self enclosingEnvironment:[self listEnvironments] inText:text location:selection.location beginLine:&beginLine endLine:&endLine];
    if (existing) {
        NSRange envRange = NSMakeRange(beginLine.location, NSMaxRange(endLine) - beginLine.location);
        if (![existing isEqualToString:envName]) {
            // 无序 ↔ 有序：只改环境名
            NSMutableString *env = [[text substringWithRange:envRange] mutableCopy];
            NSString *oldBegin = [NSString stringWithFormat:@"\\begin{%@}", existing];
            NSString *oldEnd = [NSString stringWithFormat:@"\\end{%@}", existing];
            NSRange b = [env rangeOfString:oldBegin];
            [env replaceCharactersInRange:b withString:[NSString stringWithFormat:@"\\begin{%@}", envName]];
            NSRange e = [env rangeOfString:oldEnd options:NSBackwardsSearch];
            [env replaceCharactersInRange:e withString:[NSString stringWithFormat:@"\\end{%@}", envName]];
            NSInteger delta = (NSInteger)envName.length - (NSInteger)existing.length;
            NSUInteger caret = selection.location >= NSMaxRange(beginLine) ? selection.location + delta : selection.location;
            return [TMFormatEdit editWithRange:envRange replacement:env selection:NSMakeRange(caret, 0)];
        }
        // 同一种列表再按一次：整个列表变回段落
        NSString *inner = [text substringWithRange:NSMakeRange(NSMaxRange(beginLine), endLine.location - NSMaxRange(beginLine))];
        NSMutableArray<NSString *> *paragraphs = [NSMutableArray array];
        for (NSString *line in [inner componentsSeparatedByString:@"\n"]) {
            if (TMIsBlank(line)) continue;
            TMLaTeXLine *info = TMParseLaTeXLine(line);
            NSString *body = info.headingCommand ? line : [info.content copy];
            [paragraphs addObject:[body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        }
        NSString *out = [[paragraphs componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n"];
        return [TMFormatEdit editWithRange:envRange replacement:out selection:NSMakeRange(envRange.location, 0)];
    }

    // 选中的各行变成列表项
    NSRange lines = [text lineRangeForRange:selection];
    NSString *block = [text substringWithRange:lines];
    NSString *indent = TMParseLaTeXLine(block).indent;
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *line in [block componentsSeparatedByString:@"\n"]) {
        if (TMIsBlank(line)) continue;
        TMLaTeXLine *info = TMParseLaTeXLine(line);
        NSString *body = info.headingCommand ? [info.content stringByAppendingString:info.trailing] : info.content;
        [items addObject:[NSString stringWithFormat:@"%@  \\item %@", indent, body]];
    }
    if (items.count == 0) [items addObject:[indent stringByAppendingString:@"  \\item "]];
    NSString *head = [NSString stringWithFormat:@"%@\\begin{%@}\n", indent, envName];
    NSString *out = [NSString stringWithFormat:@"%@%@\n%@\\end{%@}\n", head, [items componentsJoinedByString:@"\n"], indent, envName];
    NSUInteger caret = lines.location + head.length + items.firstObject.length;
    if (items.count > 1) caret = lines.location + out.length - indent.length - envName.length - 8; // 最后一项末尾（去掉 "\n" 缩进 "\end{…}\n"）
    return [TMFormatEdit editWithRange:lines replacement:out selection:NSMakeRange(caret, 0)];
}

+ (TMFormatEdit *)quoteEditForSelection:(NSRange)selection inText:(NSString *)text {
    NSRange beginLine, endLine;
    if ([self enclosingEnvironment:[self quoteEnvironments] inText:text location:selection.location beginLine:&beginLine endLine:&endLine]) {
        NSRange envRange = NSMakeRange(beginLine.location, NSMaxRange(endLine) - beginLine.location);
        NSString *inner = [text substringWithRange:NSMakeRange(NSMaxRange(beginLine), endLine.location - NSMaxRange(beginLine))];
        NSUInteger caret = selection.location >= NSMaxRange(beginLine) ? selection.location - beginLine.length : beginLine.location;
        return [TMFormatEdit editWithRange:envRange replacement:inner selection:NSMakeRange(MIN(caret, beginLine.location + inner.length), 0)];
    }
    NSRange lines = [text lineRangeForRange:selection];
    NSString *block = [text substringWithRange:lines];
    if (![block hasSuffix:@"\n"]) block = [block stringByAppendingString:@"\n"];
    NSString *indent = TMParseLaTeXLine(block).indent;
    NSString *head = [NSString stringWithFormat:@"%@\\begin{quote}\n", indent];
    NSString *out = [NSString stringWithFormat:@"%@%@%@\\end{quote}\n", head, block, indent];
    return [TMFormatEdit editWithRange:lines replacement:out selection:NSMakeRange(selection.location + head.length, 0)];
}

#pragma mark - Markdown 段落样式

+ (NSRegularExpression *)markdownPrefixRegex {
    static NSRegularExpression *regex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*(#{1,6}[ \\t]+|[-*+][ \\t]+|[0-9]+[.)][ \\t]+|>[ \\t]?)?" options:0 error:nil];
    });
    return regex;
}

+ (TMParagraphStyle)markdownStyleOfLine:(NSString *)line {
    NSTextCheckingResult *m = [[self markdownPrefixRegex] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    NSRange p = [m rangeAtIndex:1];
    if (p.location == NSNotFound) return TMParagraphStyleBody;
    unichar c = [line characterAtIndex:p.location];
    if (c == '#') {
        NSUInteger level = 0;
        while (p.location + level < line.length && [line characterAtIndex:p.location + level] == '#') level++;
        return level >= 4 ? TMParagraphStyleHeading4 : TMParagraphStyleHeading1 + (TMParagraphStyle)(level - 1);
    }
    if (c == '>') return TMParagraphStyleQuote;
    if (c >= '0' && c <= '9') return TMParagraphStyleNumberedList;
    return TMParagraphStyleBulletList;
}

+ (TMFormatEdit *)markdownEditForStyle:(TMParagraphStyle)style selection:(NSRange)selection inText:(NSString *)text {
    NSRange lines = TMLineContentRange(text, selection.location);
    if (selection.length > 0) {
        NSRange last = TMLineContentRange(text, NSMaxRange(selection) - 1);
        lines = NSUnionRange(lines, last);
    }
    NSArray<NSString *> *parts = [[text substringWithRange:lines] componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSUInteger number = 1;
    NSInteger firstDelta = 0;
    for (NSUInteger k = 0; k < parts.count; k++) {
        NSString *line = parts[k];
        NSTextCheckingResult *m = [[self markdownPrefixRegex] firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        NSString *rest = [line substringFromIndex:NSMaxRange(m.range)];
        NSString *prefix = @"";
        if (!(TMIsBlank(line) && parts.count > 1)) {
            switch (style) {
                case TMParagraphStyleHeading1: prefix = @"# "; break;
                case TMParagraphStyleHeading2: prefix = @"## "; break;
                case TMParagraphStyleHeading3: prefix = @"### "; break;
                case TMParagraphStyleHeading4: prefix = @"#### "; break;
                case TMParagraphStyleBulletList: prefix = @"- "; break;
                case TMParagraphStyleNumberedList: prefix = [NSString stringWithFormat:@"%lu. ", (unsigned long)number++]; break;
                case TMParagraphStyleQuote: prefix = @"> "; break;
                case TMParagraphStyleBody: break;
            }
        }
        if (k == 0) firstDelta = (NSInteger)prefix.length - (NSInteger)m.range.length;
        [out addObject:[prefix stringByAppendingString:rest]];
    }
    NSString *replacement = [out componentsJoinedByString:@"\n"];
    NSRange sel;
    if (parts.count > 1) {
        sel = NSMakeRange(lines.location, replacement.length);
    } else {
        NSInteger caret = (NSInteger)selection.location + firstDelta;
        caret = MAX((NSInteger)lines.location, MIN(caret, (NSInteger)(lines.location + replacement.length)));
        sel = NSMakeRange((NSUInteger)caret, 0);
    }
    return [TMFormatEdit editWithRange:lines replacement:replacement selection:sel];
}

#pragma mark - 文字样式

+ (TMFormatEdit *)editForInlineStyle:(TMInlineStyle)style selection:(NSRange)selection inText:(NSString *)text markdown:(BOOL)markdown {
    NSArray<NSString *> *opens;
    NSString *close;
    if (markdown) {
        switch (style) {
            case TMInlineStyleBold: opens = @[@"**"]; close = @"**"; break;
            case TMInlineStyleItalic: opens = @[@"*"]; close = @"*"; break;
            case TMInlineStyleUnderline: opens = @[@"<u>"]; close = @"</u>"; break;
        }
    } else {
        switch (style) {
            case TMInlineStyleBold: opens = @[@"\\textbf{"]; break;
            case TMInlineStyleItalic: opens = @[@"\\textit{", @"\\emph{"]; break;
            case TMInlineStyleUnderline: opens = @[@"\\underline{"]; break;
        }
        close = @"}";
    }

    if (selection.length > 0) {
        NSString *selected = [text substringWithRange:selection];
        for (NSString *open in opens) {
            // 选中的就是 \textbf{…} 整体
            if ([selected hasPrefix:open] && [selected hasSuffix:close] && selected.length >= open.length + close.length &&
                (markdown || TMMatchBrace(selected, open.length - 1, selected.length) == selected.length - 1)) {
                NSString *inner = [selected substringWithRange:NSMakeRange(open.length, selected.length - open.length - close.length)];
                return [TMFormatEdit editWithRange:selection replacement:inner selection:NSMakeRange(selection.location, inner.length)];
            }
            // 选中的是 \textbf{…} 里面的全部文字
            if (selection.location >= open.length &&
                [[text substringWithRange:NSMakeRange(selection.location - open.length, open.length)] isEqualToString:open] &&
                [[text substringFromIndex:NSMaxRange(selection)] hasPrefix:close] &&
                (markdown || TMMatchBrace(text, selection.location - 1, text.length) == NSMaxRange(selection))) {
                NSRange whole = NSMakeRange(selection.location - open.length, selection.length + open.length + close.length);
                return [TMFormatEdit editWithRange:whole replacement:selected selection:NSMakeRange(whole.location, selected.length)];
            }
        }
        NSString *wrapped = [NSString stringWithFormat:@"%@%@%@", opens.firstObject, selected, close];
        return [TMFormatEdit editWithRange:selection replacement:wrapped
                                 selection:NSMakeRange(selection.location + opens.firstObject.length, selected.length)];
    }

    if (!markdown) {
        // 光标在同一行的 \textbf{…} 里：去掉这层样式
        NSRange line = TMLineContentRange(text, selection.location);
        NSUInteger lineEnd = NSMaxRange(line);
        for (NSString *open in opens) {
            NSRange search = NSMakeRange(line.location, selection.location - line.location);
            while (search.length > 0) {
                NSRange hit = [text rangeOfString:open options:NSBackwardsSearch range:search];
                if (hit.location == NSNotFound) break;
                NSUInteger closeAt = TMMatchBrace(text, NSMaxRange(hit) - 1, lineEnd);
                if (closeAt != NSNotFound && closeAt >= selection.location) {
                    NSString *inner = [text substringWithRange:NSMakeRange(NSMaxRange(hit), closeAt - NSMaxRange(hit))];
                    NSUInteger caret = selection.location >= NSMaxRange(hit) ? selection.location - open.length : hit.location;
                    return [TMFormatEdit editWithRange:NSMakeRange(hit.location, closeAt + 1 - hit.location)
                                           replacement:inner selection:NSMakeRange(caret, 0)];
                }
                search.length = hit.location - search.location;
            }
        }
    }
    NSString *pair = [opens.firstObject stringByAppendingString:close];
    return [TMFormatEdit editWithRange:selection replacement:pair selection:NSMakeRange(selection.location + opens.firstObject.length, 0)];
}

#pragma mark - 插入

+ (TMFormatEdit *)editForInsertion:(TMFormatInsertion)kind selection:(NSRange)selection inText:(NSString *)text markdown:(BOOL)markdown {
    NSString *selected = [text substringWithRange:selection];
    switch (kind) {
        case TMFormatInsertInlineMath:
            return [self wrap:selected in:selection open:@"$" close:@"$"];
        case TMFormatInsertFootnote:
            return markdown ? [self wrap:selected in:selection open:@"^[" close:@"]"]
                            : [self wrap:selected in:selection open:@"\\footnote{" close:@"}"];
        case TMFormatInsertLink: {
            NSString *head = markdown ? [NSString stringWithFormat:@"[%@](", selected] : @"\\href{";
            NSString *url = @"https://";
            NSString *tail = markdown ? @")" : [NSString stringWithFormat:@"}{%@}", selected];
            TMFormatEdit *edit = [TMFormatEdit editWithRange:selection replacement:[NSString stringWithFormat:@"%@%@%@", head, url, tail]
                                                   selection:NSMakeRange(selection.location + head.length, url.length)];
            if (!markdown) edit.requiredPackage = @"hyperref";
            return edit;
        }
        case TMFormatInsertDisplayMath: {
            NSString *head = markdown ? @"$$\n" : @"\\begin{equation}\n  ";
            NSString *tail = markdown ? @"\n$$\n" : @"\n\\end{equation}\n";
            return [self block:[NSString stringWithFormat:@"%@%@%@", head, selected, tail]
                         caret:head.length + selected.length selection:selection inText:text];
        }
        case TMFormatInsertTable: {
            if (markdown) {
                NSString *table = @"| 列 1 | 列 2 | 列 3 |\n| --- | --- | --- |\n|  |  |  |\n";
                TMFormatEdit *edit = [self block:table caret:2 selection:selection inText:text];
                edit.selection = NSMakeRange(edit.selection.location, 3); // 选中“列 1”，直接改
                return edit;
            }
            NSString *head = @"\\begin{table}[htbp]\n  \\centering\n  \\caption{";
            NSString *tail = @"}\n  \\label{tab:}\n  \\begin{tabular}{lll}\n    \\hline\n    列 1 & 列 2 & 列 3 \\\\\n    \\hline\n"
                             @"     &  &  \\\\\n    \\hline\n  \\end{tabular}\n\\end{table}\n";
            return [self block:[NSString stringWithFormat:@"%@%@%@", head, selected, tail]
                         caret:head.length + selected.length selection:selection inText:text];
        }
    }
    return [self wrap:selected in:selection open:@"" close:@""];
}

+ (TMFormatEdit *)wrap:(NSString *)selected in:(NSRange)selection open:(NSString *)open close:(NSString *)close {
    NSString *out = [NSString stringWithFormat:@"%@%@%@", open, selected, close];
    NSRange sel = selected.length ? NSMakeRange(selection.location + open.length, selected.length)
                                  : NSMakeRange(selection.location + open.length, 0);
    return [TMFormatEdit editWithRange:selection replacement:out selection:sel];
}

/// 块级内容独占几行：空行上直接替换；否则插在当前行（或选区）之后
+ (TMFormatEdit *)block:(NSString *)block caret:(NSUInteger)caret selection:(NSRange)selection inText:(NSString *)text {
    if (selection.length > 0) {
        NSRange lines = [text lineRangeForRange:selection];
        NSString *before = [text substringWithRange:NSMakeRange(lines.location, selection.location - lines.location)];
        NSString *prefix = TMIsBlank(before) ? @"" : @"\n";
        NSString *out = [prefix stringByAppendingString:block];
        NSUInteger end = NSMaxRange(selection);
        // 选区后面同一行还有内容：块后面自带的换行保留；选区刚好到行尾：吃掉原来的换行，避免多出空行
        if (end < text.length && [text characterAtIndex:end] == '\n') end++;
        return [TMFormatEdit editWithRange:NSMakeRange(selection.location, end - selection.location) replacement:out
                                 selection:NSMakeRange(selection.location + prefix.length + caret, 0)];
    }
    NSRange line = TMLineContentRange(text, selection.location);
    if (TMIsBlank([text substringWithRange:line])) {
        NSString *out = [block hasSuffix:@"\n"] ? [block substringToIndex:block.length - 1] : block;
        return [TMFormatEdit editWithRange:line replacement:out selection:NSMakeRange(line.location + caret, 0)];
    }
    NSRange full = [text lineRangeForRange:NSMakeRange(selection.location, 0)];
    BOOL endsWithNewline = NSMaxRange(full) > full.location && [text characterAtIndex:NSMaxRange(full) - 1] == '\n';
    NSString *prefix = endsWithNewline ? @"" : @"\n";
    NSString *out = [prefix stringByAppendingString:block];
    return [TMFormatEdit editWithRange:NSMakeRange(NSMaxRange(full), 0) replacement:out
                             selection:NSMakeRange(NSMaxRange(full) + prefix.length + caret, 0)];
}

#pragma mark - 宏包

+ (NSUInteger)usepackageInsertionLocationForPackage:(NSString *)package inContent:(NSString *)content {
    NSString *escaped = [NSRegularExpression escapedPatternForString:package];
    NSString *pattern = [NSString stringWithFormat:@"^[ \\t]*\\\\(?:usepackage|RequirePackage)(?:\\[[^\\]]*\\])?\\{[^}]*\\b%@\\b[^}]*\\}", escaped];
    NSRegularExpression *loaded = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:nil];
    NSRange all = NSMakeRange(0, content.length);
    if ([loaded firstMatchInString:content options:0 range:all]) return NSNotFound;

    static NSRegularExpression *documentclassRegex, *beginDocumentRegex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        documentclassRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*\\\\documentclass(?:\\[[^\\]]*\\])?\\{[^}]*\\}[^\\n]*\\n?"
                                                                       options:NSRegularExpressionAnchorsMatchLines error:nil];
        beginDocumentRegex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*\\\\begin\\{document\\}"
                                                                       options:NSRegularExpressionAnchorsMatchLines error:nil];
    });
    NSTextCheckingResult *dc = [documentclassRegex firstMatchInString:content options:0 range:all];
    if (!dc) return NSNotFound;
    if ([package isEqualToString:@"hyperref"]) {
        NSTextCheckingResult *bd = [beginDocumentRegex firstMatchInString:content options:0 range:all];
        if (bd) return bd.range.location;
    }
    return NSMaxRange(dc.range);
}

@end
