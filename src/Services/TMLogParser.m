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

/// 编译过程中生成、下次编译又会读回来的文件：内容坏了（上次中断）或过时了（换了宏包 / 文献样式）会让编译失败。
static BOOL TMIsGeneratedAuxExtension(NSString *ext) {
    static NSSet<NSString *> *generated;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        generated = [NSSet setWithArray:@[@"aux", @"bbl", @"toc", @"lof", @"lot", @"lol", @"loa", @"nav", @"snm", @"out",
                                          @"ind", @"gls", @"acr", @"nls", @"brf", @"vrb", @"thm"]];
    });
    return [generated containsObject:ext.lowercaseString];
}

/// 会把辅助文件读进来的命令：辅助文件内容有问题时，TeX 报错的 "l.N" 行就是这些命令所在的行。
static BOOL TMLineReadsAuxiliaryFile(NSString *sourceLine) {
    static NSArray<NSString *> *readers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        readers = @[@"\\begin{document}", @"\\end{document}", @"\\tableofcontents", @"\\listoffigures", @"\\listoftables",
                    @"\\listof", @"\\bibliography", @"\\printbibliography", @"\\printglossar", @"\\printacronyms",
                    @"\\printnomenclature", @"\\printindex", @"\\include{"];
    });
    for (NSString *r in readers) {
        if ([sourceLine containsString:r]) return YES;
    }
    return NO;
}

/// 最后一遍 TeX 运行在日志里的范围：从它的启动行（行首的 "This is pdfTeX, Version …"，XeTeX / LuaHBTeX 同理）到结尾。
/// latexmk 多遍编译时前几遍的输出也在日志里。找不到启动行（TeX 根本没跑起来）返回 NSNotFound。
static NSRange TMLastTeXRun(NSString *log) {
    NSRange search = NSMakeRange(0, log.length);
    while (search.length > 0) {
        NSRange hit = [log rangeOfString:@"This is " options:NSBackwardsSearch range:search];
        if (hit.location == NSNotFound) break;
        // 行首才算：正文里的 "This is" 会出现在坏盒子、错误上下文里，但都不在行首
        if (hit.location == 0 || [log characterAtIndex:hit.location - 1] == '\n') {
            NSString *line = [log substringWithRange:[log lineRangeForRange:hit]];
            if ([line containsString:@"TeX, Version"] && ![line containsString:@"BibTeX"]) {
                return NSMakeRange(hit.location, log.length - hit.location);
            }
        }
        search.length = hit.location;
    }
    return NSMakeRange(NSNotFound, 0);
}

+ (nullable NSString *)staleAuxiliaryFileInLog:(NSString *)log {
    static NSRegularExpression *firstError; // "./main.bbl:3: Undefined control sequence."（-file-line-error）或 "! …"
    static NSRegularExpression *opened;     // "(./main.aux"：TeX 打开文件时打印的 "(路径"
    static NSRegularExpression *errorLine;  // "l.2 \begin{document}"：出错时正在读的源码行
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        firstError = [NSRegularExpression regularExpressionWithPattern:@"^(?:(?:\\./)?([^:\\n]+\\.([A-Za-z]+)):\\d+:|! )"
                                                               options:NSRegularExpressionAnchorsMatchLines error:nil];
        opened = [NSRegularExpression regularExpressionWithPattern:@"\\((\\.?/?[^()\\s]+\\.([A-Za-z]+))" options:0 error:nil];
        errorLine = [NSRegularExpression regularExpressionWithPattern:@"^l\\.\\d+ (.*)$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    });

    NSRange run = TMLastTeXRun(log);
    if (run.location == NSNotFound) return nil;
    NSTextCheckingResult *error = [firstError firstMatchInString:log options:0 range:run];
    if (!error) return nil;

    // ① 第一个错误直接报在辅助文件里（旧 .bbl：./main.bbl:3:）
    if ([error rangeAtIndex:1].location != NSNotFound && TMIsGeneratedAuxExtension([log substringWithRange:[error rangeAtIndex:2]])) {
        return [log substringWithRange:[error rangeAtIndex:1]].lastPathComponent;
    }

    // ② 报在正文，但三条同时满足：错误是“文件读到一半就结束了”；紧挨着错误之前打开的是辅助文件；
    //    出错的源码行正是读它的命令（截断的 .aux 报在 \begin{document}，截断的 .toc 报在 \tableofcontents）。
    //    正文漏了右括号、或错误恰好写在 \begin{document} 同一行时，总有一条不满足。
    NSRange errorText = [log lineRangeForRange:NSMakeRange(error.range.location, 0)];
    if (![[log substringWithRange:errorText] containsString:@"File ended while scanning"]) return nil;

    NSUInteger windowStart = MAX(run.location, error.range.location > 600 ? error.range.location - 600 : 0);
    NSTextCheckingResult *lastOpened = [opened matchesInString:log options:0
                                                         range:NSMakeRange(windowStart, error.range.location - windowStart)].lastObject;
    if (!lastOpened || !TMIsGeneratedAuxExtension([log substringWithRange:[lastOpened rangeAtIndex:2]])) return nil;

    NSUInteger after = NSMaxRange(errorText);
    NSTextCheckingResult *source = [errorLine firstMatchInString:log options:0 range:NSMakeRange(after, MIN(log.length - after, (NSUInteger)1200))];
    if (!source || !TMLineReadsAuxiliaryFile([log substringWithRange:[source rangeAtIndex:1]])) return nil;
    return [log substringWithRange:[lastOpened rangeAtIndex:1]].lastPathComponent;
}

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
