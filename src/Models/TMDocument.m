#import "TMDocument.h"
#import <sys/stat.h>

NSErrorDomain const TMDocumentErrorDomain = @"TMDocumentErrorDomain";

@interface TMDocument ()
@property (nonatomic, readwrite) NSStringEncoding textEncoding;
@property (nonatomic, copy, nullable) NSData *byteOrderMark;
@property (nonatomic, copy, nullable) NSData *diskFingerprint;
@property (nonatomic) BOOL hasDiskBaseline;
@end

static NSError *TMDocumentErrorWithCode(TMDocumentError code, NSString *message) {
    return [NSError errorWithDomain:TMDocumentErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}

/// stat 不受 NSURL 资源缓存影响；ctime / inode 可以识别保留 mtime 的替换与原地写入。
static NSData *TMFileFingerprint(NSURL *url) {
    struct stat info;
    if (!url || stat(url.path.fileSystemRepresentation, &info) != 0) return nil;
    int64_t fields[] = {info.st_dev, (int64_t)info.st_ino, info.st_size,
        info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec, info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec};
    return [NSData dataWithBytes:fields length:sizeof(fields)];
}

static BOOL TMSameFingerprint(NSData *a, NSData *b) {
    return a == b || [a isEqualToData:b];
}

static BOOL TMEncodingSpace(unichar c) { return c == ' ' || c == '\t' || c == '\r' || c == '\n'; }
static BOOL TMEncodingLetter(unichar c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '@'; }

static NSUInteger TMSkipEncodingTrivia(NSString *text, NSUInteger i) {
    while (i < text.length) {
        unichar c = [text characterAtIndex:i];
        if (TMEncodingSpace(c)) i++;
        else if (c == '%') {
            while (i < text.length && [text characterAtIndex:i] != '\n' && [text characterAtIndex:i] != '\r') i++;
        } else break;
    }
    return i;
}

static NSString *TMReadEncodingCommand(NSString *text, NSUInteger *position) {
    NSUInteger start = ++*position;
    if (start >= text.length) return @"";
    if (!TMEncodingLetter([text characterAtIndex:start])) (*position)++;
    else while (*position < text.length && TMEncodingLetter([text characterAtIndex:*position])) (*position)++;
    return [text substringWithRange:NSMakeRange(start, *position - start)];
}

/// 只读取语法参数；注释和转义括号不参与配对。失败时停在 EOF，避免把残缺定义体当成声明。
static NSString *TMReadEncodingGroup(NSString *text, NSUInteger *position, unichar open, unichar close) {
    NSUInteger start = TMSkipEncodingTrivia(text, *position);
    *position = start;
    if (start >= text.length || [text characterAtIndex:start] != open) return nil;
    NSUInteger depth = 0;
    for (NSUInteger i = start; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\\') { i++; continue; }
        if (c == '%') {
            while (i < text.length && [text characterAtIndex:i] != '\r' && [text characterAtIndex:i] != '\n') i++;
            continue;
        }
        if (c == open) depth++;
        else if (c == close && --depth == 0) {
            *position = i + 1;
            return [text substringWithRange:NSMakeRange(start + 1, i - start - 1)];
        }
    }
    *position = text.length;
    return nil;
}

/// 编码元信息只有两处：文件起始的注释头，以及正文之前、组/环境/条件分支外的 inputenc。
/// 读磁盘的字节视图与保存时的 Unicode 文本共用同一词法边界，不按字节/UTF-16 长度分别截断。
static NSString *TMDeclaredEncoding(NSString *text) {
    static NSRegularExpression *magic;
    static NSSet *definitions, *rawEnvironments, *conditionals;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        magic = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*%[ \\t]*![ \\t]*TEX[ \\t]+encoding[ \\t]*=[ \\t]*([^\\r\\n]+)" options:NSRegularExpressionCaseInsensitive error:nil];
        definitions = [NSSet setWithArray:@[@"newcommand", @"renewcommand", @"providecommand", @"DeclareRobustCommand", @"DeclareMathOperator", @"newenvironment", @"renewenvironment", @"def", @"gdef", @"edef", @"xdef"]];
        rawEnvironments = [NSSet setWithArray:@[@"comment", @"verbatim", @"verbatim*", @"Verbatim", @"Verbatim*", @"BVerbatim", @"LVerbatim", @"lstlisting", @"minted", @"filecontents", @"filecontents*"]];
        conditionals = [NSSet setWithArray:@[@"if", @"ifcat", @"ifnum", @"ifdim", @"ifodd", @"ifvmode", @"ifhmode", @"ifmmode", @"ifinner", @"ifvoid", @"ifhbox", @"ifvbox", @"ifx", @"ifeof", @"iftrue", @"iffalse", @"ifcase", @"ifdefined", @"ifcsname", @"iffontchar"]];
    });
    NSUInteger i = 0;
    while (i < text.length) {
        NSUInteger start = i;
        // 这里只把 CR/LF 当行界，不能把旧编码/UTF-8 字节里的 0x85 当 Unicode 换行。
        while (i < text.length && [text characterAtIndex:i] != '\r' && [text characterAtIndex:i] != '\n') i++;
        NSUInteger first = start;
        while (first < i && ([text characterAtIndex:first] == ' ' || [text characterAtIndex:first] == '\t')) first++;
        if (first < i && [text characterAtIndex:first] != '%') { i = first; break; }
        NSString *line = [text substringWithRange:NSMakeRange(start, i - start)];
        NSTextCheckingResult *match = [magic firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (match) return [[line substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (i < text.length) i++;
    }

    NSUInteger environments = 0, conditionalDepth = 0;
    while ((i = TMSkipEncodingTrivia(text, i)) < text.length) {
        unichar c = [text characterAtIndex:i];
        if (c == '{' || c == '[') { TMReadEncodingGroup(text, &i, c, c == '{' ? '}' : ']'); continue; }
        if (c != '\\') { i++; continue; }
        NSString *command = TMReadEncodingCommand(text, &i);
        if ([command isEqualToString:@"verb"]) {
            if (i < text.length && [text characterAtIndex:i] == '*') i++;
            if (i >= text.length || TMEncodingSpace([text characterAtIndex:i])) continue;
            unichar delimiter = [text characterAtIndex:i++];
            while (i < text.length && [text characterAtIndex:i] != delimiter && [text characterAtIndex:i] != '\r' && [text characterAtIndex:i] != '\n') i++;
            if (i < text.length && [text characterAtIndex:i] == delimiter) i++;
        } else if ([definitions containsObject:command]) {
            if (i < text.length && [text characterAtIndex:i] == '*') i++;
            i = TMSkipEncodingTrivia(text, i);
            if (i < text.length && [text characterAtIndex:i] == '\\') TMReadEncodingCommand(text, &i);
            else TMReadEncodingGroup(text, &i, '{', '}');
            if ([command hasSuffix:@"def"]) {
                while (i < text.length && [text characterAtIndex:i] != '{') i++;
            } else {
                while (TMReadEncodingGroup(text, &i, '[', ']')) {}
            }
            TMReadEncodingGroup(text, &i, '{', '}');
            if ([command hasSuffix:@"environment"]) TMReadEncodingGroup(text, &i, '{', '}');
        } else if ([conditionals containsObject:command]) conditionalDepth++;
        else if ([command isEqualToString:@"fi"]) { if (conditionalDepth) conditionalDepth--; }
        else if ([command isEqualToString:@"begin"] || [command isEqualToString:@"end"]) {
            NSString *name = TMReadEncodingGroup(text, &i, '{', '}');
            if ([command isEqualToString:@"end"]) { if (environments) environments--; continue; }
            if ([name isEqualToString:@"document"] && conditionalDepth == 0) return nil;
            if (name && [rawEnvironments containsObject:name]) {
                NSString *end = [NSString stringWithFormat:@"\\end{%@}", name];
                NSRange found = [text rangeOfString:end options:NSLiteralSearch range:NSMakeRange(i, text.length - i)];
                if (found.location == NSNotFound) return nil;
                i = NSMaxRange(found);
            } else if (name) environments++;
        } else if (environments == 0 && conditionalDepth == 0 &&
                   ([command isEqualToString:@"usepackage"] || [command isEqualToString:@"RequirePackage"])) {
            NSString *encoding = TMReadEncodingGroup(text, &i, '[', ']');
            NSString *packages = TMReadEncodingGroup(text, &i, '{', '}');
            if (!encoding || [encoding containsString:@","]) continue;
            for (NSString *package in [packages componentsSeparatedByString:@","]) {
                if ([[package stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqualToString:@"inputenc"])
                    return [encoding stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            }
        }
    }
    return nil;
}

static NSStringEncoding TMEncodingNamed(NSString *name) {
    NSString *key = name.lowercaseString;
    NSDictionary *aliases = @{@"utf8":@"UTF-8", @"utf8x":@"UTF-8", @"utf-8 unicode":@"UTF-8",
        @"latin1":@"ISO-8859-1", @"latin2":@"ISO-8859-2", @"latin9":@"ISO-8859-15", @"ansinew":@"windows-1252",
        @"applemac":@"macintosh", @"sjis":@"Shift_JIS"};
    CFStringEncoding encoding = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)(aliases[key] ?: name));
    return encoding == kCFStringEncodingInvalidId ? 0 : CFStringConvertEncodingToNSStringEncoding(encoding);
}

/// 不把任意旧编码猜成 Latin-1。声明优先；无声明时只接受 UTF-8 或系统识别的 Unicode。
static NSString *TMDecodeDocument(NSData *data, NSStringEncoding *encoding, NSData **bom, NSError **error) {
    const unsigned char *bytes = data.bytes;
    NSUInteger skip = 0;
    if (data.length >= 4 && !memcmp(bytes, "\xFF\xFE\0\0", 4)) { *encoding = NSUTF32LittleEndianStringEncoding; skip = 4; }
    else if (data.length >= 4 && !memcmp(bytes, "\0\0\xFE\xFF", 4)) { *encoding = NSUTF32BigEndianStringEncoding; skip = 4; }
    else if (data.length >= 3 && !memcmp(bytes, "\xEF\xBB\xBF", 3)) { *encoding = NSUTF8StringEncoding; skip = 3; }
    else if (data.length >= 2 && !memcmp(bytes, "\xFF\xFE", 2)) { *encoding = NSUTF16LittleEndianStringEncoding; skip = 2; }
    else if (data.length >= 2 && !memcmp(bytes, "\xFE\xFF", 2)) { *encoding = NSUTF16BigEndianStringEncoding; skip = 2; }
    NSString *text = nil;
    if (skip) {
        *bom = [data subdataWithRange:NSMakeRange(0, skip)];
        text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(skip, data.length - skip)] encoding:*encoding];
    } else {
        NSString *prefix = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSString *declared = TMDeclaredEncoding(prefix ?: @"");
        *encoding = declared ? TMEncodingNamed(declared) : NSUTF8StringEncoding;
        if (*encoding) text = [[NSString alloc] initWithData:data encoding:*encoding];
        if (!declared && data.length && memchr(bytes, 0, data.length)) {
            BOOL lossy = NO;
            NSString *detected = nil;
            NSArray *unicode = @[@(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding), @(NSUTF32LittleEndianStringEncoding), @(NSUTF32BigEndianStringEncoding)];
            NSStringEncoding candidate = [NSString stringEncodingForData:data encodingOptions:@{NSStringEncodingDetectionSuggestedEncodingsKey:unicode, NSStringEncodingDetectionUseOnlySuggestedEncodingsKey:@YES, NSStringEncodingDetectionAllowLossyKey:@NO} convertedString:&detected usedLossyConversion:&lossy];
            if (!lossy && [unicode containsObject:@(candidate)]) { text = detected; *encoding = candidate; }
        }
    }
    // NUL 不是可编辑的 TeX 文本；拒绝二进制内容和错判的 UTF-16。
    if (text && [text rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location == NSNotFound) return text;
    if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorUnknownEncoding,
        @"无法可靠识别文件编码。请在文件开头声明 % !TEX encoding = GBK（或实际编码），或先将文件转换为 UTF-8 后再打开。");
    return nil;
}

