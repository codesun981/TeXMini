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
#import "TMOutlineParser.h"
#import "TMLaTeXScanner.h"
#import "TMFontSettings.h"
#import "TMFontCatalog.h"
#import "TMMarkdownScanner.h"
#import "TMFormatActions.h"

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
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:nil];
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
    [[NSFileManager defaultManager] removeItemAtURL:tmp error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:real error:nil];
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
    [fm removeItemAtPath:dir error:nil];
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

TM_TEST(test_drop_helpers_label_slug_and_figure_snippet) {
    TM_ASSERT_EQ_STR([TMEditActions labelSlugForFileName:@"My Plot (v2).PNG"], @"my-plot-v2");
    TM_ASSERT_EQ_STR([TMEditActions labelSlugForFileName:@"___.png"], @"figure");
    NSUInteger off = 0;
    NSString *snip = [TMEditActions figureSnippetForImagePath:@"figures/a.png" label:@"a" cursorOffset:&off];
    TM_ASSERT_TRUE([snip containsString:@"\\includegraphics[width=0.8\\linewidth]{figures/a.png}"]);
    TM_ASSERT_TRUE([snip containsString:@"\\label{fig:a}"]);
    TM_ASSERT_TRUE([snip hasSuffix:@"\\end{figure}\n"]);
    TM_ASSERT_TRUE([[snip substringToIndex:off] hasSuffix:@"\\caption{"]);
    TM_ASSERT_EQ_INT([snip characterAtIndex:off], '}');
}

TM_TEST(test_graphicx_insertion_location) {
    NSString *withPkg = @"\\documentclass{article}\n\\usepackage[final]{graphicx}\n\\begin{document}\n";
    TM_ASSERT_EQ_INT([TMEditActions graphicxInsertionLocationInContent:withPkg], NSNotFound);
    NSString *combined = @"\\documentclass{article}\n\\usepackage{amsmath,graphicx}\n";
    TM_ASSERT_EQ_INT([TMEditActions graphicxInsertionLocationInContent:combined], NSNotFound);
    NSString *without = @"% comment\n\\documentclass[11pt]{article} % opts\n\\usepackage{amsmath}\n";
    NSUInteger loc = [TMEditActions graphicxInsertionLocationInContent:without];
    TM_ASSERT_EQ_STR([without substringFromIndex:loc], @"\\usepackage{amsmath}\n");
    TM_ASSERT_EQ_INT([TMEditActions graphicxInsertionLocationInContent:@"no class here"], NSNotFound);
}

TM_TEST(test_relative_path_from_directory) {
    NSURL *dir = [NSURL fileURLWithPath:@"/tmp/proj"];
    TM_ASSERT_EQ_STR([TMEditActions relativePathFromDirectory:dir toFile:[NSURL fileURLWithPath:@"/tmp/proj/figs/a.png"]], @"figs/a.png");
    TM_ASSERT_EQ_STR([TMEditActions relativePathFromDirectory:[NSURL fileURLWithPath:@"/tmp/proj/"] toFile:[NSURL fileURLWithPath:@"/tmp/proj/a.png"]], @"a.png");
    TM_ASSERT_NIL([TMEditActions relativePathFromDirectory:dir toFile:[NSURL fileURLWithPath:@"/tmp/projects/a.png"]]);
    TM_ASSERT_NIL([TMEditActions relativePathFromDirectory:dir toFile:[NSURL fileURLWithPath:@"/Users/x/a.png"]]);
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

TM_TEST(test_preferences_autosave_and_restore_default_on) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"TMAutoSave"];
    [d removeObjectForKey:@"TMRestoreLastSession"];
    [TMPreferences registerDefaults];
    TM_ASSERT_TRUE([TMPreferences shared].autoSaveEnabled);
    TM_ASSERT_TRUE([TMPreferences shared].restoreLastSession);
    [TMPreferences shared].autoSaveEnabled = NO;
    TM_ASSERT_TRUE(![TMPreferences shared].autoSaveEnabled);
    [d removeObjectForKey:@"TMAutoSave"];
}

TM_TEST(test_combined_sidebar_preference_defaults_off_and_persists) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:@"TMCombinedSidebar"];
    [TMPreferences registerDefaults];
    TM_ASSERT_TRUE(![TMPreferences shared].combinedSidebar);
    [TMPreferences shared].combinedSidebar = YES;
    TM_ASSERT_TRUE([d boolForKey:@"TMCombinedSidebar"]);
    TM_ASSERT_TRUE([TMPreferences shared].combinedSidebar);
    [d removeObjectForKey:@"TMCombinedSidebar"];
}

