#import "TMDocument.h"

@implementation TMDocument

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
@"1. 按 \\textbf{⌘B} 一键保存并自动编译，右侧即可获得高清 PDF 预览；\n"
@"2. 在右侧 PDF 任意位置 \\textbf{⌘+鼠标点击}，左侧源码将瞬间跳转至对应代码行；\n"
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
    NSError *utf8Error = nil;
    NSString *str = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&utf8Error];
    if (!str) {
        // 尝试非 UTF-8；仍失败则报告首次（更有意义）的错误
        str = [NSString stringWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:nil];
        if (!str) {
            if (error) *error = utf8Error;
            return nil;
        }
    }

    TMDocument *doc = [[TMDocument alloc] init];
    doc.fileURL = url;
    doc.content = str;
    doc.isDirty = NO;
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
    BOOL success = [self.content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (success) {
        self.fileURL = url;
        self.isDirty = NO;
        self.isScratch = NO;
    }
    return success;
}

- (BOOL)saveScratchToURL:(NSURL *)url error:(NSError **)error {
    BOOL success = [self.content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (success) {
        self.fileURL = url;
        self.isScratch = YES;
    }
    return success;
}

- (BOOL)saveCurrentFileWithError:(NSError **)error {
    if (!self.fileURL) return NO;
    if (self.isScratch) return [self saveScratchToURL:self.fileURL error:error];
    return [self saveToURL:self.fileURL error:error];
}

- (void)cleanAuxiliaryFiles {
    if (!self.fileURL) return;

    NSString *dir = [self.fileURL URLByDeletingLastPathComponent].path;
    NSString *base = [self.fileURL.URLByDeletingPathExtension lastPathComponent];
    NSArray<NSString *> *extensions = @[@"aux", @"log", @"synctex.gz", @"fls", @"fdb_latexmk", @"out", @"toc", @"bbl", @"blg"];

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *ext in extensions) {
        NSString *auxPath = [dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:ext]];
        if ([fm fileExistsAtPath:auxPath]) {
            [fm removeItemAtPath:auxPath error:nil];
        }
    }
}

@end