@implementation TMDocument

- (instancetype)init {
    if ((self = [super init])) {
        _textEncoding = NSUTF8StringEncoding;
        _content = @"";
    }
    return self;
}

+ (instancetype)documentWithDefaultTemplate {
    TMDocument *doc = [[TMDocument alloc] init];
    doc.content =
@"\\documentclass{article}\n"
@"\\usepackage{amsmath}\n"
@"\\usepackage{geometry}\n"
@"\\geometry{a4paper, margin=1in}\n\n"
@"\\title{My LaTeX Document}\n"
@"\\author{Author}\n"
@"\\date{\\today}\n\n"
@"\\begin{document}\n"
@"\\maketitle\n\n"
@"\\section{Introduction}\n"
@"Welcome to your lightweight native LaTeX editor on macOS!\n\n"
@"\\section{Mathematics}\n"
@"Euler's identity is given by:\n"
@"\\begin{equation}\n"
@"  e^{i\\pi} + 1 = 0\n"
@"\\end{equation}\n\n"
@"\\end{document}\n";
    doc.isDirty = NO;
    return doc;
}

+ (instancetype)documentWithChineseTemplate {
    TMDocument *doc = [[TMDocument alloc] init];
    doc.content =
@"\\documentclass[UTF8]{ctexart}\n"
@"\\usepackage{amsmath}\n"
@"\\usepackage{geometry}\n"
@"\\geometry{a4paper, margin=1in}\n\n"
@"\\title{中文研究报告}\n"
@"\\author{作者}\n"
@"\\date{\\today}\n\n"
@"\\begin{document}\n"
@"\\maketitle\n\n"
@"\\section{引言}\n"
@"欢迎使用 TeXMini 原生轻量 LaTeX 编辑器！\n"
@"在中文文档排版中，推荐使用 XeLaTeX 引擎（在底部状态栏可快速切换）。\n\n"
@"\\section{公式排版示例}\n"
@"柯西-施瓦茨不等式：\n"
@"\\begin{equation}\n"
@"  \\left( \\sum_{k=1}^n a_k b_k \\right)^2 \\le \\left( \\sum_{k=1}^n a_k^2 \\right) \\left( \\sum_{k=1}^n b_k^2 \\right)\n"
@"\\end{equation}\n\n"
@"\\section{操作提示}\n"
@"1. 按 \\textbf{⌘↩} 一键保存并自动编译，右侧即可获得高清 PDF 预览；\n"
@"2. 在右侧 PDF 任意位置 \\textbf{双击}（或 ⌘+点击），左侧源码将瞬间跳转至对应代码行；\n"
@"3. 在左侧代码任意位置 \\textbf{双击}（或 ⌘+点击、按 \\textbf{⌘J}），右侧 PDF 对应段落将闪烁定位高亮；点击左侧大纲章节同样会同步定位。\n\n"
@"\\end{document}\n";
    doc.isDirty = NO;
    return doc;
}

