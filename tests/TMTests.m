// TeXMini 极简单元测试：无 XCTest 依赖，clang 直接编译运行。
// 用法：tests/run_tests.sh
#import <Foundation/Foundation.h>
#import "TMDocument.h"
#import "TMEditActions.h"
#import "TMMagicComments.h"
#import "TMLogParser.h"
#import "TMRecentFiles.h"
#import "TMProject.h"
#import "TMCompletionProvider.h"
#import "TMPreferences.h"
#import "TMCompiler.h"

static int gPassed = 0;
static int gFailed = 0;
static const char *gCurrentTest = "";

#define TM_TEST(name) static void name(void); \
    __attribute__((constructor)) static void name##_register(void) { tm_register(#name, name); } \
    static void name(void)

typedef void (*TMTestFn)(void);
static NSMutableArray *gTests;
static void tm_register(const char *name, TMTestFn fn) {
    if (!gTests) gTests = [NSMutableArray array];
    [gTests addObject:@[[NSString stringWithUTF8String:name], [NSValue valueWithPointer:(void *)fn]]];
}

#define TM_FAIL(fmt, ...) do { gFailed++; fprintf(stderr, "  ✗ %s (%s:%d): " fmt "\n", gCurrentTest, __FILE__, __LINE__, ##__VA_ARGS__); return; } while (0)
#define TM_ASSERT_TRUE(x) do { if (!(x)) TM_FAIL("expected true: %s", #x); } while (0)
#define TM_ASSERT_NIL(x) do { if ((x) != nil) TM_FAIL("expected nil: %s", #x); } while (0)
#define TM_ASSERT_EQ_INT(a, b) do { long _a = (long)(a), _b = (long)(b); if (_a != _b) TM_FAIL("%s == %ld, expected %ld", #a, _a, _b); } while (0)
#define TM_ASSERT_EQ_STR(a, b) do { NSString *_a = (a), *_b = (b); if (!((_a == nil && _b == nil) || [_a isEqualToString:_b])) TM_FAIL("%s == \"%s\", expected \"%s\"", #a, _a ? [_a UTF8String] : "(nil)", _b ? [_b UTF8String] : "(nil)"); } while (0)

#pragma mark - TMDocument

TM_TEST(test_templates_are_not_empty) {
    TM_ASSERT_TRUE([TMDocument documentWithDefaultTemplate].content.length > 0);
    TM_ASSERT_TRUE([TMDocument documentWithChineseTemplate].content.length > 0);
    TM_ASSERT_TRUE([TMDocument documentWithBlankTemplate].content.length > 0);
}

TM_TEST(test_unnamed_document_display_name) {
    TMDocument *doc = [TMDocument documentWithBlankTemplate];
    TM_ASSERT_NIL(doc.fileURL);
    TM_ASSERT_EQ_STR(doc.displayName, @"未命名文档.tex");
}

TM_TEST(test_scratch_save_keeps_document_unnamed_and_dirty) {
    TMDocument *doc = [TMDocument documentWithBlankTemplate];
    doc.isDirty = YES;
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tmtest_scratch.tex"]];
    TM_ASSERT_TRUE([doc saveScratchToURL:tmp error:NULL]);
    TM_ASSERT_TRUE(doc.isScratch);
    TM_ASSERT_TRUE(doc.isDirty);
    TM_ASSERT_EQ_STR(doc.displayName, @"未命名文档.tex");
    TM_ASSERT_TRUE(doc.fileURL != nil);
}

TM_TEST(test_real_save_clears_scratch_and_dirty) {
    TMDocument *doc = [TMDocument documentWithBlankTemplate];
    NSURL *tmp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tmtest_scratch2.tex"]];
    [doc saveScratchToURL:tmp error:NULL];
    doc.isDirty = YES;
    NSURL *real = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"tmtest_real.tex"]];
    TM_ASSERT_TRUE([doc saveToURL:real error:NULL]);
    TM_ASSERT_TRUE(!doc.isScratch);
    TM_ASSERT_TRUE(!doc.isDirty);
    TM_ASSERT_EQ_STR(doc.displayName, @"tmtest_real.tex");
}