TM_TEST(test_session_round_trip_and_missing_paths) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *file = [dir stringByAppendingPathComponent:@"main.tex"];
    [@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [TMRecentFiles noteSessionFolderURL:[NSURL fileURLWithPath:dir] fileURL:[NSURL fileURLWithPath:file] selection:42];
    TM_ASSERT_EQ_STR([TMRecentFiles sessionFolderURL].URLByStandardizingPath.path, [NSURL fileURLWithPath:dir].URLByStandardizingPath.path);
    TM_ASSERT_EQ_STR([TMRecentFiles sessionFileURL].lastPathComponent, @"main.tex");
    TM_ASSERT_EQ_INT([TMRecentFiles sessionSelection], 42);

    // 文件夹当文件用、文件被删：都视为不存在
    [TMRecentFiles noteSessionFolderURL:[NSURL fileURLWithPath:file] fileURL:[NSURL fileURLWithPath:file] selection:0];
    TM_ASSERT_NIL([TMRecentFiles sessionFolderURL]);
    [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    TM_ASSERT_NIL([TMRecentFiles sessionFileURL]);

    [TMRecentFiles noteSessionFolderURL:[NSURL fileURLWithPath:@"/tmp"] fileURL:nil selection:3];
    [TMRecentFiles clear];
    TM_ASSERT_NIL([TMRecentFiles sessionFolderURL]);
    TM_ASSERT_EQ_INT([TMRecentFiles sessionSelection], 0);
}

TM_TEST(test_compiler_arguments_include_shell_escape_and_extras_before_filename) {
    NSArray *args = [TMCompiler argumentsForEngineName:@"xelatex" useLatexmk:YES outputDir:@"/w" auxDir:nil fileName:@"m.tex"
                                            shellEscape:YES extraArguments:@[@"-outdir=build", @""]];
    TM_ASSERT_EQ_STR(args.firstObject, @"-xelatex");
    TM_ASSERT_TRUE([args containsObject:@"-shell-escape"]);
    TM_ASSERT_TRUE([args containsObject:@"-outdir=build"]);
    TM_ASSERT_EQ_STR(args.lastObject, @"m.tex");
    TM_ASSERT_EQ_INT([args indexOfObject:@"-shell-escape"] < [args indexOfObject:@"-outdir=build"], 1);

    NSArray *plain = [TMCompiler argumentsForEngineName:@"pdflatex" useLatexmk:NO outputDir:@"/w" auxDir:nil fileName:@"m.tex"
                                             shellEscape:NO extraArguments:nil];
    TM_ASSERT_TRUE(![plain containsObject:@"-shell-escape"]);
    TM_ASSERT_TRUE(![plain containsObject:@"-pdf"]);
    TM_ASSERT_EQ_STR(plain.firstObject, @"-synctex=1");
    TM_ASSERT_EQ_STR([TMCompiler argumentsForEngineName:@"lualatex" useLatexmk:YES outputDir:@"/w" auxDir:nil fileName:@"m.tex" shellEscape:NO extraArguments:nil].firstObject, @"-lualatex");
}

TM_TEST(test_compiler_arguments_separate_aux_dir) {
    NSArray *mk = [TMCompiler argumentsForEngineName:@"pdflatex" useLatexmk:YES outputDir:@"/src" auxDir:@"/cache/m" fileName:@"m.tex"
                                          shellEscape:NO extraArguments:nil];
    TM_ASSERT_TRUE([mk containsObject:@"-outdir=/src"]);
    TM_ASSERT_TRUE([mk containsObject:@"-auxdir=/cache/m"]);

    // 引擎直跑只有一个输出目录：全部进缓存
    NSArray *plain = [TMCompiler argumentsForEngineName:@"pdflatex" useLatexmk:NO outputDir:@"/src" auxDir:@"/cache/m" fileName:@"m.tex"
                                             shellEscape:NO extraArguments:nil];
    TM_ASSERT_TRUE([plain containsObject:@"-output-directory=/cache/m"]);

    NSArray *beside = [TMCompiler argumentsForEngineName:@"pdflatex" useLatexmk:YES outputDir:@"/src" auxDir:nil fileName:@"m.tex"
                                              shellEscape:NO extraArguments:nil];
    TM_ASSERT_TRUE(![[beside componentsJoinedByString:@" "] containsString:@"-auxdir"]);
}

TM_TEST(test_aux_directory_is_per_path_and_in_caches) {
    NSURL *a = [TMCompiler auxiliaryDirectoryForTeXFileURL:[NSURL fileURLWithPath:@"/p1/main.tex"]];
    NSURL *b = [TMCompiler auxiliaryDirectoryForTeXFileURL:[NSURL fileURLWithPath:@"/p2/main.tex"]];
    TM_ASSERT_TRUE(![a isEqual:b]);
    TM_ASSERT_TRUE([a.path containsString:@"/Caches/TeXMini/build/main-"]);
    TM_ASSERT_TRUE([a isEqual:[TMCompiler auxiliaryDirectoryForTeXFileURL:[NSURL fileURLWithPath:@"/p1/main.tex"]]]);
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

#pragma mark - 大纲与高亮

TM_TEST(test_outline_follows_custom_heading_macros) {
    NSString *tex = @"\\newcommand{\\mychapter}[1]{\\section*{#1}\\addcontentsline{toc}{section}{#1}}\n"
                    @"\\newcommand{\\mysub}[1]{\\subsection*{#1}}\n"
                    @"\\newcommand{\\mysubsub}[1]{\\subsubsection*{#1}}\n"
                    @"\\newcommand{\\note}[1]{\\textbf{#1}}\n"
                    @"\\begin{document}\n"
                    @"\\mychapter{一、问题重述}\n"
                    @"\\mysub{1.1 背景}\n"
                    @"\\mysubsub{1.1.1 细节}\n"
                    @"\\note{不是标题}\n"
                    @"\\section{Plain}\n";
    NSArray<TMOutlineItem *> *flat = nil;
    [TMOutlineParser parseOutlineFromLaTeXString:tex flatList:&flat];
    TM_ASSERT_EQ_INT(flat.count, 4);
    TM_ASSERT_EQ_STR(flat[0].title, @"一、问题重述");
    TM_ASSERT_EQ_INT(flat[0].level, TMOutlineLevelSection);
    TM_ASSERT_EQ_STR(flat[1].title, @"1.1 背景");
    TM_ASSERT_EQ_INT(flat[1].level, TMOutlineLevelSubsection);
    TM_ASSERT_EQ_INT(flat[2].level, TMOutlineLevelSubsubsection);
    TM_ASSERT_EQ_INT(flat[2].lineNumber, 8);
    TM_ASSERT_EQ_STR(flat[3].title, @"Plain");
}

/// 扫描结果里某一类区域对应的文本
static NSString *tm_regions(NSString *t, TMLaTeXRegionKind kind) {
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:t];
    NSMutableArray *found = [NSMutableArray array];
    for (NSUInteger i = 0; i < scan.regionCount; i++) {
        if (scan.regions[i].kind == kind) [found addObject:[t substringWithRange:scan.regions[i].range]];
    }
    return [found componentsJoinedByString:@","];
}

static NSString *tm_outlineTitles(NSString *t) {
    NSArray<TMOutlineItem *> *flat = nil;
    [TMOutlineParser parseOutlineFromLaTeXString:t flatList:&flat];
    NSMutableArray *titles = [NSMutableArray array];
    for (TMOutlineItem *item in flat) [titles addObject:item.title];
    return [titles componentsJoinedByString:@","];
}

TM_TEST(test_scanner_dollar_math_pairs_like_tex) {
    // $a$$b$ 是两段行内公式；\$ 与注释里的 $ 不算；空行结束未闭合的 $
    NSString *t = @"x $a$$b$ y \\$5 % $ in comment\n$$c$$\nopen $ oops\n\nlater $d$";
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionMath), @"$a$,$b$,$$c$$,$d$");
}

TM_TEST(test_scanner_verbatim_and_verb_do_not_leak) {
    NSString *t = @"\\begin{verbatim}\nprice $5 % not comment\n\\end{verbatim}\nsee \\verb|$%| then $y$ and \\url{a.com/%20} $z$\n";
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionMath), @"$y$,$z$");
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionComment), @"");
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionVerbatim), @"\nprice $5 % not comment\n,\\verb|$%|");
}

TM_TEST(test_scanner_math_environments_and_brackets) {
    NSString *t = @"a \\[x\\] b \\(y\\)\n\\begin{align*}\nz \\\\[4pt] w\n\\end{align*}\nrow \\\\[2pt] next\n";
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionMath), @"\\[x\\],\\(y\\),\\begin{align*}\nz \\\\[4pt] w\n\\end{align*}");
}

