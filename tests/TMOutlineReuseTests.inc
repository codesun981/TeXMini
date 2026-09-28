TM_TEST(test_outline_from_shared_scan_preserves_hierarchy_and_locations) {
    NSString *text = @"% \\section{hidden}\n\\section[短]{一 {章}}\n中文😀\r\n\\subsection{二}\n\\begin{verbatim}\n\\section{ignored}\n\\end{verbatim}\n\\section{三}\n";
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:text];
    TMLineIndex *index = [[TMLineIndex alloc] initWithString:text];
    NSArray<TMOutlineItem *> *flat = nil;
    NSArray<TMOutlineItem *> *roots = [TMOutlineParser parseOutlineFromScan:scan lineIndex:index flatList:&flat];
    TM_ASSERT_EQ_INT(roots.count, 2);
    TM_ASSERT_EQ_INT(flat.count, 3);
    TM_ASSERT_EQ_INT(flat[0].lineNumber, 2);
    TM_ASSERT_EQ_INT(flat[1].lineNumber, 4);
    TM_ASSERT_EQ_INT(flat[2].lineNumber, 8);
    TM_ASSERT_TRUE(flat[1].parent == flat[0]);
    TM_ASSERT_EQ_INT(flat[1].charLocation, [text rangeOfString:@"\\subsection"].location);
    NSArray<TMOutlineItem *> *legacy = nil;
    [TMOutlineParser parseOutlineFromLaTeXString:text flatList:&legacy];
    for (NSUInteger i = 0; i < flat.count; i++) {
        TM_ASSERT_EQ_STR(flat[i].title, legacy[i].title);
        TM_ASSERT_EQ_INT(flat[i].level, legacy[i].level);
        TM_ASSERT_EQ_INT(flat[i].charLocation, legacy[i].charLocation);
    }
}

TM_TEST(test_outline_shared_empty_and_changed_snapshots) {
    NSArray *flat = nil;
    TM_ASSERT_EQ_INT([TMOutlineParser parseOutlineFromScan:nil lineIndex:[[TMLineIndex alloc] initWithString:@""] flatList:&flat].count, 0);
    TM_ASSERT_EQ_INT(flat.count, 0);
    NSMutableString *text = [@"\\section{old}\n" mutableCopy];
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:text];
    TMLineIndex *index = [[TMLineIndex alloc] initWithString:text];
    [text setString:@"\\section{new}\n"];
    [TMOutlineParser parseOutlineFromScan:scan lineIndex:index flatList:&flat];
    TM_ASSERT_EQ_STR(((TMOutlineItem *)flat[0]).title, @"old");
    [TMOutlineParser parseOutlineFromLaTeXString:text flatList:&flat];
    TM_ASSERT_EQ_STR(((TMOutlineItem *)flat[0]).title, @"new");
}