TM_TEST(test_clean_auxiliary_files_removes_aux_keeps_pdf_and_tex) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmtest_clean"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:dir error:nil];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *name in @[@"main.tex", @"main.pdf", @"main.aux", @"main.bbl", @"main.synctex.gz", @"main.run.xml", @"other.aux"]) {
        [@"x" writeToFile:[dir stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:@"main.tex"]]];
    TM_ASSERT_TRUE([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.tex"]]);
    TM_ASSERT_TRUE([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.pdf"]]);
    TM_ASSERT_TRUE([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"other.aux"]]);
    TM_ASSERT_TRUE(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.aux"]]);
    TM_ASSERT_TRUE(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.bbl"]]);
    TM_ASSERT_TRUE(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.synctex.gz"]]);
    TM_ASSERT_TRUE(![fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"main.run.xml"]]);
}

TM_TEST(test_recent_folders_are_separate_from_files_and_cleared_together) {
    [TMRecentFiles clear];
    [TMRecentFiles noteFileURL:[NSURL fileURLWithPath:@"/tmp/a.tex"]];
    [TMRecentFiles noteFolderURL:[NSURL fileURLWithPath:@"/tmp/proj"]];
    [TMRecentFiles noteFolderURL:[NSURL fileURLWithPath:@"/tmp/proj2/"]];
    [TMRecentFiles noteFolderURL:[NSURL fileURLWithPath:@"/tmp/proj"]];
    TM_ASSERT_EQ_INT([TMRecentFiles recentFileURLs].count, 1);
    TM_ASSERT_EQ_INT([TMRecentFiles recentFolderURLs].count, 2);
    TM_ASSERT_EQ_STR([TMRecentFiles recentFolderURLs].firstObject.path, @"/tmp/proj");
    [TMRecentFiles removeFolderURL:[NSURL fileURLWithPath:@"/tmp/proj"]];
    TM_ASSERT_EQ_INT([TMRecentFiles recentFolderURLs].count, 1);
    [TMRecentFiles clear];
    TM_ASSERT_EQ_INT([TMRecentFiles recentFolderURLs].count, 0);
    TM_ASSERT_EQ_INT([TMRecentFiles recentFileURLs].count, 0);
}

#pragma mark - TMEditActions

TM_TEST(test_toggle_comment_adds_prefix_to_every_line) {
    TM_ASSERT_EQ_STR([TMEditActions toggledCommentForLines:@"a\n  b\n"], @"% a\n%   b\n");
}

TM_TEST(test_toggle_comment_removes_prefix_when_all_nonblank_lines_commented) {
    TM_ASSERT_EQ_STR([TMEditActions toggledCommentForLines:@"% a\n\n  %b\n"], @"a\n\n  b\n");
}

TM_TEST(test_toggle_comment_mixed_lines_comments_everything) {
    TM_ASSERT_EQ_STR([TMEditActions toggledCommentForLines:@"% a\nb"], @"% % a\n% b");
}

TM_TEST(test_toggle_comment_blank_lines_stay_blank) {
    TM_ASSERT_EQ_STR([TMEditActions toggledCommentForLines:@"a\n\nb"], @"% a\n\n% b");
}

TM_TEST(test_indent_lines) {
    TM_ASSERT_EQ_STR([TMEditActions indentedLines:@"a\n\nb\n" indent:@"  "], @"  a\n\n  b\n");
}

TM_TEST(test_outdent_lines_removes_up_to_width_spaces_or_one_tab) {
    TM_ASSERT_EQ_STR([TMEditActions outdentedLines:@"    a\n b\n\tc\nd" width:2], @"  a\nb\nc\nd");
}

TM_TEST(test_environment_to_close) {
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInLine:@"  \\begin{itemize}"], @"itemize");
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInLine:@"\\begin{align*}"], @"align*");
    TM_ASSERT_NIL([TMEditActions environmentToCloseInLine:@"\\begin{x} text \\end{x}"]);
    TM_ASSERT_NIL([TMEditActions environmentToCloseInLine:@"% \\begin{x}"]);
    TM_ASSERT_NIL([TMEditActions environmentToCloseInLine:@"plain text"]);
}

