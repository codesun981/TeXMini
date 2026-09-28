// 纯逻辑回归：不创建窗口，不依赖 GUI 事件。
TM_TEST(test_editor_does_not_close_an_existing_document_environment) {
    NSString *text = @"\\documentclass{article}\n\\begin{document}\nHello.\n\\end{document}\n";
    NSUInteger cursor = NSMaxRange([text rangeOfString:@"\\begin{document}"]);
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:text atLocation:cursor]);
}

TM_TEST(test_editor_environment_matching_handles_nested_names_and_ignored_text) {
    NSString *closed = @"\\begin{itemize}\n\\begin{itemize}\n\\item 中文😀\n\\end{itemize}\n\\end{itemize}";
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:closed atLocation:15]);
    NSString *open = @"\\begin{itemize}\n\\begin{itemize}\n\\item 中文😀\n\\end{itemize}";
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInText:open atLocation:15], @"itemize");
    NSString *commented = @"\\begin{itemize}\n% \\end{itemize}\n\\verb|\\end{itemize}|";
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInText:commented atLocation:15], @"itemize");
    NSString *raw = @"\\begin{itemize}\n\\begin{verbatim}\n\\end{itemize}\n\\end{verbatim}";
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInText:raw atLocation:15], @"itemize");
    NSString *codeLine = @"\\begin{verbatim}\n\\begin{itemize}\n\\end{verbatim}";
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:codeLine atLocation:NSMaxRange([codeLine rangeOfString:@"\\begin{itemize}"])]);
    NSString *definition = @"\\newcommand{\\foo}{\\begin{itemize}}";
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:definition atLocation:definition.length]);
}

TM_TEST(test_editor_environment_matching_respects_cursor_and_math) {
    NSString *text = @"中文😀 \\begin{align*}\n x &= y \\\\\n\\end{align*}";
    NSUInteger beginEnd = NSMaxRange([text rangeOfString:@"\\begin{align*}"]);
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:text atLocation:beginEnd]);
    NSString *open = @"中文😀 \\begin{align*}";
    TM_ASSERT_EQ_STR([TMEditActions environmentToCloseInText:open atLocation:open.length], @"align*");
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:open atLocation:0]);
    TM_ASSERT_NIL([TMEditActions environmentToCloseInText:open atLocation:open.length - 1]);
}

TM_TEST(test_scanner_raw_environment_at_eof_stays_inside_source) {
    for (NSString *name in @[@"verbatim", @"comment", @"minted"]) {
        NSString *text = [NSString stringWithFormat:@"\\begin{%@}\n中文😀\n\\end{%@}", name, name];
        TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:text];
        for (NSUInteger i = 0; i < scan.regionCount; i++) TM_ASSERT_TRUE(NSMaxRange(scan.regions[i].range) <= text.length);
    }
}

TM_TEST(test_highlight_repaints_block_boundaries_even_when_kind_count_is_unchanged) {
    NSString *padding = [@"raw " stringByPaddingToLength:120 withString:@"raw " startingAtIndex:0];
    NSString *old = [NSString stringWithFormat:@"\\begin{verbatim}\n%@\n\\end{verbatim}\n\n\\section{Far heading}\n\n%% \\end{verbatim}\n", padding];
    NSRange removed = [old rangeOfString:@"\\end{verbatim}"];
    NSMutableString *now = [old mutableCopy];
    [now deleteCharactersInRange:removed];
    TMLaTeXScanResult *before = [TMLaTeXScanner scanString:old];
    TMLaTeXScanResult *after = [TMLaTeXScanner scanString:now];
    TM_ASSERT_EQ_STR(before.blockSignature, after.blockSignature);
    NSUInteger heading = [now rangeOfString:@"\\section"].location;
    NSRange affected = [after rangeAffectedComparedToScan:before editedRange:NSMakeRange(removed.location, 0)];
    TM_ASSERT_TRUE(affected.location != NSNotFound && NSLocationInRange(heading, affected));
    TM_ASSERT_TRUE(NSMaxRange(affected) <= now.length);
}

TM_TEST(test_highlight_plain_edits_only_shift_later_regions) {
    NSString *old = @"前言😀\n\n\\begin{equation}\n x + y\n\\end{equation}\n\n\\section{后文}";
    NSString *inserted = @"中文😀";
    NSUInteger location = 1;
    NSMutableString *now = [old mutableCopy];
    [now insertString:inserted atIndex:location];
    TMLaTeXScanResult *before = [TMLaTeXScanner scanString:old];
    TMLaTeXScanResult *after = [TMLaTeXScanner scanString:now];
    TM_ASSERT_EQ_INT([after rangeAffectedComparedToScan:before editedRange:NSMakeRange(location, inserted.length)].location, NSNotFound);
    location = [old rangeOfString:@"x + y"].location;
    now = [old mutableCopy];
    [now insertString:@"z + " atIndex:location];
    after = [TMLaTeXScanner scanString:now];
    TM_ASSERT_EQ_INT([after rangeAffectedComparedToScan:before editedRange:NSMakeRange(location, 4)].location, NSNotFound);
}

