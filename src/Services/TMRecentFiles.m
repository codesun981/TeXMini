#import "TMRecentFiles.h"

static NSString *const kTMRecentFilesKey = @"TMRecentFiles";
static const NSUInteger kTMRecentFilesMax = 10;

@implementation TMRecentFiles

+ (NSMutableArray<NSString *> *)paths {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kTMRecentFilesKey];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (id item in stored) {
        if ([item isKindOfClass:[NSString class]]) [paths addObject:item];
    }
    return paths;
}

+ (void)store:(NSArray<NSString *> *)paths {
    [[NSUserDefaults standardUserDefaults] setObject:paths forKey:kTMRecentFilesKey];
}

+ (NSArray<NSURL *> *)recentFileURLs {
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (NSString *path in [self paths]) {
        [urls addObject:[NSURL fileURLWithPath:path]];
    }
    return urls;
}

+ (void)noteFileURL:(NSURL *)url {
    NSString *path = url.URLByStandardizingPath.path;
    if (path.length == 0) return;
    NSMutableArray<NSString *> *paths = [self paths];
    [paths removeObject:path];
    [paths insertObject:path atIndex:0];
    while (paths.count > kTMRecentFilesMax) [paths removeLastObject];
    [self store:paths];
}

+ (void)removeFileURL:(NSURL *)url {
    NSMutableArray<NSString *> *paths = [self paths];
    [paths removeObject:url.URLByStandardizingPath.path ?: @""];
    [self store:paths];
}

+ (void)clear {
    [self store:@[]];
}

@end