TM_TEST(test_scanner_definition_body_does_not_open_environments) {
    // 定义体里的 \begin{equation} 不能让后面整篇变成公式
    NSString *t = @"\\newcommand{\\be}{\\begin{equation}}\n\\newcommand{\\ee}{\\end{equation}}\ntext $q$\n";
    TM_ASSERT_EQ_STR(tm_regions(t, TMLaTeXRegionMath), @"$q$");
}

TM_TEST(test_scanner_ignorable_lookup) {
    NSString *t = @"{a} % {b}\n\\verb|{|";
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:t];
    TM_ASSERT_TRUE(![scan isIgnorableAtIndex:0]);
    TM_ASSERT_TRUE([scan isIgnorableAtIndex:[t rangeOfString:@"{b}"].location]);
    TM_ASSERT_TRUE([scan isIgnorableAtIndex:t.length - 2]);
}

TM_TEST(test_outline_short_titles_verbatim_and_beamer) {
    TM_ASSERT_EQ_STR(tm_outlineTitles(@"\\section[短]{很长的标题}\n"), @"很长的标题");
    TM_ASSERT_EQ_STR(tm_outlineTitles(@"\\begin{verbatim}\n\\section{假的}\n\\end{verbatim}\n\\section{真的}\n"), @"真的");
    TM_ASSERT_EQ_STR(tm_outlineTitles(@"% \\section{注释里}\n\\section{A}\n"), @"A");
    TM_ASSERT_EQ_STR(tm_outlineTitles(@"\\section{S}\n\\begin{frame}[t]{帧一}\n\\end{frame}\n\\begin{frame}\n\\frametitle{帧二}\n\\end{frame}\n"), @"S,帧一,帧二");
    TM_ASSERT_EQ_STR(tm_outlineTitles(@"\\newcommand\\mysec[1]{\\section{#1}}\n\\mysec{A}\n"), @"A");
}

#pragma mark - TMFontSettings

static TMDocumentFontSettings *tm_fonts(NSString *latin, NSString *cjk, NSString *size) {
    TMDocumentFontSettings *s = [[TMDocumentFontSettings alloc] init];
    s.latinFont = latin;
    s.cjkFont = cjk;
    s.sizeOption = size;
    return s;
}

TM_TEST(test_fonts_read_settings_ignores_comments) {
    NSString *t = @"\\documentclass[UTF8,zihao=-4]{ctexart}\n% \\setmainfont{Arial}\n\\setmainfont[Ligatures=TeX]{Times New Roman}\n"
                  @"\\setCJKmainfont{Songti SC}\n\\begin{document}\n\\setmainfont{Late}\n\\end{document}\n";
    TMDocumentFontSettings *s = [TMFontSettings settingsInContent:t];
    TM_ASSERT_EQ_STR(s.latinFont, @"Times New Roman");
    TM_ASSERT_EQ_STR(s.cjkFont, @"Songti SC");
    TM_ASSERT_EQ_STR(s.sizeOption, @"zihao=-4");
    TM_ASSERT_TRUE([TMFontSettings isCTeXContent:t]);
    TMDocumentFontSettings *none = [TMFontSettings settingsInContent:@"\\documentclass{article}\n\\begin{document}\n\\end{document}\n"];
    TM_ASSERT_NIL(none.latinFont);
    TM_ASSERT_NIL(none.sizeOption);
}

TM_TEST(test_fonts_apply_to_plain_article_adds_xecjk) {
    NSString *t = @"\\documentclass{article}\n\\usepackage{amsmath}\n\\begin{document}\nHi\n\\end{document}\n";
    NSString *r = [TMFontSettings contentByApplyingSettings:tm_fonts(@"Times New Roman", @"Kaiti SC", @"12pt") cjkFakeBold:NO toContent:t];
    TM_ASSERT_EQ_STR(r, @"\\documentclass[12pt]{article}\n\\usepackage{amsmath}\n\\usepackage{xeCJK}\n"
                        @"\\setmainfont{Times New Roman}\n\\setCJKmainfont{Kaiti SC}\n\\begin{document}\nHi\n\\end{document}\n");
}

TM_TEST(test_fonts_apply_latin_only_adds_fontspec) {
    NSString *t = @"\\documentclass{article}\n\\begin{document}\n\\end{document}\n";
    NSString *r = [TMFontSettings contentByApplyingSettings:tm_fonts(@"Georgia", nil, nil) cjkFakeBold:NO toContent:t];
    TM_ASSERT_EQ_STR(r, @"\\documentclass{article}\n\\usepackage{fontspec}\n\\setmainfont{Georgia}\n\\begin{document}\n\\end{document}\n");
}

TM_TEST(test_fonts_apply_ctex_updates_in_place_and_keeps_options) {
    NSString *t = @"\\documentclass[UTF8,12pt]{ctexart}\n\\setCJKmainfont[BoldFont=STHeiti]{STSong}\n\\setmainfont{Arial}\n\\begin{document}\n\\end{document}\n";
    NSString *r = [TMFontSettings contentByApplyingSettings:tm_fonts(nil, @"Songti SC", @"zihao=-4") cjkFakeBold:YES toContent:t];
    // 已有的 \setCJKmainfont 只改名、保留 BoldFont；英文字体设为默认 → 整行删掉；ctex 不需要补宏包
    TM_ASSERT_EQ_STR(r, @"\\documentclass[UTF8,zihao=-4]{ctexart}\n\\setCJKmainfont[BoldFont=STHeiti]{Songti SC}\n\\begin{document}\n\\end{document}\n");
}

TM_TEST(test_fonts_apply_fake_bold_and_default_size) {
    NSString *t = @"\\documentclass[11pt]{ctexart}\n\\begin{document}\n\\end{document}\n";
    NSString *r = [TMFontSettings contentByApplyingSettings:tm_fonts(nil, @"STKaiti", nil) cjkFakeBold:YES toContent:t];
    TM_ASSERT_EQ_STR(r, @"\\documentclass{ctexart}\n\\setCJKmainfont[AutoFakeBold]{STKaiti}\n\\begin{document}\n\\end{document}\n");
    TM_ASSERT_NIL([TMFontSettings contentByApplyingSettings:tm_fonts(@"A", nil, nil) cjkFakeBold:NO toContent:@"\\section{x}\n"]);
}

