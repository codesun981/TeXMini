#import "TMRecentFiles.h"

static NSString *const kTMRecentFilesKey = @"TMRecentFiles";
static NSString *const kTMRecentFoldersKey = @"TMRecentFolders";
static const NSUInteger kTMRecentMax = 10;

@implementation TMRecentFiles

+ (NSMutableArray<NSString *> *)pathsForKey:(NSString *)key {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]]) [paths addObject:item];
    }
    return paths;
}

+ (void)store:(NSArray<NSString *> *)paths forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:key];
}

+ (NSArray<NSURL *> *)urlsForKey:(NSString *)key {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *path in [self pathsForKey:key]) {
        [urls addObject:[NSURL fileURLWithPath:path]];
    }
    return urls;
}

+ (void)noteURL:(NSURL *)url forKey:(NSString *)key {
    NSString *path = url.URLByStandardizingPath.path;
    if (path.length == 0) return;
    NSMutableArray<NSString *> *paths = [self pathsForKey:key];
    [paths removeObject:path];
    [paths insertObject:path atIndex:0];
    while (paths.count > kTMRecentMax) [paths removeLastObject];
    [self store:paths forKey:key];
}

+ (void)removeURL:(NSURL *)url forKey:(NSString *)key {
    NSMutableArray<NSString *> *paths = [self pathsForKey:key];
    [paths removeObject:url.URLByStandardizingPath.path ?: @""];
    [self store:paths forKey:key];
}

#pragma mark - 文件

+ (NSArray<NSURL *> *)recentFileURLs { return [self urlsForKey:kTMRecentFilesKey]; }
+ (void)noteFileURL:(NSURL *)url { [self noteURL:url forKey:kTMRecentFilesKey]; }
+ (void)removeFileURL:(NSURL *)url { [self removeURL:url forKey:kTMRecentFilesKey]; }

#pragma mark - 文件夹

+ (NSArray<NSURL *> *)recentFolderURLs { return [self urlsForKey:kTMRecentFoldersKey]; }
+ (void)noteFolderURL:(NSURL *)url { [self noteURL:url forKey:kTMRecentFoldersKey]; }
+ (void)removeFolderURL:(NSURL *)url { [self removeURL:url forKey:kTMRecentFoldersKey]; }

+ (void)clear {
    [self store:@[] forKey:kTMRecentFilesKey];
    [self store:@[] forKey:kTMRecentFoldersKey];
    [self noteSessionFolderURL:nil fileURL:nil selection:0];
}

#pragma mark - 上次会话

static NSString *const kTMSessionFolderKey = @"TMSessionFolder";
static NSString *const kTMSessionFileKey = @"TMSessionFile";
static NSString *const kTMSessionSelectionKey = @"TMSessionSelection";

+ (void)noteSessionFolderURL:(nullable NSURL *)folder fileURL:(nullable NSURL *)file selection:(NSUInteger)selection {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *folderPath = folder.URLByStandardizingPath.path;
    NSString *filePath = file.URLByStandardizingPath.path;
    if (folderPath.length) [d setObject:folderPath forKey:kTMSessionFolderKey]; else [d removeObjectForKey:kTMSessionFolderKey];
    if (filePath.length) [d setObject:filePath forKey:kTMSessionFileKey]; else [d removeObjectForKey:kTMSessionFileKey];
    [d setInteger:(NSInteger)selection forKey:kTMSessionSelectionKey];
}

+ (nullable NSURL *)existingURLForKey:(NSString *)key directory:(BOOL)wantDirectory {
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    BOOL isDir = NO;
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] || isDir != wantDirectory) return nil;
    return [NSURL fileURLWithPath:path isDirectory:wantDirectory];
}

+ (nullable NSURL *)sessionFolderURL { return [self existingURLForKey:kTMSessionFolderKey directory:YES]; }
+ (nullable NSURL *)sessionFileURL { return [self existingURLForKey:kTMSessionFileKey directory:NO]; }

+ (NSUInteger)sessionSelection {
    NSInteger loc = [[NSUserDefaults standardUserDefaults] integerForKey:kTMSessionSelectionKey];
    return loc > 0 ? (NSUInteger)loc : 0;
}

@end
