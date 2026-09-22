// TeXMini 极简单元测试：无 XCTest 依赖，clang 直接编译运行。
// 用法：tests/run_tests.sh
#import <Foundation/Foundation.h>
#import "TMDocument.h"
#import "TMEditActions.h"
#import "TMMagicComments.h"
#import "TMLogParser.h"
#import "TMRecentFiles.h"

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
    TM_ASSERT_EQ_INT(issues[1].line, 20);
}

#pragma mark - TMRecentFiles

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