TM_TEST(test_fonts_size_options_per_class) {
    TM_ASSERT_EQ_INT([TMFontSettings sizeOptionsForDocumentClass:@"article"].count, 3);
    TM_ASSERT_TRUE([[TMFontSettings sizeOptionsForDocumentClass:@"ctexart"] containsObject:@"zihao=-4"]);
    TM_ASSERT_EQ_INT([TMFontSettings sizeOptionsForDocumentClass:@"thuthesis"].count, 0);
    TM_ASSERT_EQ_STR([TMFontSettings displayNameForSizeOption:@"zihao=-4"], @"小四（12pt）");
}

TM_TEST(test_fonts_missing_names_from_log) {
    NSString *log = @"./a.tex:4: Package fontspec Error: \n"
                    @"(fontspec)                The font \"Microsoft YaHei\" cannot be found; this\n"
                    @"(fontspec)                may be but usually is not a fontspec bug.\n"
                    @"! Font \\x=\"PingFang SC:mapping=tex-text\" at 10.0pt not loadable: Metric (TFM) file or installed font not found.\n";
    NSArray *names = [TMFontSettings missingFontNamesInLog:log];
    TM_ASSERT_EQ_INT(names.count, 2);
    TM_ASSERT_EQ_STR(names[0], @"Microsoft YaHei");
    TM_ASSERT_EQ_STR(names[1], @"PingFang SC");
    TM_ASSERT_NIL([TMFontSettings failingCTeXFontsetInLog:log]);
    NSString *ctexLog = @"(/usr/local/texlive/2026/texmf-dist/tex/latex/ctex/fontset/ctex-fontset-windows.\n"
                        @"def:101: Package fontspec Error: \n(fontspec)                The font \"SimSun\" cannot be found; this may be but\n";
    TM_ASSERT_EQ_STR([TMFontSettings failingCTeXFontsetInLog:ctexLog], @"windows");
    TM_ASSERT_EQ_STR([TMFontSettings missingFontNamesInLog:ctexLog].firstObject, @"SimSun");
}

TM_TEST(test_fonts_remove_ctex_fontset) {
    TM_ASSERT_EQ_STR([TMFontSettings contentByRemovingCTeXFontset:@"windows" inContent:@"\\documentclass[fontset=windows]{ctexart}\n"],
                     @"\\documentclass{ctexart}\n");
    TM_ASSERT_EQ_STR([TMFontSettings contentByRemovingCTeXFontset:@"windows" inContent:@"\\documentclass[UTF8, fontset = windows,12pt]{ctexart}\n"],
                     @"\\documentclass[UTF8,12pt]{ctexart}\n");
    TM_ASSERT_EQ_STR([TMFontSettings contentByRemovingCTeXFontset:@"windows" inContent:@"\\documentclass{article}\n\\usepackage[fontset=windows]{ctex}\n"],
                     @"\\documentclass{article}\n\\usepackage{ctex}\n");
    TM_ASSERT_NIL([TMFontSettings contentByRemovingCTeXFontset:@"windows" inContent:@"\\documentclass{ctexart}\n"]);
}

TM_TEST(test_fonts_replace_only_on_font_lines) {
    NSString *t = @"\\setCJKmainfont[BoldFont = SimHei, ItalicFont=KaiTi]{SimSun}\n"
                  @"\\setCJKfamilyfont{zhkai}{kaiti_gb2312.ttf}\n"
                  @"\\setCJKsansfont{Kaiti SC}\n"
                  @"正文要求使用{宋体}和 SimSun。\n";
    NSArray *found = [TMFontSettings knownReplaceableFontNamesInContent:t];
    TM_ASSERT_EQ_STR([found componentsJoinedByString:@"|"], @"SimHei|KaiTi|SimSun|kaiti_gb2312.ttf");
    NSUInteger n = 0;
    NSString *r = [TMFontSettings contentByReplacingFonts:@{@"SimSun": @"Songti SC", @"SimHei": @"Heiti SC", @"KaiTi": @"Kaiti SC", @"kaiti_gb2312.ttf": @"Kaiti SC"}
                                                inContent:t count:&n];
    TM_ASSERT_EQ_INT(n, 4);
    TM_ASSERT_EQ_STR(r, @"\\setCJKmainfont[BoldFont = Heiti SC, ItalicFont=Kaiti SC]{Songti SC}\n"
                        @"\\setCJKfamilyfont{zhkai}{Kaiti SC}\n"
                        @"\\setCJKsansfont{Kaiti SC}\n"
                        @"正文要求使用{宋体}和 SimSun。\n");
    TM_ASSERT_EQ_STR([TMFontSettings replacementCandidatesForFont:@"SIMSUN.TTC"].firstObject, @"Songti SC");
    TM_ASSERT_EQ_INT([TMFontSettings replacementCandidatesForFont:@"Songti SC"].count, 0);
}

TM_TEST(test_compiler_font_commands_pick_xelatex) {
    TMCompiler *c = [[TMCompiler alloc] init];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n\\usepackage{unicode-math}\n\\setmainfont{Georgia}\n"], @"xelatex");
}