+ (instancetype)documentWithBlankTemplate {
    TMDocument *doc = [[TMDocument alloc] init];
    doc.content =
@"\\documentclass{article}\n"
@"\\usepackage{amsmath}\n\n"
@"\\begin{document}\n"
@"% 在此书写您的 LaTeX 代码\n\n"
@"\\end{document}\n";
    doc.isDirty = NO;
    return doc;
}

+ (nullable instancetype)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    NSData *before = TMFileFingerprint(url);
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    NSStringEncoding encoding = NSUTF8StringEncoding;
    NSData *bom = nil;
    NSString *str = TMDecodeDocument(data, &encoding, &bom, error);
    if (!str) return nil;
    NSData *after = TMFileFingerprint(url);
    if (!TMSameFingerprint(before, after)) {
        if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorExternalChange, @"读取期间文件被其他程序修改，请重新打开。");
        return nil;
    }

    TMDocument *doc = [[TMDocument alloc] init];
    doc.fileURL = url;
    doc.content = str;
    doc.isDirty = NO;
    doc.textEncoding = encoding;
    doc.byteOrderMark = bom;
    doc.diskFingerprint = after;
    doc.hasDiskBaseline = YES;
    return doc;
}

- (NSURL *)expectedPDFURL {
    if (!self.fileURL) return nil;
    NSString *base = [self.fileURL.URLByDeletingPathExtension lastPathComponent];
    return [[self.fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"pdf"]];
}

