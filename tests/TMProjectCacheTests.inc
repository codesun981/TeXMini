// 候选主文件解析缓存：观察结果与解析次数，不依赖缓存内部表示。
#include <sys/stat.h>
#include <fcntl.h>
@interface TMProject (CacheTestHooks)
+ (BOOL)contentDeclaresDocumentClass:(NSString *)content;
+ (NSArray *)fileReferencesInContent:(NSString *)content;
@end
@interface TMCountingProject : TMProject
@end
static NSUInteger tmProjectClassParses, tmProjectReferenceParses;
@implementation TMCountingProject
+ (BOOL)contentDeclaresDocumentClass:(NSString *)content {
    tmProjectClassParses++;
    return [super contentDeclaresDocumentClass:content];
}
+ (NSArray *)fileReferencesInContent:(NSString *)content {
    tmProjectReferenceParses++;
    return [super fileReferencesInContent:content];
}
@end

static NSURL *tm_projectCacheRoot(void) {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    return root.URLByResolvingSymlinksInPath;
}
static NSURL *tm_projectCacheWrite(NSURL *root, NSString *name, NSString *text) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return url;
}

TM_TEST(test_project_cache_reuses_candidate_parses) {
    NSURL *root = tm_projectCacheRoot();
    NSURL *main = tm_projectCacheWrite(root, @"main.tex", @"\\documentclass{article}\n\\input{notes}\n");
    tm_projectCacheWrite(root, @"notes.tex", @"body\n");
    tmProjectClassParses = tmProjectReferenceParses = 0;
    TM_ASSERT_EQ_STR([TMCountingProject guessMainFileInDirectory:root].lastPathComponent, main.lastPathComponent);
    NSUInteger classes = tmProjectClassParses, references = tmProjectReferenceParses;
    TM_ASSERT_TRUE(classes > 0 && references > 0);
    TM_ASSERT_EQ_STR([TMCountingProject guessMainFileInDirectory:root].lastPathComponent, main.lastPathComponent);
    TM_ASSERT_EQ_INT(tmProjectClassParses, classes);
    TM_ASSERT_EQ_INT(tmProjectReferenceParses, references);
    NSURL *notes = [root URLByAppendingPathComponent:@"notes.tex"];
    for (NSString *body in @[@"first unsaved edit", @"second unsaved edit"]) {
        TM_ASSERT_EQ_STR([TMCountingProject mainFileURLForDocumentURL:notes content:body].lastPathComponent, main.lastPathComponent);
    }
    TM_ASSERT_EQ_INT(tmProjectReferenceParses, references);
    [[NSFileManager defaultManager] removeItemAtURL:root error:nil];
}

TM_TEST(test_project_cache_detects_equal_size_edits_with_restored_mtime) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = tm_projectCacheRoot();
    NSString *before = @"\\documentclass{article}\n\\input{notes}\n";
    NSString *after = @"%documentclass{article}\n\\input{notes}\n";
    TM_ASSERT_EQ_INT(before.length, after.length);
    NSURL *main = tm_projectCacheWrite(root, @"main.tex", before);
    TM_ASSERT_EQ_STR([TMProject guessMainFileInDirectory:root].lastPathComponent, main.lastPathComponent);
    struct stat original, updated;
    TM_ASSERT_EQ_INT(stat(main.fileSystemRepresentation, &original), 0);
    struct timespec times[] = {original.st_atimespec, original.st_mtimespec};
    // 原地同长度写入，inode 不变；恢复 mtime 后仍必须从 ctime 识别变化。
    TM_ASSERT_TRUE([after writeToURL:main atomically:NO encoding:NSUTF8StringEncoding error:nil]);
    TM_ASSERT_EQ_INT(utimensat(AT_FDCWD, main.fileSystemRepresentation, times, 0), 0);
    TM_ASSERT_EQ_INT(stat(main.fileSystemRepresentation, &updated), 0);
    TM_ASSERT_EQ_INT(updated.st_ino, original.st_ino);
    TM_ASSERT_EQ_INT(updated.st_size, original.st_size);
    TM_ASSERT_EQ_INT(updated.st_mtimespec.tv_nsec, original.st_mtimespec.tv_nsec);
    TM_ASSERT_NIL([TMProject guessMainFileInDirectory:root]);
    // 原子替换也保留旧 mtime，必须重新识别主文件。
    tm_projectCacheWrite(root, @"main.tex", before);
    TM_ASSERT_EQ_INT(utimensat(AT_FDCWD, main.fileSystemRepresentation, times, 0), 0);
    TM_ASSERT_EQ_STR([TMProject guessMainFileInDirectory:root].lastPathComponent, main.lastPathComponent);
    [fm removeItemAtURL:root error:nil];
}

TM_TEST(test_project_cache_refreshes_parent_reference_relationships) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = tm_projectCacheRoot();
    NSURL *chapters = [root URLByAppendingPathComponent:@"chapters"];
    [fm createDirectoryAtURL:chapters withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *intro = tm_projectCacheWrite(chapters, @"intro.tex", @"intro");
    NSURL *a = tm_projectCacheWrite(root, @"a.tex", @"\\documentclass{article}\n\\input{chapters/intro}\n");
    NSURL *b = tm_projectCacheWrite(root, @"b.tex", @"\\documentclass{article}\n\\input{chapters/other}\n");
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:intro content:@"intro"].lastPathComponent, a.lastPathComponent);
    tm_projectCacheWrite(root, @"a.tex", @"\\documentclass{article}\n\\input{chapters/other}\n");
    tm_projectCacheWrite(root, @"b.tex", @"\\documentclass{article}\n\\input{chapters/intro}\n");
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:intro content:@"edited intro"].lastPathComponent, b.lastPathComponent);
    [fm removeItemAtURL:root error:nil];
}

TM_TEST(test_project_cache_tracks_candidates_and_magic_root_existence) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *root = tm_projectCacheRoot();
    NSURL *notes = tm_projectCacheWrite(root, @"notes.tex", @"notes");
    TM_ASSERT_NIL([TMProject mainFileURLForDocumentURL:notes content:@"notes"]);
    NSURL *main = tm_projectCacheWrite(root, @"main.tex", @"\\documentclass{article}\n");
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:notes content:@"notes"].lastPathComponent, main.lastPathComponent);
    NSURL *other = tm_projectCacheWrite(root, @"other.tex", @"\\documentclass{book}\n");
    TM_ASSERT_NIL([TMProject mainFileURLForDocumentURL:notes content:@"notes"]);
    TM_ASSERT_TRUE([fm removeItemAtURL:other error:nil]);
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:notes content:@"notes"].lastPathComponent, main.lastPathComponent);
    NSURL *renamed = [root URLByAppendingPathComponent:@"renamed.tex"];
    TM_ASSERT_TRUE([fm moveItemAtURL:main toURL:renamed error:nil]);
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:notes content:@"notes"].lastPathComponent, renamed.lastPathComponent);
    NSURL *explicit = tm_projectCacheWrite(root, @"explicit.tex", @"fragment");
    NSString *magic = @"% !TEX root = explicit.tex\n\\documentclass{article}\n";
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:notes content:magic].lastPathComponent, explicit.lastPathComponent);
    TM_ASSERT_TRUE([fm removeItemAtURL:explicit error:nil]);
    TM_ASSERT_EQ_STR([TMProject mainFileURLForDocumentURL:notes content:magic].lastPathComponent, notes.lastPathComponent);
    [fm removeItemAtURL:root error:nil];
}