TM_TEST(test_leading_whitespace) {
    TM_ASSERT_EQ_STR([TMEditActions leadingWhitespaceOfLine:@"  \t x"], @"  \t ");
    TM_ASSERT_EQ_STR([TMEditActions leadingWhitespaceOfLine:@"x"], @"");
}

#pragma mark - TMMagicComments

TM_TEST(test_magic_comments_program_and_root) {
    NSDictionary *m = [TMMagicComments magicCommentsInString:@"% !TEX program = xelatex\n%!TEX root=../main.tex\n\\documentclass{article}"];
    TM_ASSERT_EQ_STR(m[@"program"], @"xelatex");
    TM_ASSERT_EQ_STR(m[@"root"], @"../main.tex");
}

TM_TEST(test_magic_comments_case_insensitive_and_tolerant_spacing) {
    NSDictionary *m = [TMMagicComments magicCommentsInString:@"%  !tex  PROGRAM  =  PdfLaTeX  \n"];
    TM_ASSERT_EQ_STR(m[@"program"], @"PdfLaTeX");
}

TM_TEST(test_magic_comments_ignored_after_30_lines) {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 31; i++) [s appendString:@"% filler\n"];
    [s appendString:@"% !TEX program = xelatex\n"];
    TM_ASSERT_NIL([TMMagicComments magicCommentsInString:s][@"program"]);
}

TM_TEST(test_root_file_url_resolves_relative_to_document) {
    NSURL *doc = [NSURL fileURLWithPath:@"/tmp/proj/chapters/ch1.tex"];
    NSURL *root = [TMMagicComments rootFileURLForDocumentURL:doc content:@"% !TEX root = ../main.tex\n"];
    TM_ASSERT_EQ_STR(root.path, @"/tmp/proj/main.tex");
    TM_ASSERT_NIL([TMMagicComments rootFileURLForDocumentURL:doc content:@"no magic here"]);
}

#pragma mark - TMLogParser

TM_TEST(test_log_parser_error_with_line) {
    NSString *log = @"! Undefined control sequence.\nl.12 \\foo\n             bar\n";
    NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:log];
    TM_ASSERT_EQ_INT(issues.count, 1);
    TM_ASSERT_EQ_INT(issues[0].kind, TMLogIssueError);
    TM_ASSERT_EQ_STR(issues[0].message, @"Undefined control sequence.");
    TM_ASSERT_EQ_INT(issues[0].line, 12);
}

TM_TEST(test_log_parser_warnings_and_bad_boxes) {
    NSString *log =
        @"LaTeX Warning: Reference `fig:x' on page 1 undefined on input line 7.\n"
        @"Overfull \\hbox (12.3pt too wide) in paragraph at lines 20--21\n"
        @"Package hyperref Warning: Token not allowed in a PDF string on input line 3.\n"
        @"Underfull \\vbox (badness 10000) has occurred while \\output is active\n";
    NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:log];
    TM_ASSERT_EQ_INT(issues.count, 4);
    TM_ASSERT_EQ_INT(issues[0].kind, TMLogIssueWarning);
    TM_ASSERT_EQ_INT(issues[0].line, 7);
    TM_ASSERT_EQ_INT(issues[1].kind, TMLogIssueBadBox);
    TM_ASSERT_EQ_INT(issues[1].line, 20);
    TM_ASSERT_EQ_INT(issues[2].kind, TMLogIssueWarning);
    TM_ASSERT_EQ_INT(issues[2].line, 3);
    TM_ASSERT_EQ_INT(issues[3].kind, TMLogIssueBadBox);
    TM_ASSERT_EQ_INT(issues[3].line, 0);
}

TM_TEST(test_log_parser_first_error_helper) {
    NSString *log = @"LaTeX Warning: x\n! Missing $ inserted.\n<inserted text>\nl.5 a_b\n! Second error.\nl.9\n";
    NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:log];
    TMLogIssue *first = [TMLogParser firstErrorInIssues:issues];
    TM_ASSERT_EQ_STR(first.message, @"Missing $ inserted.");
    TM_ASSERT_EQ_INT(first.line, 5);
    TM_ASSERT_EQ_INT([TMLogParser countOfKind:TMLogIssueError inIssues:issues], 2);
    TM_ASSERT_EQ_INT([TMLogParser countOfKind:TMLogIssueWarning inIssues:issues], 1);
}

