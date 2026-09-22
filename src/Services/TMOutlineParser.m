#import "TMOutlineParser.h"

@implementation TMOutlineParser

+ (NSArray<TMOutlineItem *> *)parseOutlineFromLaTeXString:(NSString *)latexString
                                                 flatList:(NSArray<TMOutlineItem *> * _Nullable * _Nullable)outFlatList {
    if (!latexString || latexString.length == 0) {
        if (outFlatList) *outFlatList = @[];
        return @[];
    }

    // 1. 预先计算每行的起始字符索引，方便根据 match.range.location 快速计算行号
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray array];
    [lineStarts addObject:@0];
    for (NSUInteger i = 0; i < latexString.length; i++) {
        if ([latexString characterAtIndex:i] == '\n') {
            [lineStarts addObject:@(i + 1)];
        }
    }

    // 辅助函数：根据字符索引获取 1-based 行号
    NSInteger (^lineNumberForLocation)(NSUInteger) = ^NSInteger(NSUInteger loc) {
        NSInteger low = 0;
        NSInteger high = (NSInteger)lineStarts.count - 1;
        while (low <= high) {
            NSInteger mid = low + (high - low) / 2;
            NSUInteger start = [lineStarts[mid] unsignedIntegerValue];
            if (start <= loc) {
                if (mid == (NSInteger)lineStarts.count - 1 || [lineStarts[mid + 1] unsignedIntegerValue] > loc) {
                    return mid + 1;
                }
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }
        return 1;
    };

    // 辅助函数：判断在当前行的 lineStart 到 loc 之间是否存在未转义的注释符 '%'
    BOOL (^isCommentedAtLocation)(NSUInteger) = ^BOOL(NSUInteger loc) {
        NSInteger lineIdx = lineNumberForLocation(loc) - 1;
        NSUInteger lineStart = [lineStarts[lineIdx] unsignedIntegerValue];
        BOOL escaped = NO;
        for (NSUInteger i = lineStart; i < loc; i++) {
            unichar c = [latexString characterAtIndex:i];
            if (c == '\\') {
                escaped = !escaped;
            } else {
                if (c == '%' && !escaped) {
                    return YES;
                }
                escaped = NO;
            }
        }
        return NO;
    };

    // 2. 正则表达式匹配标题命令起始部分：\part, \chapter, \section 等
    static NSRegularExpression *headingRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        headingRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(part|chapter|section|subsection|subsubsection|paragraph)\\*?\\s*\\{"
                                                                 options:0
                                                                   error:nil];
    });

    NSMutableArray<TMOutlineItem *> *flatItems = [NSMutableArray array];

    NSArray<NSTextCheckingResult *> *matches = [headingRegex matchesInString:latexString options:0 range:NSMakeRange(0, latexString.length)];
    for (NSTextCheckingResult *match in matches) {
        NSUInteger matchLoc = match.range.location;

        // 如果在注释中，则跳过
        if (isCommentedAtLocation(matchLoc)) {
            continue;
        }

        // 提取命令名称确定级别
        NSRange cmdRange = [match rangeAtIndex:1];
        NSString *cmdName = [latexString substringWithRange:cmdRange];
        TMOutlineLevel level = TMOutlineLevelSection;
        if ([cmdName isEqualToString:@"part"]) level = TMOutlineLevelPart;
        else if ([cmdName isEqualToString:@"chapter"]) level = TMOutlineLevelChapter;
        else if ([cmdName isEqualToString:@"section"]) level = TMOutlineLevelSection;
        else if ([cmdName isEqualToString:@"subsection"]) level = TMOutlineLevelSubsection;
        else if ([cmdName isEqualToString:@"subsubsection"]) level = TMOutlineLevelSubsubsection;
        else if ([cmdName isEqualToString:@"paragraph"]) level = TMOutlineLevelParagraph;

        // 找到开括号位置，进行花括号平衡扫描以提取完整标题文本
        NSUInteger openBraceLoc = match.range.location + match.range.length - 1;
        NSInteger depth = 1;
        NSUInteger closeBraceLoc = NSNotFound;
        BOOL escaped = NO;

        for (NSUInteger i = openBraceLoc + 1; i < latexString.length; i++) {
            unichar c = [latexString characterAtIndex:i];
            if (escaped) {
                escaped = NO;
                continue;
            }
            if (c == '\\') {
                escaped = YES;
                continue;
            }
            if (c == '{') {
                depth++;
            } else if (c == '}') {
                depth--;
                if (depth == 0) {
                    closeBraceLoc = i;
                    break;
                }
            }
        }

        NSString *rawTitle = @"";
        if (closeBraceLoc != NSNotFound && closeBraceLoc > openBraceLoc + 1) {
            rawTitle = [latexString substringWithRange:NSMakeRange(openBraceLoc + 1, closeBraceLoc - openBraceLoc - 1)];
        }

        NSString *cleanTitle = [self cleanHeadingTitle:rawTitle];
        if (cleanTitle.length == 0) {
            cleanTitle = [NSString stringWithFormat:@"未命名 %@", cmdName];
        }

        NSInteger line = lineNumberForLocation(matchLoc);
        TMOutlineItem *item = [[TMOutlineItem alloc] initWithTitle:cleanTitle
                                                             level:level
                                                        lineNumber:line
                                                      charLocation:matchLoc];
        [flatItems addObject:item];
    }

    if (outFlatList) {
        *outFlatList = [flatItems copy];
    }

    // 3. 构建层级树 (利用栈结构)
    NSMutableArray<TMOutlineItem *> *rootItems = [NSMutableArray array];
    NSMutableArray<TMOutlineItem *> *stack = [NSMutableArray array];

    for (TMOutlineItem *item in flatItems) {
        while (stack.count > 0 && stack.lastObject.level >= item.level) {
            [stack removeLastObject];
        }

        if (stack.count == 0) {
            [rootItems addObject:item];
        } else {
            [stack.lastObject addChild:item];
        }
        [stack addObject:item];
    }

    return [rootItems copy];
}

