// TeXMini 极简单元测试：无 XCTest 依赖，clang 直接编译运行。
// 用法：tests/run_tests.sh
#import <Foundation/Foundation.h>
#import "TMDocument.h"
#import "TMEditActions.h"

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
#define TM_ASSERT_EQ_STR(a, b) do { NSString *_a = (a), *_b = (b); if (!((_a == nil && _b == nil) || [_a isEqualToString:_b])) TM_FAIL("%s == %@, expected %@", #a, [_a description], [_b description]); } while (0)

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