TM_TEST(test_compiler_engine_follows_template_class) {
    // 中文模板常把 ctex 藏在 .cls 里：正文只有 \documentclass{gmcmthesis}
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [@"\\NeedsTeXFormat{LaTeX2e}\n\\LoadClass{ctexart}\n" writeToURL:[dir URLByAppendingPathComponent:@"gmcmthesis.cls"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 两层：mythesis.cls → mystyle.sty → xeCJK
    [@"\\LoadClass{article}\n\\RequirePackage{mystyle}\n" writeToURL:[dir URLByAppendingPathComponent:@"mythesis.cls"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"\\RequirePackage{xeCJK}\n" writeToURL:[dir URLByAppendingPathComponent:@"mystyle.sty"] atomically:YES encoding:NSUTF8StringEncoding error:nil];

    TMCompiler *c = [[TMCompiler alloc] init];
    NSString *reason = nil;
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{gmcmthesis}\n\\begin{document}\nabc\n\\end{document}\n" directoryURL:dir reason:&reason], @"xelatex");
    TM_ASSERT_TRUE([reason containsString:@"gmcmthesis.cls"]);
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{mythesis}\n" directoryURL:dir reason:&reason], @"xelatex");
    TM_ASSERT_TRUE([reason containsString:@"mystyle.sty"]);
    // 不给目录时维持老行为
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{gmcmthesis}\n"], @"pdflatex");
    // 手动选择与魔法注释仍然优先
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"% !TEX program = pdflatex\n\\documentclass{gmcmthesis}\n" directoryURL:dir reason:&reason], @"pdflatex");
    c.engine = TMTeXEngineLuaLaTeX;
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{gmcmthesis}\n" directoryURL:dir reason:&reason], @"lualatex");
    [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
}

TM_TEST(test_compiler_engine_chinese_text) {
    TMCompiler *c = [[TMCompiler alloc] init];
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n\\begin{document}\n你好，世界\n\\end{document}\n"], @"xelatex");
    // CJK 宏包是 pdfLaTeX 的中文方案，不要改引擎
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n\\usepackage{CJKutf8}\n\\begin{document}\n\\begin{CJK}{UTF8}{gbsn}你好\\end{CJK}\n\\end{document}\n"], @"pdflatex");
    // 只有注释里有中文 / 注释掉的 ctex 不算
    TM_ASSERT_EQ_STR([c effectiveEngineNameForContent:@"\\documentclass{article}\n% 这是注释 \\usepackage{ctex}\nHello\n"], @"pdflatex");
}

TM_TEST(test_log_stale_auxiliary_file_detection) {
    // 以下日志片段取自 TeX Live 2026 的真实输出
    NSString *head = @"This is pdfTeX, Version 3.141592653-2.6-1.40.29 (TeX Live 2026)\n(./main.tex\nLaTeX2e <2025-11-01>\n"
                     @"(/usr/local/texlive/2026/texmf-dist/tex/latex/base/article.cls\n"
                     @"(/usr/local/texlive/2026/texmf-dist/tex/latex/base/size10.clo))\n";
    // 截断的 .aux（上次编译中断）：报在 \begin{document} 这一行
    NSString *aux = [head stringByAppendingString:@"(./main.aux)\nRunaway argument?\n{{1}{1} \n"
                     @"./main.tex:2: File ended while scanning use of \\@newl@bel.\n<inserted text> \n                \\par \nl.2 \\begin{document}\n"];
    TM_ASSERT_EQ_STR([TMLogParser staleAuxiliaryFileInLog:aux], @"main.aux");
    // 截断的 .toc：报在 \tableofcontents 这一行
    NSString *toc = [head stringByAppendingString:@"(./main.aux) (./main.toc\nRunaway argument?\n"
                     @"./main.tex:3: File ended while scanning use of \\contentsline.\nl.3 \\tableofcontents\n"];
    TM_ASSERT_EQ_STR([TMLogParser staleAuxiliaryFileInLog:toc], @"main.toc");
    // 换了文献样式后的旧 .bbl：直接报在 .bbl 里
    NSString *bbl = [head stringByAppendingString:@"(./main.aux) (./main.bbl\n./main.bbl:3: Undefined control sequence.\nl.3 \\bibitem[Old(2020)]{k}\\natexlab\n"];
    TM_ASSERT_EQ_STR([TMLogParser staleAuxiliaryFileInLog:bbl], @"main.bbl");
    // \include 的章节 .aux 截断：报在主 .aux 里
    NSString *chapter = [head stringByAppendingString:@"(./b.aux (./chapters/intro.aux\nRunaway argument?\n"
                         @"./b.aux:2: File ended while scanning use of \\@newl@bel.\nl.2 \\@input{chapters/intro.aux}\n"];
    TM_ASSERT_EQ_STR([TMLogParser staleAuxiliaryFileInLog:chapter], @"b.aux");

    // 以下都是正文自己的错误，不能清理
    NSString *body = [head stringByAppendingString:@"(./main.aux)\n./main.tex:3: Undefined control sequence.\nl.3 Hello \\undefinedmacro\n"];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:body] == nil);
    // 错误恰好写在 \begin{document} 同一行，且刚读过 .aux
    NSString *sameLine = [head stringByAppendingString:@"(./d.aux)\n./d.tex:2: Undefined control sequence.\nl.2 \\begin{document}\\undefinedfoo\n"];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:sameLine] == nil);
    // 第一个错误在正文，后面才有辅助文件的连带错误
    NSString *cascade = [head stringByAppendingString:@"./main.tex:5: Missing $ inserted.\nl.5 a_b\n(./main.aux)\n./main.aux:3: Undefined control sequence.\n"];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:cascade] == nil);
    // 多遍编译：只看最后一遍（前一遍的 .bbl 错误已经过去了）
    NSString *multi = [NSString stringWithFormat:@"%@(./main.aux) (./main.bbl\n./main.bbl:3: Undefined control sequence.\n%@(./main.aux)\n./main.tex:3: Undefined control sequence.\nl.3 Hello \\oops\n", head, head];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:multi] == nil);
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:@""] == nil);
    // 正文里的 "This is" 出现在坏盒子里（不在行首），不能当成新一遍编译的开头
    NSString *overfull = [head stringByAppendingString:@"(./main.aux)\nOverfull \\hbox (1.0pt too wide) in paragraph at lines 3--4\n"
                          @"[]\\OT1/cmr/m/n/10 This is a very long line\nRunaway argument?\n"
                          @"./main.tex:5: File ended while scanning use of \\@newl@bel.\nl.5 \\end{document}\n"];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:overfull] != nil);
    // 找不到 TeX 的启动行（TeX 根本没跑起来，比如 latexmk 自己报错）：不判断
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:@"Latexmk: This is Latexmk\n(./main.aux)\n./main.aux:2: Undefined control sequence.\n"] == nil);
    // 正文漏了右括号：文件结束时出错，但出错位置不是读辅助文件的命令（真实日志）
    NSString *unclosed = [head stringByAppendingString:@"(./t1.aux))\nRunaway argument?\n{world \\end {document} \n"
                          @"! File ended while scanning use of \\textbf .\n<inserted text> \n                \\par \n<*> t1.tex\n"];
    TM_ASSERT_TRUE([TMLogParser staleAuxiliaryFileInLog:unclosed] == nil);
}