TM_TEST(test_log_parser_file_line_error_format) {
    NSString *log = @"./sample/test.tex:15: Undefined control sequence.\nl.15 \\foo\n\n./sample/test.tex:20: Missing $ inserted.\n";
    NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:log];
    TM_ASSERT_EQ_INT(issues.count, 2);
    TM_ASSERT_EQ_INT(issues[0].kind, TMLogIssueError);
    TM_ASSERT_EQ_INT(issues[0].line, 15);
    TM_ASSERT_EQ_STR(issues[0].message, @"Undefined control sequence.");
    TM_ASSERT_EQ_STR(issues[0].filePath, @"./sample/test.tex");
    TM_ASSERT_EQ_INT(issues[1].line, 20);
}

TM_TEST(test_log_parser_native_error_has_no_file_path_and_kind_labels) {
    NSArray<TMLogIssue *> *issues = [TMLogParser issuesFromLog:@"! Missing $ inserted.\nl.5 a_b\nOverfull \\hbox (1pt too wide) in paragraph at lines 20--21\n"];
    TM_ASSERT_EQ_INT(issues.count, 2);
    TM_ASSERT_NIL(issues[0].filePath);
    TM_ASSERT_EQ_STR(issues[0].kindLabel, @"错误");
    TM_ASSERT_EQ_STR(issues[1].kindLabel, @"坏盒子");
    TM_ASSERT_EQ_INT(issues[1].line, 20);
}

#pragma mark - TMRecentFiles

TM_TEST(test_preferences_argument_splitting_handles_quotes_and_whitespace) {
    NSArray *args = [TMPreferences argumentsFromString:@"  -outdir=build   -bibtex \"-usepretex=\\def\\x{1 2}\"\n-g"];
    TM_ASSERT_EQ_INT(args.count, 4);
    TM_ASSERT_EQ_STR(args[0], @"-outdir=build");
    TM_ASSERT_EQ_STR(args[2], @"-usepretex=\\def\\x{1 2}");
    TM_ASSERT_EQ_STR(args[3], @"-g");
    TM_ASSERT_EQ_INT([TMPreferences argumentsFromString:@"   "].count, 0);
}

TM_TEST(test_compiler_arguments_include_shell_escape_and_extras_before_filename) {
    NSArray *args = [TMCompiler argumentsForEngineName:@"xelatex" useLatexmk:YES workingDir:@"/w" fileName:@"m.tex"
                                            shellEscape:YES extraArguments:@[@"-outdir=build", @""]];
    TM_ASSERT_EQ_STR(args.firstObject, @"-xelatex");
    TM_ASSERT_TRUE([args containsObject:@"-shell-escape"]);
    TM_ASSERT_TRUE([args containsObject:@"-outdir=build"]);
    TM_ASSERT_EQ_STR(args.lastObject, @"m.tex");
    TM_ASSERT_EQ_INT([args indexOfObject:@"-shell-escape"] < [args indexOfObject:@"-outdir=build"], 1);

    NSArray *plain = [TMCompiler argumentsForEngineName:@"pdflatex" useLatexmk:NO workingDir:@"/w" fileName:@"m.tex"
                                             shellEscape:NO extraArguments:nil];
    TM_ASSERT_TRUE(![plain containsObject:@"-shell-escape"]);
    TM_ASSERT_TRUE(![plain containsObject:@"-pdf"]);
    TM_ASSERT_EQ_STR(plain.firstObject, @"-synctex=1");
    TM_ASSERT_EQ_STR([TMCompiler argumentsForEngineName:@"lualatex" useLatexmk:YES workingDir:@"/w" fileName:@"m.tex" shellEscape:NO extraArguments:nil].firstObject, @"-lualatex");
}

