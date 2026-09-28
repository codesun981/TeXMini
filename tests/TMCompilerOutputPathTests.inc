TM_TEST(test_output_paths_defaults_and_managed_cache) {
    NSURL *source = [NSURL fileURLWithPath:@"/projects/paper/main.tex"];
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:source auxFilesBesideSource:NO extraArguments:nil];
    TM_ASSERT_EQ_STR(paths.pdfURL.path, @"/projects/paper/main.pdf");
    TM_ASSERT_EQ_STR(paths.synctexURL.path, @"/projects/paper/main.synctex.gz");
    TM_ASSERT_EQ_STR(paths.auxiliaryDirectoryURL.path, [TMCompiler auxiliaryDirectoryForTeXFileURL:source].path);
    TM_ASSERT_TRUE(paths.usesManagedAuxiliaryDirectory);
    paths = [TMCompiler outputPathsForTeXFileURL:source auxFilesBesideSource:YES extraArguments:@[]];
    TM_ASSERT_EQ_STR([paths auxiliaryFileURLWithExtension:@"aux"].path, @"/projects/paper/main.aux");
    TM_ASSERT_TRUE(!paths.usesManagedAuxiliaryDirectory);
}

TM_TEST(test_output_paths_aliases_last_value_and_spaces) {
    NSURL *source = [NSURL fileURLWithPath:@"/projects/paper/main.tex"];
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:source auxFilesBesideSource:YES
        extraArguments:@[@"-outdir=ignored", @"--output-directory", @"custom output", @"-jobname=old", @"--jobname", @"%A-final"]];
    TM_ASSERT_EQ_STR(paths.outputDirectoryURL.path, @"/projects/paper/custom output");
    TM_ASSERT_EQ_STR(paths.pdfURL.path, @"/projects/paper/custom output/main-final.pdf");
    TM_ASSERT_EQ_STR(paths.auxiliaryDirectoryURL.path, paths.outputDirectoryURL.path);
    TM_ASSERT_EQ_STR(paths.synctexURL.path, @"/projects/paper/custom output/main-final.synctex.gz");
}

TM_TEST(test_output_paths_custom_auxiliary_is_never_managed) {
    NSURL *source = [NSURL fileURLWithPath:@"/projects/paper/main.tex"];
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:source auxFilesBesideSource:NO
        extraArguments:@[@"--auxdir=ignored", @"--aux-directory", @"../shared aux", @"-outdir=/tmp/output", @"-jobname=article"]];
    TM_ASSERT_EQ_STR(paths.pdfURL.path, @"/tmp/output/article.pdf");
    TM_ASSERT_EQ_STR([paths auxiliaryFileURLWithExtension:@"bbl"].path, @"/projects/shared aux/article.bbl");
    TM_ASSERT_TRUE(!paths.usesManagedAuxiliaryDirectory);
}

TM_TEST(test_output_paths_empty_overrides_restore_engine_defaults) {
    NSURL *source = [NSURL fileURLWithPath:@"/projects/paper/main.tex"];
    TMCompilerOutputPaths *paths = [TMCompiler outputPathsForTeXFileURL:source auxFilesBesideSource:NO
        extraArguments:@[@"-outdir=build", @"--outdir=", @"--aux-directory=", @"--jobname="]];
    TM_ASSERT_EQ_STR(paths.pdfURL.path, @"/projects/paper/main.pdf");
    TM_ASSERT_EQ_STR(paths.auxiliaryDirectoryURL.path, @"/projects/paper");
    TM_ASSERT_TRUE(!paths.usesManagedAuxiliaryDirectory);
}