TM_TEST(test_clean_removes_glossary_and_chapter_aux) {
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] isDirectory:YES];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *sub in @[@"chapters", @"other-project"]) {
        [fm createDirectoryAtURL:[dir URLByAppendingPathComponent:sub] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSArray *names = @[@"main.tex", @"main.glo", @"main.gls", @"main.acn", @"main.ist", @"main.lol", @"main.ent", @"main.xyc", @"main.bbl",
                       @"chapters/intro.tex", @"chapters/intro.aux", @"chapters/notes.tex", @"chapters/notes.aux",
                       @"other-project/paper.tex", @"other-project/paper.aux", @"refs.bib", @"figure.pdf"];
    for (NSString *n in names) [@"x" writeToURL:[dir URLByAppendingPathComponent:n] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    // 主 .aux 只 \@input 了 intro 一章（外加一个指向项目外的，不能碰）
    [@"\\relax\n\\@input{chapters/intro.aux}\n\\@input{../outside.aux}\n" writeToURL:[dir URLByAppendingPathComponent:@"main.aux"]
                                                                         atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSURL *main = [dir URLByAppendingPathComponent:@"main.tex"];
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:main keepingBibliography:YES];
    TM_ASSERT_TRUE([fm fileExistsAtPath:[dir URLByAppendingPathComponent:@"main.bbl"].path]);   // 要求保留 .bbl
    [TMDocument cleanAuxiliaryFilesForTeXFileURL:main];

    for (NSString *gone in @[@"main.aux", @"main.glo", @"main.gls", @"main.acn", @"main.ist", @"main.lol", @"main.ent", @"main.xyc", @"main.bbl",
                             @"chapters/intro.aux"]) {
        TM_ASSERT_TRUE(![fm fileExistsAtPath:[dir URLByAppendingPathComponent:gone].path]);
    }
    // 源文件、参考文献库、插图保留；主 .aux 没列出的章节 .aux、同目录下别的项目的 .aux 也不动
    for (NSString *kept in @[@"main.tex", @"chapters/intro.tex", @"chapters/notes.aux", @"other-project/paper.aux", @"refs.bib", @"figure.pdf"]) {
        TM_ASSERT_TRUE([fm fileExistsAtPath:[dir URLByAppendingPathComponent:kept].path]);
    }
    [fm removeItemAtURL:dir error:nil];
}

TM_TEST(test_bibliography_regenerable_only_with_bib_source) {
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main = [dir URLByAppendingPathComponent:@"main.tex"];
    void (^write)(NSString *) = ^(NSString *text) { [text writeToURL:main atomically:YES encoding:NSUTF8StringEncoding error:nil]; };

    // arXiv 式：只有 .bbl，没有 .bib
    write(@"\\documentclass{article}\n\\begin{document}\n\\cite{k}\n\\bibliographystyle{plain}\n\\bibliography{refs}\n\\end{document}\n");
    TM_ASSERT_TRUE(![TMProject canRegenerateBibliographyForTeXFileURL:main]);
    [@"@article{k,}" writeToURL:[dir URLByAppendingPathComponent:@"refs.bib"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    TM_ASSERT_TRUE([TMProject canRegenerateBibliographyForTeXFileURL:main]);
    // biblatex 的 \addbibresource 带扩展名
    write(@"\\usepackage{biblatex}\n\\addbibresource{refs.bib}\n");
    TM_ASSERT_TRUE([TMProject canRegenerateBibliographyForTeXFileURL:main]);
    // 注释掉的不算；\bibliographystyle 不是 \bibliography
    write(@"% \\bibliography{refs}\n\\bibliographystyle{refs}\n\\input{main.bbl}\n");
    TM_ASSERT_TRUE(![TMProject canRegenerateBibliographyForTeXFileURL:main]);
    [[NSFileManager defaultManager] removeItemAtURL:dir error:nil];
}

TM_TEST(test_font_catalog_lists_songti_and_hides_pingfang) {
    NSArray<TMFontFamily *> *families = [TMFontCatalog enumerateSystemFamilies];
    TMFontFamily *songti = nil;
    BOOL pingfang = NO;
    for (TMFontFamily *f in families) {
        if ([f.familyName isEqualToString:@"Songti SC"]) songti = f;
        if ([f.familyName isEqualToString:@"PingFang SC"]) pingfang = YES;
    }
    TM_ASSERT_TRUE(songti != nil);
    TM_ASSERT_TRUE(songti.supportsChinese);
    TM_ASSERT_TRUE(songti.hasBold);
    TM_ASSERT_TRUE(!pingfang);
}

#pragma mark - TMMarkdownScanner

/// 把扫描结果拼成 "kind:文字" 列表，便于断言
static NSArray<NSString *> *TMMarkdownRegionsOf(NSString *s) {
    TMMarkdownScanResult *r = [TMMarkdownScanner scanString:s];
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < r.regionCount; i++) {
        [out addObject:[NSString stringWithFormat:@"%ld:%@", (long)r.regions[i].kind, [s substringWithRange:r.regions[i].range]]];
    }
    return out;
}

static BOOL TMHasRegion(NSArray<NSString *> *regions, TMMarkdownRegionKind kind, NSString *text) {
    return [regions containsObject:[NSString stringWithFormat:@"%ld:%@", (long)kind, text]];
}

TM_TEST(test_markdown_percent_is_not_a_comment) {
    TM_ASSERT_EQ_INT(TMMarkdownRegionsOf(@"增长了 50% 以上，a & b\n").count, 0);
}

TM_TEST(test_markdown_heading_and_inline) {
    NSArray *r = TMMarkdownRegionsOf(@"## 标题\n一段 **粗体** 和 *斜体* 以及 `a*b*c` 与 ~~删~~\n");
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionHeading, @"## 标题"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionMarker, @"##"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionStrong, @"**粗体**"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionEmphasis, @"*斜体*"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionCode, @"`a*b*c`"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionStrike, @"~~删~~"));
    // 代码里的 *b* 不算斜体
    TM_ASSERT_TRUE(!TMHasRegion(r, TMMarkdownRegionEmphasis, @"*b*"));
}

TM_TEST(test_markdown_hash_without_space_is_not_heading) {
    NSArray *r = TMMarkdownRegionsOf(@"#tag 不是标题\n");
    TM_ASSERT_EQ_INT(r.count, 0);
}

TM_TEST(test_markdown_fenced_code_spans_blank_lines) {
    NSString *s = @"前\n```\na = 1 # x\n\n**不粗**\n```\n后\n";
    NSArray *r = TMMarkdownRegionsOf(s);
    TM_ASSERT_EQ_INT(r.count, 1);
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionCode, @"```\na = 1 # x\n\n**不粗**\n```"));
}

TM_TEST(test_markdown_lists_quotes_links_rules) {
    NSArray *r = TMMarkdownRegionsOf(@"- 一\n1. 二\n> 引用\n---\n见 [文档](https://a.b/c_d) 和 snake_case_name\n");
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionMarker, @"-"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionMarker, @"1."));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionQuote, @"> 引用"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionMarker, @"---"));
    TM_ASSERT_TRUE(TMHasRegion(r, TMMarkdownRegionLink, @"[文档](https://a.b/c_d)"));
    NSString *emphasisPrefix = [NSString stringWithFormat:@"%ld:", (long)TMMarkdownRegionEmphasis];
    for (NSString *x in r) TM_ASSERT_TRUE(![x hasPrefix:emphasisPrefix]);
}

