#import "TMLineIndex.h"

static BOOL tm_lineIndexMatchesText(NSString *text) {
    TMLineIndex *index = [[TMLineIndex alloc] initWithString:text];
    NSUInteger line = 1, start = 0;
    for (NSUInteger pos = 0; pos <= text.length; pos++) {
        if ([index lineNumberForCharacterIndex:pos] != line || [index startOfLine:line] != start) return NO;
        if (pos < text.length && [text characterAtIndex:pos] == '\n') { line++; start = pos + 1; }
    }
    return index.length == text.length && index.lineCount == line &&
        [index startOfLine:0] == NSNotFound && [index startOfLine:line + 1] == NSNotFound &&
        [index lineNumberForCharacterIndex:NSUIntegerMax] == line;
}

TM_TEST(test_line_index_preserves_utf16_and_newline_boundaries) {
    for (NSString *text in @[@"", @"abc", @"\n", @"\n\n", @"中文😀\r\n第二行\n", @"a\rb\u2028c", @"x\n\nend"]) {
        TM_ASSERT_TRUE(tm_lineIndexMatchesText(text));
    }
    NSMutableString *mutable = [@"a\nb" mutableCopy];
    TMLineIndex *snapshot = [[TMLineIndex alloc] initWithString:mutable];
    [mutable setString:@"ab\n"];
    TM_ASSERT_EQ_INT([snapshot startOfLine:2], 2);
    TM_ASSERT_TRUE(tm_lineIndexMatchesText(mutable));
}

TM_TEST(test_line_index_matches_reference_after_random_edits) {
    NSMutableString *text = [@"中文😀\nfirst\r\nlast" mutableCopy];
    uint32_t state = 12345;
    NSArray *insertions = @[@"", @"a", @"\n", @"\r\n", @"中文", @"😀", @"\n\n"];
    for (NSUInteger step = 0; step < 300; step++) {
        state = state * 1664525u + 1013904223u;
        NSUInteger start = state % (text.length + 1);
        state = state * 1664525u + 1013904223u;
        NSUInteger length = state % (MIN((NSUInteger)5, text.length - start) + 1);
        [text replaceCharactersInRange:NSMakeRange(start, length) withString:insertions[step % insertions.count]];
        TM_ASSERT_TRUE(tm_lineIndexMatchesText(text));
    }
}