TM_TEST(test_highlight_removed_math_repaints_its_old_extent_not_whole_document) {
    NSString *old = @"前言\n\n\\begin{equation}\nx = y\n\n+ z\n\\end{equation}\n\n后文";
    NSRange edit = [old rangeOfString:@"\\end{equation}"];
    NSMutableString *now = [old mutableCopy];
    [now deleteCharactersInRange:edit];
    TMLaTeXScanResult *before = [TMLaTeXScanner scanString:old];
    TMLaTeXScanResult *after = [TMLaTeXScanner scanString:now];
    NSRange affected = [after rangeAffectedComparedToScan:before editedRange:NSMakeRange(edit.location, 0)];
    TM_ASSERT_TRUE(affected.location != NSNotFound);
    TM_ASSERT_TRUE(NSLocationInRange([now rangeOfString:@"x = y"].location, affected));
    TM_ASSERT_TRUE(affected.location > 0 && NSMaxRange(affected) < now.length);
}

TM_TEST(test_scanner_unclosed_heading_arguments_do_not_rescan_every_suffix) {
    NSMutableString *text = [NSMutableString string];
    for (NSUInteger i = 0; i < 20000; i++) [text appendString:@"\\section{unfinished\n"];
    [text appendString:@"\\section{最后😀标题}\n"];
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:text];
    NSTimeInterval duration = CFAbsoluteTimeGetCurrent() - start;
    TM_ASSERT_EQ_INT(scan.headings.count, 1);
    TM_ASSERT_EQ_STR(scan.headings.firstObject.rawTitle, @"最后😀标题");
    // 原实现约 3.7 秒；线性失败缓存约几十毫秒，1 秒给慢速 CI 留足余量。
    TM_ASSERT_TRUE(duration < 1.0);
}

TM_TEST(test_scanner_failed_arguments_preserve_later_aliases_and_optional_titles) {
    NSString *text = @"\\newcommand{\\mysection}[1]{\\section{#1}}\n"
        @"\\section{unfinished\n\\section[unfinished\n"
        @"\\mysection{中文😀别名}\n\\section[short]{Last {nested} title}\n";
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:text];
    TM_ASSERT_EQ_INT(scan.headings.count, 2);
    TM_ASSERT_EQ_STR(scan.headings[0].rawTitle, @"中文😀别名");
    TM_ASSERT_EQ_STR(scan.headings[1].rawTitle, @"Last {nested} title");
}

static NSUInteger tm_editor_region_kinds(TMLaTeXScanResult *scan, NSUInteger location) {
    NSUInteger kinds = 0;
    for (NSUInteger i = 0; i < scan.regionCount; i++) {
        if (NSLocationInRange(location, scan.regions[i].range)) kinds |= (1UL << scan.regions[i].kind);
    }
    return kinds;
}

TM_TEST(test_highlight_changed_range_covers_every_changed_retained_character) {
    NSString *old = @"中文😀\n\\section{Title}\n\n\\begin{equation}\nx + \\alpha\n\ny\n\\end{equation}\n\n"
        @"\\begin{verbatim}\nraw % $ {}\n\n\\end{verbatim}\n% comment\n\\url{https://x/%20}\n\\textbf{end}";
    TMLaTeXScanResult *before = [TMLaTeXScanner scanString:old];
    for (NSUInteger location = 0; location <= old.length; location += 3) {
        for (NSString *replacement in @[@"", @"%", @"\n", @"\\", @"中文😀"]) {
            NSUInteger removed = MIN((NSUInteger)2, old.length - location);
            NSMutableString *now = [old mutableCopy];
            [now replaceCharactersInRange:NSMakeRange(location, removed) withString:replacement];
            TMLaTeXScanResult *after = [TMLaTeXScanner scanString:now];
            NSRange edit = NSMakeRange(location, replacement.length);
            NSRange affected = [after rangeAffectedComparedToScan:before editedRange:edit];
            TM_ASSERT_TRUE(affected.location == NSNotFound || NSMaxRange(affected) <= now.length);
            for (NSUInteger p = 0; p < now.length; p++) {
                if (NSLocationInRange(p, edit)) continue;
                NSUInteger oldPosition = p < location ? p : p - replacement.length + removed;
                if (tm_editor_region_kinds(before, oldPosition) == tm_editor_region_kinds(after, p)) continue;
                TM_ASSERT_TRUE(affected.location != NSNotFound && NSLocationInRange(p, affected));
            }
        }
    }
}