TM_TEST(test_recent_files_most_recent_first_and_deduplicated) {
    [TMRecentFiles clear];
    [TMRecentFiles noteFileURL:[NSURL fileURLWithPath:@"/tmp/a.tex"]];
    [TMRecentFiles noteFileURL:[NSURL fileURLWithPath:@"/tmp/b.tex"]];
    [TMRecentFiles noteFileURL:[NSURL fileURLWithPath:@"/tmp/a.tex"]];
    NSArray<NSURL *> *urls = [TMRecentFiles recentFileURLs];
    TM_ASSERT_EQ_INT(urls.count, 2);
    TM_ASSERT_EQ_STR(urls[0].path, @"/tmp/a.tex");
    TM_ASSERT_EQ_STR(urls[1].path, @"/tmp/b.tex");
}

TM_TEST(test_recent_files_capped_at_ten_and_removable) {
    [TMRecentFiles clear];
    for (int i = 0; i < 12; i++) {
        [TMRecentFiles noteFileURL:[NSURL fileURLWithPath:[NSString stringWithFormat:@"/tmp/f%d.tex", i]]];
    }
    TM_ASSERT_EQ_INT([TMRecentFiles recentFileURLs].count, 10);
    TM_ASSERT_EQ_STR([TMRecentFiles recentFileURLs][0].path, @"/tmp/f11.tex");
    [TMRecentFiles removeFileURL:[NSURL fileURLWithPath:@"/tmp/f11.tex"]];
    TM_ASSERT_EQ_STR([TMRecentFiles recentFileURLs][0].path, @"/tmp/f10.tex");
    [TMRecentFiles clear];
    TM_ASSERT_EQ_INT([TMRecentFiles recentFileURLs].count, 0);
}

#pragma mark - TMProject