- (NSURL *)expectedSyncTeXURL {
    if (!self.fileURL) return nil;
    NSString *base = [self.fileURL.URLByDeletingPathExtension lastPathComponent];
    return [[self.fileURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"synctex.gz"]];
}

- (NSString *)displayName {
    if (!self.fileURL || self.isScratch) return @"未命名文档.tex";
    return self.fileURL.lastPathComponent;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
    BOOL success = [self writeContentToURL:url error:error];
    if (success) {
        self.fileURL = url;
        self.isDirty = NO;
        self.isScratch = NO;
        [self acknowledgeExternalChanges];
    }
    return success;
}

- (BOOL)saveScratchToURL:(NSURL *)url error:(NSError **)error {
    BOOL success = [self writeContentToURL:url error:error];
    if (success) {
        self.fileURL = url;
        self.isScratch = YES;
        [self acknowledgeExternalChanges];
    }
    return success;
}

- (BOOL)saveCurrentFileWithError:(NSError **)error {
    if (!self.fileURL) {
        if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorExternalChange, @"文档还没有保存位置，请先另存为。");
        return NO;
    }
    if (self.isScratch) return [self saveScratchToURL:self.fileURL error:error];
    return [self saveToURL:self.fileURL error:error];
}

- (BOOL)writeContentToURL:(NSURL *)url error:(NSError **)error {
    NSString *declared = TMDeclaredEncoding(self.content);
    NSStringEncoding encoding = declared ? TMEncodingNamed(declared) : self.textEncoding;
    if (!encoding) {
        if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorUnknownEncoding,
            [NSString stringWithFormat:@"无法识别声明的文件编码“%@”，文件未被修改。请使用 UTF-8、GBK 或 ISO-8859-1 等有效编码名。", declared]);
        return NO;
    }
    NSData *encoded = [self.content dataUsingEncoding:encoding allowLossyConversion:NO];
    if (!encoded) {
        if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorUnrepresentableEncoding,
            [NSString stringWithFormat:@"新增字符无法用文件编码（%@）无损保存，文件未被修改。请把文件中的编码声明（含 inputenc）改为 UTF-8 后再保存。", [NSString localizedNameOfStringEncoding:encoding]]);
        return NO;
    }
    NSData *bom = encoding == self.textEncoding ? self.byteOrderMark : nil;
    if (bom.length) {
        NSMutableData *withBOM = [bom mutableCopy];
        [withBOM appendData:encoded];
        encoded = withBOM;
    }
    // 编码完成后才检查，尽量缩短检查与原子写之间的窗口；这不替代跨进程文件事务。
    if ([url.URLByStandardizingPath isEqual:self.fileURL.URLByStandardizingPath] && [self hasExternalChanges]) {
        if (error) *error = TMDocumentErrorWithCode(TMDocumentErrorExternalChange, @"文件已在磁盘上被修改、移动或删除，未覆盖外部更改。请重新载入或明确选择保留编辑器内容后再保存。");
        return NO;
    }
    if (![encoded writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    self.textEncoding = encoding;
    self.byteOrderMark = bom;
    return YES;
}

- (BOOL)hasExternalChanges {
    return self.hasDiskBaseline && !TMSameFingerprint(self.diskFingerprint, TMFileFingerprint(self.fileURL));
}

- (void)acknowledgeExternalChanges {
    self.diskFingerprint = TMFileFingerprint(self.fileURL);
    self.hasDiskBaseline = YES;
}

- (void)acknowledgeDiskStateFromDocument:(TMDocument *)diskDocument {
    if (![self.fileURL.URLByStandardizingPath isEqual:diskDocument.fileURL.URLByStandardizingPath] || !diskDocument.hasDiskBaseline) return;
    self.diskFingerprint = diskDocument.diskFingerprint;
    self.hasDiskBaseline = YES;
}

- (void)cleanAuxiliaryFiles {
    if (!self.fileURL) return;
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:self.fileURL];
}

