#import "TMLogParser.h"

@implementation TMLogIssue
- (NSString *)kindLabel {
    switch (self.kind) {
        case TMLogIssueError: return @"错误";
        case TMLogIssueWarning: return @"警告";
        case TMLogIssueBadBox: return @"坏盒子";
    }
    return @"";
}
@end

@implementation TMLogParser

+ (NSArray<TMLogIssue *> *)issuesFromLog:(NSString *)log {
    NSMutableArray<TMLogIssue *> *issues = [NSMutableArray array];
    if (log.length == 0) return issues;

    static NSRegularExpression *inputLineRegex;   // "... on input line 7."
    static NSRegularExpression *atLinesRegex;     // "... at lines 20--21"
    static NSRegularExpression *tomlineRegex;     // "l.12 ..."
    static NSRegularExpression *fileLineRegex;    // "./file.tex:12: message"  (-file-line-error)
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inputLineRegex = [NSRegularExpression regularExpressionWithPattern:@"on input line (\\d+)" options:0 error:nil];
        atLinesRegex = [NSRegularExpression regularExpressionWithPattern:@"at lines? (\\d+)" options:0 error:nil];
        tomlineRegex = [NSRegularExpression regularExpressionWithPattern:@"^l\\.(\\d+)" options:0 error:nil];
        fileLineRegex = [NSRegularExpression regularExpressionWithPattern:@"^((?:\\./)?[^:\\n]+\\.(?:tex|sty|cls|ltx|def)):(\\d+):\\s*(.+)$" options:0 error:nil];
    });

    NSInteger (^lineFrom)(NSRegularExpression *, NSString *) = ^NSInteger(NSRegularExpression *re, NSString *s) {
        NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
        return m ? [[s substringWithRange:[m rangeAtIndex:1]] integerValue] : 0;
    };

    NSArray<NSString *> *lines = [log componentsSeparatedByString:@"\n"];
    NSUInteger count = lines.count;

    for (NSUInteger i = 0; i < count; i++) {
        NSString *raw = lines[i];
        NSString *l = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (l.length == 0) continue;

        if ([l hasPrefix:@"! "]) {
            TMLogIssue *issue = [[TMLogIssue alloc] init];
            issue.kind = TMLogIssueError;
            issue.message = [l substringFromIndex:2];
            // TeX 在错误后几行内输出 "l.<n>"
            for (NSUInteger j = i + 1; j < MIN(i + 15, count); j++) {
                NSInteger n = lineFrom(tomlineRegex, lines[j]);
                if (n > 0) { issue.line = n; break; }
            }
            [issues addObject:issue];
            continue;
        }

        NSTextCheckingResult *fl = [fileLineRegex firstMatchInString:l options:0 range:NSMakeRange(0, l.length)];
        if (fl) {
            TMLogIssue *issue = [[TMLogIssue alloc] init];
            issue.kind = TMLogIssueError;
            issue.filePath = [l substringWithRange:[fl rangeAtIndex:1]];
            issue.line = [[l substringWithRange:[fl rangeAtIndex:2]] integerValue];
            issue.message = [l substringWithRange:[fl rangeAtIndex:3]];
            [issues addObject:issue];
            continue;
        }

        if ([l hasPrefix:@"Overfull "] || [l hasPrefix:@"Underfull "]) {
            TMLogIssue *issue = [[TMLogIssue alloc] init];
            issue.kind = TMLogIssueBadBox;
            issue.message = l;
            issue.line = lineFrom(atLinesRegex, l);
            [issues addObject:issue];
            continue;
        }

        BOOL isWarning = [l hasPrefix:@"LaTeX Warning:"] ||
                         [l hasPrefix:@"LaTeX Font Warning:"] ||
                         ([l hasPrefix:@"Package "] && [l containsString:@" Warning:"]) ||
                         ([l hasPrefix:@"Class "] && [l containsString:@" Warning:"]);
        if (isWarning) {
            TMLogIssue *issue = [[TMLogIssue alloc] init];
            issue.kind = TMLogIssueWarning;
            // 警告信息可能折到下一行（TeX 的 79 列换行），拼接紧随其后的续行
            NSMutableString *msg = [l mutableCopy];
            NSUInteger j = i + 1;
            while (j < count && raw.length >= 79 && lines[j].length > 0 && ![lines[j] hasPrefix:@"("] ) {
                NSString *cont = [lines[j] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if ([cont hasPrefix:@"!"] || [cont hasPrefix:@"LaTeX"] || [cont hasPrefix:@"Package"] || [cont hasPrefix:@"Overfull"] || [cont hasPrefix:@"Underfull"]) break;
                [msg appendString:@" "];
                [msg appendString:cont];
                raw = lines[j];
                j++;
            }
            issue.message = msg;
            issue.line = lineFrom(inputLineRegex, msg);
            [issues addObject:issue];
            i = j - 1;
            continue;
        }
    }

    return issues;
}

+ (nullable TMLogIssue *)firstErrorInIssues:(NSArray<TMLogIssue *> *)issues {
    for (TMLogIssue *issue in issues) {
        if (issue.kind == TMLogIssueError) return issue;
    }
    return nil;
}

+ (NSUInteger)countOfKind:(TMLogIssueKind)kind inIssues:(NSArray<TMLogIssue *> *)issues {
    NSUInteger n = 0;
    for (TMLogIssue *issue in issues) {
        if (issue.kind == kind) n++;
    }
    return n;
}

@end