static NSURL *tm_makeTempProject(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"tmproj-%@", NSUUID.UUID.UUIDString]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"chapters"] withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:[dir stringByAppendingPathComponent:@"build"] withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *files = @{
        @"main.tex": @"\\documentclass{article}\n\\begin{document}\n\\input{chapters/intro}\n\\include{chapters/method}\n\\end{document}\n",
        @"notes.tex": @"% \\documentclass{article} 被注释掉了，不算主文件\nsome notes\n",
        @"chapters/intro.tex": @"\\section{Intro}\n",
        @"chapters/method.tex": @"\\section{Method}\n",
        @"refs.bib": @"@article{a, title={T}}\n",
        @"main.pdf": @"%PDF-1.4 fake\n",
        @"main.aux": @"aux\n",
        @"figure.pdf": @"%PDF-1.4 fig\n",
        @"build/junk.tex": @"\\documentclass{article}\n",
    };
    for (NSString *rel in files) {
        [files[rel] writeToFile:[dir stringByAppendingPathComponent:rel] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return [NSURL fileURLWithPath:dir];
}

TM_TEST(test_project_editable_extensions) {
    TM_ASSERT_TRUE([TMProject isEditableFileURL:[NSURL fileURLWithPath:@"/x/a.tex"]]);
    TM_ASSERT_TRUE([TMProject isEditableFileURL:[NSURL fileURLWithPath:@"/x/refs.BIB"]]);
    TM_ASSERT_TRUE([TMProject isEditableFileURL:[NSURL fileURLWithPath:@"/x/my.cls"]]);
    TM_ASSERT_TRUE(![TMProject isEditableFileURL:[NSURL fileURLWithPath:@"/x/fig.png"]]);
    TM_ASSERT_TRUE(![TMProject isEditableFileURL:[NSURL fileURLWithPath:@"/x/noext"]]);
}

TM_TEST(test_project_main_file_from_chapter_via_input) {
    NSURL *root = tm_makeTempProject();
    NSURL *intro = [root URLByAppendingPathComponent:@"chapters/intro.tex"];
    NSURL *main = [TMProject mainFileURLForDocumentURL:intro content:@"\\section{Intro}\n"];
    TM_ASSERT_EQ_STR(main.lastPathComponent, @"main.tex");
    NSURL *method = [root URLByAppendingPathComponent:@"chapters/method.tex"];
    main = [TMProject mainFileURLForDocumentURL:method content:@"\\section{Method}\n"];
    TM_ASSERT_EQ_STR(main.lastPathComponent, @"main.tex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_main_file_self_when_declares_documentclass) {
    NSURL *root = tm_makeTempProject();
    NSURL *mainURL = [root URLByAppendingPathComponent:@"main.tex"];
    NSString *content = [NSString stringWithContentsOfURL:mainURL encoding:NSUTF8StringEncoding error:nil];
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:mainURL content:content].path, mainURL.path);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_main_file_magic_root_wins) {
    NSURL *root = tm_makeTempProject();
    NSURL *notes = [root URLByAppendingPathComponent:@"notes.tex"];
    NSURL *main = [TMProject mainFileURLForDocumentURL:notes content:@"% !TEX root = main.tex\nhi\n"];
    TM_ASSERT_EQ_STR(main.lastPathComponent, @"main.tex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_main_file_single_candidate_in_same_dir) {
    NSURL *root = tm_makeTempProject();
    // notes.tex 没引用 orphan.tex，但目录里只有 main.tex 一个候选 → 用它
    NSURL *orphan = [root URLByAppendingPathComponent:@"orphan.tex"];
    [@"text" writeToURL:orphan atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:orphan content:@"text"].lastPathComponent, @"main.tex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_guess_main_in_directory_ignores_commented_documentclass) {
    NSURL *root = tm_makeTempProject();
    TM_ASSERT_EQ_STR([TMProject guessMainFileInDirectory:root].lastPathComponent, @"main.tex");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_file_tree_filters_aux_build_and_twin_pdf) {
    NSURL *root = tm_makeTempProject();
    NSArray<TMFileNode *> *tree = [TMProject fileTreeForDirectory:root maxDepth:3];
    NSMutableArray *names = [NSMutableArray array];
    for (TMFileNode *n in tree) [names addObject:n.name];
    // 目录优先；build/ 被忽略；main.aux 不显示；main.pdf 与 main.tex 同名不显示；figure.pdf 显示
    TM_ASSERT_EQ_STR([names componentsJoinedByString:@","], @"chapters,figure.pdf,main.tex,notes.tex,refs.bib");
    TM_ASSERT_TRUE(tree[0].isDirectory);
    TM_ASSERT_EQ_INT(tree[0].children.count, 2);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

#pragma mark - TMCompletionProvider

TM_TEST(test_completion_context_cite_partial_after_comma) {
    NSString *text = @"see \\cite{knuth84, lam";
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:text cursorLocation:text.length];
    TM_ASSERT_EQ_INT(ctx.kind, TMCompletionKindCitation);
    TM_ASSERT_EQ_STR(ctx.partial, @"lam");
    TM_ASSERT_EQ_INT(ctx.partialRange.location, text.length - 3);
}

TM_TEST(test_completion_context_ref_with_optional_arg_and_empty_partial) {
    NSString *text = @"\\autoref{}";
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:text cursorLocation:9]; // 在 { 与 } 之间
    TM_ASSERT_EQ_INT(ctx.kind, TMCompletionKindReference);
    TM_ASSERT_EQ_STR(ctx.partial, @"");
    NSString *t2 = @"\\cref[opt]{fig:";
    ctx = [TMCompletionProvider contextInText:t2 cursorLocation:t2.length];
    TM_ASSERT_EQ_INT(ctx.kind, TMCompletionKindReference);
    TM_ASSERT_EQ_STR(ctx.partial, @"fig:");
}

TM_TEST(test_completion_context_begin_and_command) {
    NSString *text = @"  \\begin{ite";
    TMCompletionContext *ctx = [TMCompletionProvider contextInText:text cursorLocation:text.length];
    TM_ASSERT_EQ_INT(ctx.kind, TMCompletionKindEnvironment);
    TM_ASSERT_EQ_STR(ctx.partial, @"ite");

    NSString *cmd = @"hello \\sec";
    ctx = [TMCompletionProvider contextInText:cmd cursorLocation:cmd.length];
    TM_ASSERT_EQ_INT(ctx.kind, TMCompletionKindCommand);
    TM_ASSERT_EQ_STR(ctx.partial, @"\\sec");
    TM_ASSERT_EQ_INT(ctx.partialRange.location, 6);

    // 普通单词、转义反斜杠、非补全命令的参数 → None
    NSString *plain = @"hello wor";
    TM_ASSERT_EQ_INT([TMCompletionProvider contextInText:plain cursorLocation:plain.length].kind, TMCompletionKindNone);
    NSString *tb = @"\\textbf{bo";
    TM_ASSERT_EQ_INT([TMCompletionProvider contextInText:tb cursorLocation:tb.length].kind, TMCompletionKindNone);
}

