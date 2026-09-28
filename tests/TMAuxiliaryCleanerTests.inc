#import "TMAuxiliaryCleaner.h"

static NSURL *tm_cleanerDirectory(void) {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [@"tm-aux-cleaner-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

static void tm_cleanerWrite(NSURL *directory, NSString *name, NSString *content) {
    NSURL *url = [directory URLByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

TM_TEST(test_aux_cleaner_respects_custom_outputs_and_unrecoverable_bbl) {
    NSURL *dir = tm_cleanerDirectory(), *tex = [dir URLByAppendingPathComponent:@"main.tex"];
    tm_cleanerWrite(dir, @"main.tex", @"\\documentclass{article}\n");
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:tex auxFilesBesideSource:NO extraArguments:@[@"-outdir=output", @"-auxdir=aux", @"-jobname=paper"]];
    NSURL *cache = [dir URLByAppendingPathComponent:@"old-cache"];
    NSArray<NSURL *> *directories = @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL, cache];
    for (NSURL *directory in directories) {
        for (NSString *name in @[@"main.aux", @"paper.log", @"main.bbl", @"paper.bbl", @"paper.ist", @"paper.xdy", @"paper.pdf", @"notes.txt", @"unrelated.aux"]) tm_cleanerWrite(directory, name, @"data");
        [NSFileManager.defaultManager createDirectoryAtURL:[directory URLByAppendingPathComponent:@"paper.toc"] withIntermediateDirectories:YES attributes:nil error:nil];
        tm_cleanerWrite(directory, @"paper.toc/keep.txt", @"user data");
    }
    TM_ASSERT_TRUE([TMAuxiliaryCleaner cleanAuxiliaryFilesForTeXFileURL:tex outputPaths:paths legacyAuxiliaryDirectoryURL:[dir URLByAppendingPathComponent:@"old-cache"] keepingBibliography:NO]);
    for (NSURL *directory in directories) {
        for (NSString *name in @[@"main.bbl", @"paper.bbl", @"paper.ist", @"paper.xdy", @"paper.pdf", @"notes.txt", @"unrelated.aux", @"paper.toc/keep.txt"]) TM_ASSERT_TRUE([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:name].path]);
        TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"main.aux"].path]);
        TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"paper.log"].path]);
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
}

TM_TEST(test_aux_cleaner_removes_regenerable_bbl_unless_explicitly_kept) {
    NSURL *dir = tm_cleanerDirectory(), *tex = [dir URLByAppendingPathComponent:@"main.tex"];
    tm_cleanerWrite(dir, @"main.tex", @"\\documentclass{article}\n\\bibliography{refs}\n");
    tm_cleanerWrite(dir, @"refs.bib", @"@article{a, title={A}}");
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:tex auxFilesBesideSource:YES extraArguments:@[@"-outdir=output", @"-auxdir=aux", @"-jobname=paper"]];
    for (NSURL *directory in @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) tm_cleanerWrite(directory, @"paper.bbl", @"bibliography");
    TM_ASSERT_TRUE([TMAuxiliaryCleaner cleanAuxiliaryFilesForTeXFileURL:tex outputPaths:paths legacyAuxiliaryDirectoryURL:[dir URLByAppendingPathComponent:@"old-cache"] keepingBibliography:YES]);
    for (NSURL *directory in @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) TM_ASSERT_TRUE([NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"paper.bbl"].path]);
    TM_ASSERT_TRUE([TMAuxiliaryCleaner cleanAuxiliaryFilesForTeXFileURL:tex outputPaths:paths legacyAuxiliaryDirectoryURL:[dir URLByAppendingPathComponent:@"old-cache"] keepingBibliography:NO]);
    for (NSURL *directory in @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:@"paper.bbl"].path]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}

TM_TEST(test_aux_cleaner_only_removes_recorded_chapter_aux_inside_output) {
    NSURL *dir = tm_cleanerDirectory(), *outside = tm_cleanerDirectory(), *tex = [dir URLByAppendingPathComponent:@"main.tex"];
    tm_cleanerWrite(dir, @"main.tex", @"\\documentclass{article}\n");
    tm_cleanerWrite(dir, @"chapters/one.tex", @"Chapter");
    tm_cleanerWrite(dir, @"linked/evil.tex", @"Chapter");
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:tex auxFilesBesideSource:NO extraArguments:@[@"-outdir=output", @"-auxdir=aux"]];
    tm_cleanerWrite(paths.auxiliaryDirectoryURL, @"main.aux", @"\\@input{chapters/one.aux}\n\\@input{linked/evil.aux}\n\\@input{../outside.aux}\n");
    tm_cleanerWrite(paths.auxiliaryDirectoryURL, @"chapters/one.aux", @"generated");
    tm_cleanerWrite(paths.auxiliaryDirectoryURL, @"chapters/unknown.aux", @"unrelated");
    tm_cleanerWrite(outside, @"evil.aux", @"external");
    [NSFileManager.defaultManager createSymbolicLinkAtURL:[paths.auxiliaryDirectoryURL URLByAppendingPathComponent:@"linked"] withDestinationURL:outside error:nil];
    TM_ASSERT_TRUE([TMAuxiliaryCleaner cleanAuxiliaryFilesForTeXFileURL:tex outputPaths:paths legacyAuxiliaryDirectoryURL:[dir URLByAppendingPathComponent:@"old-cache"] keepingBibliography:NO]);
    TM_ASSERT_TRUE(![NSFileManager.defaultManager fileExistsAtPath:[paths.auxiliaryDirectoryURL URLByAppendingPathComponent:@"chapters/one.aux"].path]);
    TM_ASSERT_TRUE([NSFileManager.defaultManager fileExistsAtPath:[paths.auxiliaryDirectoryURL URLByAppendingPathComponent:@"chapters/unknown.aux"].path]);
    TM_ASSERT_TRUE([NSFileManager.defaultManager fileExistsAtPath:[outside URLByAppendingPathComponent:@"evil.aux"].path]);
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
    [NSFileManager.defaultManager removeItemAtURL:outside error:nil];
}

TM_TEST(test_aux_cleaner_child_bibliography_is_checked_independently) {
    NSURL *dir = tm_cleanerDirectory();
    tm_cleanerWrite(dir, @"main.tex", @"\\documentclass{article}\n\\bibliography{refs}\n");
    tm_cleanerWrite(dir, @"refs.bib", @"@article{a, title={A}}");
    tm_cleanerWrite(dir, @"chapter.tex", @"A chapter without its bibliography sources\n");
    for (NSString *name in @[@"main", @"chapter"]) {
        NSURL *tex = [dir URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"tex"]];
        TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:tex auxFilesBesideSource:YES extraArguments:@[@"-outdir=output", @"-auxdir=aux"]];
        for (NSURL *directory in @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) tm_cleanerWrite(directory, [name stringByAppendingPathExtension:@"bbl"], @"bibliography");
        TM_ASSERT_TRUE([TMAuxiliaryCleaner cleanAuxiliaryFilesForTeXFileURL:tex outputPaths:paths legacyAuxiliaryDirectoryURL:nil keepingBibliography:NO]);
        for (NSURL *directory in @[dir, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) {
            BOOL remains = [NSFileManager.defaultManager fileExistsAtPath:[directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"bbl"]].path];
            TM_ASSERT_TRUE(remains == [name isEqualToString:@"chapter"]);
        }
    }
    [NSFileManager.defaultManager removeItemAtURL:dir error:nil];
}
