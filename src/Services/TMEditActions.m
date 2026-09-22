#import "TMEditActions.h"

@implementation TMEditActions

/// 将文本拆成行（保留每行的换行符），逐行变换后拼回。
+ (NSString *)mapLines:(NSString *)lines using:(NSString *(^)(NSString *lineWithoutNewline))transform {
    NSMutableString *out = [NSMutableString stringWithCapacity:lines.length + 16];
    NSUInteger loc = 0;
    while (loc < lines.length) {
        NSRange lineRange = [lines lineRangeForRange:NSMakeRange(loc, 0)];
        NSRange contentRange = lineRange;
        NSUInteger contentEnd = 0;
        [lines getLineStart:NULL end:NULL contentsEnd:&contentEnd forRange:lineRange];
        contentRange.length = contentEnd - lineRange.location;

        NSString *content = [lines substringWithRange:contentRange];
        NSString *newline = [lines substringWithRange:NSMakeRange(contentEnd, NSMaxRange(lineRange) - contentEnd)];
        [out appendString:transform(content)];
        [out appendString:newline];
        loc = NSMaxRange(lineRange);
    }
    return out;
}

+ (BOOL)isBlankLine:(NSString *)line {
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0;
}

+ (NSString *)toggledCommentForLines:(NSString *)lines {
    // 先判断是否全部非空行都已注释
    __block BOOL allCommented = YES;
    __block BOOL anyNonBlank = NO;
    [self mapLines:lines using:^NSString *(NSString *line) {
        if (![self isBlankLine:line]) {
            anyNonBlank = YES;
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (![trimmed hasPrefix:@"%"]) allCommented = NO;
        }
        return line;
    }];

    if (anyNonBlank && allCommented) {
        return [self mapLines:lines using:^NSString *(NSString *line) {
            if ([self isBlankLine:line]) return line;
            NSString *ws = [self leadingWhitespaceOfLine:line];
            NSString *rest = [line substringFromIndex:ws.length]; // 以 % 开头
            rest = [rest substringFromIndex:1];
            if ([rest hasPrefix:@" "]) rest = [rest substringFromIndex:1];
            return [ws stringByAppendingString:rest];
        }];
    }

    return [self mapLines:lines using:^NSString *(NSString *line) {
        if ([self isBlankLine:line]) return line;
        return [@"% " stringByAppendingString:line];
    }];
}

+ (NSString *)indentedLines:(NSString *)lines indent:(NSString *)indent {
    return [self mapLines:lines using:^NSString *(NSString *line) {
        if ([self isBlankLine:line]) return line;
        return [indent stringByAppendingString:line];
    }];
}

+ (NSString *)outdentedLines:(NSString *)lines width:(NSUInteger)width {
    return [self mapLines:lines using:^NSString *(NSString *line) {
        if (line.length == 0) return line;
        if ([line characterAtIndex:0] == '\t') return [line substringFromIndex:1];
        NSUInteger removed = 0;
        while (removed < width && removed < line.length && [line characterAtIndex:removed] == ' ') {
            removed++;
        }
        return [line substringFromIndex:removed];
    }];
}

+ (nullable NSString *)environmentToCloseInLine:(NSString *)line {
    static NSRegularExpression *beginRegex;
    static NSRegularExpression *commentRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        beginRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\begin\\{([^}]+)\\}" options:0 error:nil];
        commentRegex = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\\\)%" options:0 error:nil];
    });

    // 截掉注释部分
    NSRange searchRange = NSMakeRange(0, line.length);
    NSTextCheckingResult *comment = [commentRegex firstMatchInString:line options:0 range:searchRange];
    if (comment) searchRange.length = comment.range.location;

    NSArray<NSTextCheckingResult *> *begins = [beginRegex matchesInString:line options:0 range:searchRange];
    // 取最后一个未闭合的 \begin
    for (NSTextCheckingResult *m in begins.reverseObjectEnumerator) {
        NSString *env = [line substringWithRange:[m rangeAtIndex:1]];
        NSString *endToken = [NSString stringWithFormat:@"\\end{%@}", env];
        NSRange after = NSMakeRange(NSMaxRange(m.range), NSMaxRange(searchRange) - NSMaxRange(m.range));
        if ([line rangeOfString:endToken options:0 range:after].location == NSNotFound) {
            return env;
        }
    }
    return nil;
}

+ (NSString *)leadingWhitespaceOfLine:(NSString *)line {
    NSUInteger i = 0;
    while (i < line.length) {
        unichar c = [line characterAtIndex:i];
        if (c != ' ' && c != '\t') break;
        i++;
    }
    return [line substringToIndex:i];
}

@end
