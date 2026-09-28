TM_TEST(test_bibliography_requires_every_literal_source) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main = [dir URLByAppendingPathComponent:@"main.tex"];
    void (^write)(NSString *) = ^(NSString *text) { [text writeToURL:main atomically:YES encoding:NSUTF8StringEncoding error:nil]; };
    [@"@article{a,}" writeToURL:[dir URLByAppendingPathComponent:@"a.bib"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    write(@"\\bibliography{a,missing}\n");
    BOOL partialBibtex = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\addbibresource{a.bib}\n\\addbibresource{missing.bib}\n");
    BOOL partialBiblatex = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    [@"@article{b,}" writeToURL:[dir URLByAppendingPathComponent:@"missing.bib"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    BOOL completeBiblatex = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\bibliography{a,missing}\n");
    BOOL completeBibtex = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    [fm removeItemAtURL:dir error:nil];
    TM_ASSERT_TRUE(!partialBibtex && !partialBiblatex);
    TM_ASSERT_TRUE(completeBibtex && completeBiblatex);
}

TM_TEST(test_bibliography_ignores_comments_and_rejects_uncertain_sources) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *dir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *main = [dir URLByAppendingPathComponent:@"main.tex"];
    void (^write)(NSString *) = ^(NSString *text) { [text writeToURL:main atomically:YES encoding:NSUTF8StringEncoding error:nil]; };
    [@"@article{a,}" writeToURL:[dir URLByAppendingPathComponent:@"a.bib"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    write(@"% \\bibliography{missing}\n\\bibliography{a}\n");
    BOOL commentsIgnored = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\bibliography{a,\\dynamicDatabase}\n");
    BOOL dynamicAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\bibliography{a}\n\\addbibresource{}\n");
    BOOL emptyAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    [fm createDirectoryAtURL:[dir URLByAppendingPathComponent:@"folder.bib"] withIntermediateDirectories:YES attributes:nil error:nil];
    write(@"\\bibliography{folder}\n");
    BOOL directoryAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"% \\bibliography{a}\n\\input{main.bbl}\n");
    BOOL noDeclarationAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\bibliography{a}\n\\input{preamble}\n");
    BOOL dependencyAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    write(@"\\bibliography{a}\n\\input{\\dynamic}\n");
    BOOL dynamicDependencyAccepted = [TMProject canRegenerateBibliographyForTeXFileURL:main];
    [fm removeItemAtURL:dir error:nil];
    TM_ASSERT_TRUE(commentsIgnored);
    TM_ASSERT_TRUE(!dynamicAccepted && !emptyAccepted && !directoryAccepted && !noDeclarationAccepted);
    TM_ASSERT_TRUE(!dependencyAccepted && !dynamicDependencyAccepted);
}