#pragma mark - TMFormatActions

/// 应用一次格式编辑，返回新文本；光标 / 选区写进 *sel
static NSString *TMApplyFormat(NSString *text, TMFormatEdit *edit, NSRange *sel) {
    if (!edit) return text;
    NSString *out = [text stringByReplacingCharactersInRange:edit.range withString:edit.replacement];
    if (sel) *sel = edit.selection;
    return out;
}

/// 文本里的 | 表示光标
static NSString *TMStripCaret(NSString *s, NSRange *sel) {
    NSRange bar = [s rangeOfString:@"|"];
    *sel = NSMakeRange(bar.location, 0);
    return [s stringByReplacingCharactersInRange:bar withString:@""];
}

static NSString *TMWithCaret(NSString *s, NSRange sel) {
    return [s stringByReplacingCharactersInRange:NSMakeRange(sel.location, 0) withString:@"|"];
}

static NSString *TMParagraph(NSString *input, TMParagraphStyle style, BOOL chapters) {
    NSRange sel;
    NSString *text = TMStripCaret(input, &sel);
    TMFormatEdit *edit = [TMFormatActions editForParagraphStyle:style selection:sel inText:text markdown:NO usesChapters:chapters];
    NSString *out = TMApplyFormat(text, edit, &sel);
    return TMWithCaret(out, sel);
}

TM_TEST(test_format_heading_levels_follow_document_class) {
    TM_ASSERT_TRUE(![TMFormatActions usesChaptersForMainContent:@"\\documentclass{ctexart}\n" currentContent:@""]);
    TM_ASSERT_TRUE([TMFormatActions usesChaptersForMainContent:@"\\documentclass[12pt]{ctexbook}\n" currentContent:@""]);
    TM_ASSERT_TRUE([TMFormatActions usesChaptersForMainContent:@"\\documentclass{thuthesis}\n" currentContent:@""]);
    TM_ASSERT_TRUE([TMFormatActions usesChaptersForMainContent:nil currentContent:@"\\chapter{引言}\n"]);
    TM_ASSERT_EQ_STR(TMParagraph(@"引|言\n", TMParagraphStyleHeading1, NO), @"\\section{引|言}\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"引|言\n", TMParagraphStyleHeading1, YES), @"\\chapter{引|言}\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"方法|\n", TMParagraphStyleHeading3, NO), @"\\subsubsection{方法|}\n");
}

TM_TEST(test_format_heading_toggle_and_change) {
    // 再按一次取消；换级别保留 * 和 \label
    TM_ASSERT_EQ_STR(TMParagraph(@"\\section{引|言}\n", TMParagraphStyleHeading1, NO), @"引|言\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"\\section*{引言|}\\label{s}\n", TMParagraphStyleHeading2, NO), @"\\subsection*{引言|}\\label{s}\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"\\subsection{A|}\n", TMParagraphStyleBody, NO), @"A|\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"|\n", TMParagraphStyleHeading1, NO), @"\\section{|}\n");
    TM_ASSERT_TRUE([TMFormatActions editForParagraphStyle:TMParagraphStyleBody selection:NSMakeRange(0, 0) inText:@"正文\n" markdown:NO usesChapters:NO] == nil);
}

TM_TEST(test_format_paragraph_style_detection) {
    NSString *text = @"\\subsection{A}\n\\begin{enumerate}\n  \\item x\n\\end{enumerate}\n\\begin{quote}\nq\n\\end{quote}\n正文\n";
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:2 inText:text markdown:NO usesChapters:NO], TMParagraphStyleHeading2);
    NSUInteger item = [text rangeOfString:@"x"].location;
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:item inText:text markdown:NO usesChapters:NO], TMParagraphStyleNumberedList);
    NSUInteger q = [text rangeOfString:@"q\n"].location;
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:q inText:text markdown:NO usesChapters:NO], TMParagraphStyleQuote);
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:text.length - 2 inText:text markdown:NO usesChapters:NO], TMParagraphStyleBody);
    // 注释掉的 \begin{itemize} 不算
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:20 inText:@"% \\begin{itemize}\nabc\n" markdown:NO usesChapters:NO], TMParagraphStyleBody);
}

TM_TEST(test_format_lists_wrap_switch_unwrap) {
    TM_ASSERT_EQ_STR(TMParagraph(@"第一点|\n", TMParagraphStyleBulletList, NO),
                     @"\\begin{itemize}\n  \\item 第一点|\n\\end{itemize}\n");
    NSRange sel;
    NSString *text = @"甲\n乙\n";
    TMFormatEdit *edit = [TMFormatActions editForParagraphStyle:TMParagraphStyleNumberedList selection:NSMakeRange(0, text.length) inText:text markdown:NO usesChapters:NO];
    NSString *out = TMApplyFormat(text, edit, &sel);
    TM_ASSERT_EQ_STR(TMWithCaret(out, sel), @"\\begin{enumerate}\n  \\item 甲\n  \\item 乙|\n\\end{enumerate}\n");
    // 无序 ↔ 有序
    TM_ASSERT_EQ_STR(TMParagraph(@"\\begin{itemize}\n  \\item a|\n\\end{itemize}\n", TMParagraphStyleNumberedList, NO),
                     @"\\begin{enumerate}\n  \\item a|\n\\end{enumerate}\n");
    // 同一种再按一次：变回段落
    TM_ASSERT_EQ_STR(TMParagraph(@"\\begin{itemize}\n  \\item a|\n  \\item b\n\\end{itemize}\n", TMParagraphStyleBulletList, NO),
                     @"|a\n\nb\n");
}

TM_TEST(test_format_list_item_to_heading_splits_list) {
    TM_ASSERT_EQ_STR(TMParagraph(@"\\begin{itemize}\n  \\item a\n  \\item b|\n  \\item c\n\\end{itemize}\n", TMParagraphStyleBody, NO),
                     @"\\begin{itemize}\n  \\item a\n\\end{itemize}\n\nb|\n\n\\begin{itemize}\n  \\item c\n\\end{itemize}\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"\\begin{itemize}\n  \\item |a\n\\end{itemize}\n", TMParagraphStyleHeading1, NO),
                     @"\\section{|a}\n");
}

TM_TEST(test_format_quote_wrap_unwrap) {
    TM_ASSERT_EQ_STR(TMParagraph(@"名言|\n", TMParagraphStyleQuote, NO), @"\\begin{quote}\n名言|\n\\end{quote}\n");
    TM_ASSERT_EQ_STR(TMParagraph(@"\\begin{quote}\n名言|\n\\end{quote}\n", TMParagraphStyleQuote, NO), @"名言|\n");
}

