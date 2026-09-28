static NSURL *tm_resolutionProject(void) {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root.URLByResolvingSymlinksInPath;
}
static NSURL *tm_resolutionWrite(NSURL *root, NSString *name, NSString *text) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

TM_TEST(test_project_matches_full_chapter_paths) {
    NSURL *root = tm_resolutionProject();
    NSURL *a = tm_resolutionWrite(root, @"a/chapter.tex", @"A");
    NSURL *b = tm_resolutionWrite(root, @"b/chapter.tex", @"B");
    tm_resolutionWrite(root, @"a-main.tex", @"\\documentclass{article}\n\\input{a/chapter}\n");
    tm_resolutionWrite(root, @"b-main.tex", @"\\documentclass{article}\n\\input{b/chapter}\n");
    NSString *forA = [TMProject mainFileURLForDocumentURL:a content:@"A"].lastPathComponent;
    NSString *forB = [TMProject mainFileURLForDocumentURL:b content:@"B"].lastPathComponent;
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    TM_ASSERT_EQ_STR(forA, @"a-main.tex");
    TM_ASSERT_EQ_STR(forB, @"b-main.tex");
}

TM_TEST(test_project_traverses_nested_inputs_and_import_contexts) {
    NSURL *root = tm_resolutionProject();
    NSURL *leaf = tm_resolutionWrite(root, @"chapters/deep/leaf.tex", @"leaf");
    tm_resolutionWrite(root, @"chapter-main.tex", @"\\documentclass{article}\n\\input{chapters/intro}\n");
    tm_resolutionWrite(root, @"chapters/intro.tex", @"\\input chapters/deep/leaf\n");
    tm_resolutionWrite(root, @"unrelated.tex", @"\\documentclass{article}\n\\input{other/leaf}\n");
    NSString *nested = [TMProject mainFileURLForDocumentURL:leaf content:@"leaf"].lastPathComponent;
    NSURL *imported = tm_resolutionWrite(root, @"imported/sections/part.tex", @"part");
    tm_resolutionWrite(root, @"import-main.tex", @"\\documentclass{article}\n\\import{imported/}{intro}\n");
    tm_resolutionWrite(root, @"imported/intro.tex", @"\\subimport{sections/}{section}\n");
    tm_resolutionWrite(root, @"imported/sections/section.tex", @"\\input{part}\n");
    NSString *importRoot = [TMProject mainFileURLForDocumentURL:imported content:@"part"].lastPathComponent;
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    TM_ASSERT_EQ_STR(nested, @"chapter-main.tex");
    TM_ASSERT_EQ_STR(importRoot, @"import-main.tex");
}

TM_TEST(test_project_ignores_commented_references_and_declines_ambiguity) {
    NSURL *root = tm_resolutionProject();
    NSURL *chapter = tm_resolutionWrite(root, @"chapter.tex", @"chapter");
    tm_resolutionWrite(root, @"a.tex", @"\\documentclass{article}\n% \\input{chapter}\n");
    tm_resolutionWrite(root, @"b.tex", @"\\documentclass{article}\n\\begin{verbatim}\n\\input{chapter}\n\\end{verbatim}\n");
    NSURL *commented = [TMProject mainFileURLForDocumentURL:chapter content:@"chapter"];
    tm_resolutionWrite(root, @"a.tex", @"\\documentclass{article}\n\\include{chapter}\n");
    tm_resolutionWrite(root, @"b.tex", @"\\documentclass{article}\n\\input{chapter}\n");
    NSURL *ambiguous = [TMProject mainFileURLForDocumentURL:chapter content:@"chapter"];
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    TM_ASSERT_NIL(commented);
    TM_ASSERT_NIL(ambiguous);
}

TM_TEST(test_project_explicit_root_and_cycles_remain_supported) {
    NSURL *root = tm_resolutionProject();
    NSURL *chapter = tm_resolutionWrite(root, @"deep/chapter.tex", @"chapter");
    tm_resolutionWrite(root, @"main.tex", @"\\documentclass{article}\n\\input{loop}\n");
    tm_resolutionWrite(root, @"loop.tex", @"\\input{loop}\n\\input{deep/chapter}\n");
    tm_resolutionWrite(root, @"explicit.tex", @"fragment");
    NSString *cycleRoot = [TMProject mainFileURLForDocumentURL:chapter content:@"chapter"].lastPathComponent;
    NSString *explicit = [TMProject mainFileURLForDocumentURL:chapter content:@"% !TEX root = ../explicit.tex\n\\documentclass{article}"].lastPathComponent;
    NSURL *selfRoot = [TMProject mainFileURLForDocumentURL:chapter content:@"\\documentclass{article}"];
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    TM_ASSERT_EQ_STR(cycleRoot, @"main.tex");
    TM_ASSERT_EQ_STR(explicit, @"explicit.tex");
    TM_ASSERT_EQ_STR(selfRoot.path, chapter.path);
}

TM_TEST(test_project_nested_import_resets_directory_and_keeps_import_prefix) {
    NSURL *root = tm_resolutionProject();
    NSURL *leaf = tm_resolutionWrite(root, @"b/leaf.tex", @"leaf");
    tm_resolutionWrite(root, @"main.tex", @"\\documentclass{article}\n\\import{a/}{intro}\n");
    tm_resolutionWrite(root, @"a/intro.tex", @"\\import{b/}{nested/part}\n");
    tm_resolutionWrite(root, @"b/nested/part.tex", @"\\input{leaf}\n");
    tm_resolutionWrite(root, @"other.tex", @"\\documentclass{article}\n");
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:leaf content:@"leaf"].lastPathComponent, @"main.tex");
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
}