TM_TEST(test_completion_scanners) {
    NSArray *labels = [TMCompletionProvider labelsInText:@"\\label{sec:intro} text \\label{ eq:main } \\label{sec:intro}"];
    TM_ASSERT_EQ_STR([labels componentsJoinedByString:@","], @"sec:intro,eq:main");

    NSArray *keys = [TMCompletionProvider citationKeysInBibText:
                     @"@comment{ignored,}\n@Article{knuth84,\n title={x}}\n@book( lamport94 , title={y})\n@string{foo = \"bar\"}"];
    TM_ASSERT_EQ_STR([keys componentsJoinedByString:@","], @"knuth84,lamport94");

    NSArray *envs = [TMCompletionProvider environmentsInText:@"\\begin{align*} \\begin{itemize}"];
    TM_ASSERT_EQ_STR([envs componentsJoinedByString:@","], @"align*,itemize");

    NSArray *cmds = [TMCompletionProvider commandsInText:@"\\newcommand{\\myvec}[1]{..} \\section{a} \\a"];
    TM_ASSERT_TRUE([cmds containsObject:@"myvec"]);
    TM_ASSERT_TRUE([cmds containsObject:@"section"]);
    TM_ASSERT_TRUE(![cmds containsObject:@"a"]);
}

TM_TEST(test_completion_candidates_filter_and_prefix_first) {
    TMCompletionProvider *p = [[TMCompletionProvider alloc] init]; // 无项目目录
    NSString *doc = @"\\label{fig:setup}\\label{sec:figures}\\label{tab:data}";
    TMCompletionContext *ctx = [[TMCompletionContext alloc] init];
    ctx.kind = TMCompletionKindReference;
    ctx.partial = @"fig";
    NSArray *out = [p completionsForContext:ctx currentText:doc];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"fig:setup,sec:figures");

    ctx.kind = TMCompletionKindCommand;
    ctx.partial = @"\\sec";
    out = [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_TRUE(out.count >= 1);
    TM_ASSERT_TRUE([out[0] hasPrefix:@"\\sec"]);

    ctx.kind = TMCompletionKindEnvironment;
    ctx.partial = @"ali";
    out = [p completionsForContext:ctx currentText:@""];
    TM_ASSERT_EQ_STR([out componentsJoinedByString:@","], @"align,align*");
}

TM_TEST(test_completion_scans_project_bib_and_labels) {
    NSURL *root = tm_makeTempProject();
    [@"\\label{ch:intro}" writeToURL:[root URLByAppendingPathComponent:@"chapters/intro.tex"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TMCompletionProvider *p = [[TMCompletionProvider alloc] init];
    p.projectRootURL = root;
    TMCompletionContext *ctx = [[TMCompletionContext alloc] init];
    ctx.kind = TMCompletionKindCitation; ctx.partial = @"";
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@""] componentsJoinedByString:@","], @"a");
    ctx.kind = TMCompletionKindReference; ctx.partial = @"ch";
    TM_ASSERT_EQ_STR([[p completionsForContext:ctx currentText:@""] componentsJoinedByString:@","], @"ch:intro");
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

#pragma mark - Runner

int main(void) {
    @autoreleasepool {
        for (NSArray *entry in gTests) {
            gCurrentTest = [entry[0] UTF8String];
            int before = gFailed;
            ((TMTestFn)[entry[1] pointerValue])();
            if (gFailed == before) gPassed++;
        }
        printf("%d passed, %d failed\n", gPassed, gFailed);
    }
    return gFailed == 0 ? 0 : 1;
}