TM_TEST(test_format_markdown_paragraph_styles) {
    NSRange sel;
    NSString *text = TMStripCaret(@"标|题\n", &sel);
    NSString *out = TMApplyFormat(text, [TMFormatActions editForParagraphStyle:TMParagraphStyleHeading2 selection:sel inText:text markdown:YES usesChapters:NO], &sel);
    TM_ASSERT_EQ_STR(TMWithCaret(out, sel), @"## 标|题\n");
    out = TMApplyFormat(out, [TMFormatActions editForParagraphStyle:TMParagraphStyleHeading2 selection:sel inText:out markdown:YES usesChapters:NO], &sel);
    TM_ASSERT_EQ_STR(TMWithCaret(out, sel), @"标|题\n");
    text = @"a\nb\n";
    out = TMApplyFormat(text, [TMFormatActions editForParagraphStyle:TMParagraphStyleNumberedList selection:NSMakeRange(0, 3) inText:text markdown:YES usesChapters:NO], &sel);
    TM_ASSERT_EQ_STR(out, @"1. a\n2. b\n");
    TM_ASSERT_EQ_INT([TMFormatActions paragraphStyleAtLocation:0 inText:@"> 引\n" markdown:YES usesChapters:NO], TMParagraphStyleQuote);
}

static NSString *TMInline(NSString *input, TMInlineStyle style, BOOL markdown) {
    // [ ] 表示选区，| 表示光标
    NSRange sel;
    NSString *text;
    NSRange open = [input rangeOfString:@"["];
    if (open.location != NSNotFound) {
        text = [input stringByReplacingCharactersInRange:open withString:@""];
        NSRange close = [text rangeOfString:@"]"];
        text = [text stringByReplacingCharactersInRange:close withString:@""];
        sel = NSMakeRange(open.location, close.location - open.location);
    } else {
        text = TMStripCaret(input, &sel);
    }
    NSString *out = TMApplyFormat(text, [TMFormatActions editForInlineStyle:style selection:sel inText:text markdown:markdown], &sel);
    if (sel.length == 0) return TMWithCaret(out, sel);
    return [NSString stringWithFormat:@"%@[%@]%@", [out substringToIndex:sel.location], [out substringWithRange:sel], [out substringFromIndex:NSMaxRange(sel)]];
}

TM_TEST(test_format_inline_styles) {
    TM_ASSERT_EQ_STR(TMInline(@"很[重要]的", TMInlineStyleBold, NO), @"很\\textbf{[重要]}的");
    TM_ASSERT_EQ_STR(TMInline(@"很\\textbf{[重要]}的", TMInlineStyleBold, NO), @"很[重要]的");
    TM_ASSERT_EQ_STR(TMInline(@"很[\\textbf{重要}]的", TMInlineStyleBold, NO), @"很[重要]的");
    TM_ASSERT_EQ_STR(TMInline(@"a|b", TMInlineStyleBold, NO), @"a\\textbf{|}b");
    TM_ASSERT_EQ_STR(TMInline(@"x \\emph{重|要} y", TMInlineStyleItalic, NO), @"x 重|要 y");
    TM_ASSERT_EQ_STR(TMInline(@"x \\textbf{a {b} c|} y", TMInlineStyleBold, NO), @"x a {b} c| y");
    TM_ASSERT_EQ_STR(TMInline(@"[词]", TMInlineStyleUnderline, NO), @"\\underline{[词]}");
    TM_ASSERT_EQ_STR(TMInline(@"[词]", TMInlineStyleBold, YES), @"**[词]**");
    TM_ASSERT_EQ_STR(TMInline(@"**[词]**", TMInlineStyleBold, YES), @"[词]");
}

TM_TEST(test_format_insertions) {
    NSRange sel;
    NSString *text = @"见官网";
    TMFormatEdit *edit = [TMFormatActions editForInsertion:TMFormatInsertLink selection:NSMakeRange(1, 2) inText:text markdown:NO];
    TM_ASSERT_EQ_STR(TMApplyFormat(text, edit, &sel), @"见\\href{https://}{官网}");
    TM_ASSERT_EQ_STR(edit.requiredPackage, @"hyperref");
    TM_ASSERT_EQ_INT(sel.length, 8);

    text = TMStripCaret(@"前文|\n后文\n", &sel);
    NSString *out = TMApplyFormat(text, [TMFormatActions editForInsertion:TMFormatInsertDisplayMath selection:sel inText:text markdown:NO], &sel);
    TM_ASSERT_EQ_STR(TMWithCaret(out, sel), @"前文\n\\begin{equation}\n  |\n\\end{equation}\n后文\n");

    text = TMStripCaret(@"|\n", &sel);
    out = TMApplyFormat(text, [TMFormatActions editForInsertion:TMFormatInsertInlineMath selection:sel inText:text markdown:NO], &sel);
    TM_ASSERT_EQ_STR(TMWithCaret(out, sel), @"$|$\n");

    text = TMStripCaret(@"|", &sel);
    out = TMApplyFormat(text, [TMFormatActions editForInsertion:TMFormatInsertTable selection:sel inText:text markdown:NO], &sel);
    TM_ASSERT_TRUE([out hasPrefix:@"\\begin{table}[htbp]\n  \\centering\n  \\caption{}"]);
    TM_ASSERT_TRUE([out hasSuffix:@"\\end{table}"]);
    TM_ASSERT_EQ_INT(sel.location, [out rangeOfString:@"\\caption{"].location + 9);
}

TM_TEST(test_format_usepackage_location) {
    NSString *doc = @"\\documentclass{article}\n\\usepackage{graphicx}\n\\begin{document}\nx\n\\end{document}\n";
    TM_ASSERT_EQ_INT([TMFormatActions usepackageInsertionLocationForPackage:@"graphicx" inContent:doc], NSNotFound);
    TM_ASSERT_EQ_INT([TMFormatActions usepackageInsertionLocationForPackage:@"xcolor" inContent:doc], 24);
    TM_ASSERT_EQ_INT([TMFormatActions usepackageInsertionLocationForPackage:@"hyperref" inContent:doc], [doc rangeOfString:@"\\begin{document}"].location);
    TM_ASSERT_EQ_INT([TMFormatActions usepackageInsertionLocationForPackage:@"hyperref" inContent:@"正文"], NSNotFound);
}

#pragma mark - Runner

#include "TMLineIndexTests.inc"
#include "TMCompletionCacheTests.inc"
#include "TMOutlineReuseTests.inc"
#include "TMWordCounterTests.inc"

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
