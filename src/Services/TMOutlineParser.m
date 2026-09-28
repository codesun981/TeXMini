#import "TMOutlineParser.h"
#import "TMLaTeXScanner.h"

@implementation TMOutlineParser

+ (NSArray<TMOutlineItem *> *)parseOutlineFromLaTeXString:(NSString *)latexString
                                                 flatList:(NSArray<TMOutlineItem *> * _Nullable * _Nullable)outFlatList {
    return [self parseOutlineFromScan:[TMLaTeXScanner scanString:latexString ?: @""]
                            lineIndex:[[TMLineIndex alloc] initWithString:latexString ?: @""] flatList:outFlatList];
}

+ (NSArray<TMOutlineItem *> *)parseOutlineFromScan:(TMLaTeXScanResult *)scan
                                       lineIndex:(TMLineIndex *)lineIndex
                                        flatList:(NSArray<TMOutlineItem *> * _Nullable * _Nullable)outFlatList {
    // 2. 标题由统一扫描器给出：已跳过注释、代码块、\newcommand 定义体，认识 \section[短]{长}、
    //    包装标题命令的自定义命令以及 beamer 帧标题
    NSMutableArray<TMOutlineItem *> *flatItems = [NSMutableArray array];
    for (TMLaTeXHeading *heading in scan.headings) {
        NSString *cleanTitle = [self cleanHeadingTitle:heading.rawTitle];
        if (cleanTitle.length == 0) {
            cleanTitle = [NSString stringWithFormat:@"未命名 %@", heading.commandName];
        }
        TMOutlineItem *item = [[TMOutlineItem alloc] initWithTitle:cleanTitle
                                                             level:heading.level
                                                        lineNumber:[lineIndex lineNumberForCharacterIndex:heading.location]
                                                      charLocation:heading.location];
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