+ (NSArray<NSString *> *)auxiliaryExtensions {
    return @[@"aux", @"log", @"synctex.gz", @"fls", @"fdb_latexmk", @"out", @"toc", @"lof", @"lot", @"lol", @"loa",
             @"bbl", @"blg", @"bcf", @"run.xml", @"nav", @"snm", @"vrb", @"idx", @"ilg", @"ind", @"xdv",
             // .ist / .xdy 可能是手写索引样式，始终保留。
             @"glo", @"gls", @"glg", @"glsdefs", @"acn", @"acr", @"alg", @"nlo", @"nls", @"nlg",
             // 定理列表 / 习题答案（answers、exsheets 等）/ 反向引用
             @"thm", @"ent", @"xyc", @"brf"];
}

+ (void)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL {
    [self cleanAuxiliaryFilesForTeXFileURL:texURL keepingBibliography:NO];
}

+ (void)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL keepingBibliography:(BOOL)keepBibliography {
    NSString *dir = [texURL URLByDeletingLastPathComponent].path;
    NSString *base = [texURL.URLByDeletingPathExtension lastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];

    // \include 的各章 .aux：只删主 .aux 里 \@input{…} 明确列出、且对应 .tex 存在的（必须在删主 .aux 之前读）
    NSString *mainAux = [NSString stringWithContentsOfFile:[dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"aux"]]
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (mainAux) {
        static NSRegularExpression *inputRe;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            inputRe = [NSRegularExpression regularExpressionWithPattern:@"\\\\@input\\{([^}]+\\.aux)\\}" options:0 error:nil];
        });
        NSString *root = [dir.stringByStandardizingPath stringByAppendingString:@"/"];
        for (NSTextCheckingResult *m in [inputRe matchesInString:mainAux options:0 range:NSMakeRange(0, mainAux.length)]) {
            NSString *chapterAux = [[dir stringByAppendingPathComponent:[mainAux substringWithRange:[m rangeAtIndex:1]]] stringByStandardizingPath];
            if (![chapterAux hasPrefix:root]) continue;   // 不碰项目目录以外的文件
            NSString *chapterTeX = [chapterAux.stringByDeletingPathExtension stringByAppendingPathExtension:@"tex"];
            if ([fm fileExistsAtPath:chapterTeX]) [fm removeItemAtPath:chapterAux error:nil];
        }
    }

    for (NSString *ext in [self auxiliaryExtensions]) {
        if (keepBibliography && [ext isEqualToString:@"bbl"]) continue;
        NSString *auxPath = [dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:ext]];
        if ([fm fileExistsAtPath:auxPath]) {
            [fm removeItemAtPath:auxPath error:nil];
        }
    }
}

@end