+ (nullable TMOutlineItem *)activeItemForLineNumber:(NSInteger)lineNumber
                                         inFlatList:(NSArray<TMOutlineItem *> *)flatList {
    if (!flatList || flatList.count == 0) return nil;

    TMOutlineItem *active = nil;
    for (TMOutlineItem *item in flatList) {
        if (item.lineNumber <= lineNumber) {
            active = item;
        } else {
            break;
        }
    }
    return active;
}

+ (NSString *)cleanHeadingTitle:(NSString *)rawTitle {
    if (!rawTitle || rawTitle.length == 0) return @"";

    NSMutableString *cleaned = [rawTitle mutableCopy];

    // 去除常见包装命令如 \textbf{...}, \textit{...}, \textsf{...}, \emph{...}, \text{...}
    static NSRegularExpression *wrapperRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wrapperRegex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(textbf|textit|textsf|emph|text|underline|textsc)\\{([^\\}]*)\\}"
                                                                 options:0
                                                                   error:nil];
    });

    [wrapperRegex replaceMatchesInString:cleaned
                                 options:0
                                   range:NSMakeRange(0, cleaned.length)
                            withTemplate:@"$2"];

    // 替换 \\ 换行符为空格
    [cleaned replaceOccurrencesOfString:@"\\\\"
                             withString:@" "
                                options:0
                                  range:NSMakeRange(0, cleaned.length)];

    // 压缩多余空白
    NSString *trimmed = [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray<NSString *> *components = [trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString *> *nonEmpty = [NSMutableArray array];
    for (NSString *comp in components) {
        if (comp.length > 0) {
            [nonEmpty addObject:comp];
        }
    }
    return [nonEmpty componentsJoinedByString:@" "];
}

@end
