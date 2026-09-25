#import "TMProject.h"
#import "TMMagicComments.h"
#import "TMLaTeXScanner.h"

@implementation TMFileNode
@end

@implementation TMProject

#pragma mark - 类型

+ (NSArray<NSString *> *)editableExtensions {
    return @[@"tex", @"latex", @"ltx", @"bib", @"sty", @"cls", @"bst", @"dtx", @"txt", @"md"];
}

+ (NSArray<NSString *> *)visibleExtensions {
    return [[self editableExtensions] arrayByAddingObjectsFromArray:@[@"png", @"jpg", @"jpeg", @"pdf", @"eps", @"svg"]];
}

+ (BOOL)isEditableFileURL:(NSURL *)url {
    NSString *ext = url.pathExtension.lowercaseString;
    return ext.length > 0 && [[self editableExtensions] containsObject:ext];
}

/// 编译产物与工具目录，不在文件树里显示。
+ (NSSet<NSString *> *)ignoredDirectoryNames {
    return [NSSet setWithArray:@[@"build", @"node_modules", @".git", @"_minted", @"auto"]];
}

#pragma mark - 文件树

+ (NSArray<TMFileNode *> *)fileTreeForDirectory:(NSURL *)directoryURL maxDepth:(NSUInteger)maxDepth {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *items = [fm contentsOfDirectoryAtURL:directoryURL
                               includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
                                                  options:NSDirectoryEnumerationSkipsHiddenFiles
                                                    error:nil];
    if (!items) return @[];

    NSMutableArray<TMFileNode *> *dirs = [NSMutableArray array];
    NSMutableArray<TMFileNode *> *files = [NSMutableArray array];
    NSArray<NSString *> *visible = [self visibleExtensions];
    NSSet<NSString *> *ignoredDirs = [self ignoredDirectoryNames];

    for (NSURL *url in items) {
        NSNumber *isDir = nil;
        [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        TMFileNode *node = [[TMFileNode alloc] init];
        node.url = url;
        node.name = url.lastPathComponent;
        node.isDirectory = isDir.boolValue;

        if (node.isDirectory) {
            if ([ignoredDirs containsObject:node.name.lowercaseString]) continue;
            node.children = maxDepth > 0 ? [self fileTreeForDirectory:url maxDepth:maxDepth - 1] : @[];
            // 空目录（没有任何可见文件）不显示，避免噪音
            if (node.children.count == 0) continue;
            [dirs addObject:node];
        } else {
            // 目录下的 .pdf 大多是编译产物，只显示与某个 .tex 不同名的 pdf（通常是插图）
            NSString *ext = url.pathExtension.lowercaseString;
            if (![visible containsObject:ext]) continue;
            if ([ext isEqualToString:@"pdf"]) {
                NSURL *twin = [url.URLByDeletingPathExtension URLByAppendingPathExtension:@"tex"];
                if ([fm fileExistsAtPath:twin.path]) continue;
            }
            node.children = @[];
            [files addObject:node];
        }
    }

    NSComparator byName = ^NSComparisonResult(TMFileNode *a, TMFileNode *b) {
        return [a.name localizedStandardCompare:b.name];
    };
    [dirs sortUsingComparator:byName];
    [files sortUsingComparator:byName];
    return [dirs arrayByAddingObjectsFromArray:files];
}

#pragma mark - 主文件推断

+ (BOOL)contentDeclaresDocumentClass:(NSString *)content {
    if (content.length == 0) return NO;
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 行首（允许空白）的 \documentclass，排除被注释掉的情况
        regex = [NSRegularExpression regularExpressionWithPattern:@"^[ \\t]*\\\\documentclass\\b"
                                                          options:NSRegularExpressionAnchorsMatchLines
                                                            error:nil];
    });
    return [regex firstMatchInString:content options:0 range:NSMakeRange(0, content.length)] != nil;
}

/// 返回 content 中 \input / \include / \subfile / \import 引用到的文件名（不含扩展名、去掉路径）。
+ (NSSet<NSString *> *)referencedBaseNamesInContent:(NSString *)content {
    NSMutableSet *names = [NSMutableSet set];
    if (content.length == 0) return names;
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(?:input|include|subfile|import|subimport)\\*?\\s*(?:\\{[^}]*\\}\\s*)?\\{([^}]+)\\}"
                                                          options:0
                                                            error:nil];
    });
    [regex enumerateMatchesInString:content options:0 range:NSMakeRange(0, content.length)
                         usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        NSString *arg = [[content substringWithRange:[m rangeAtIndex:1]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *base = arg.lastPathComponent.stringByDeletingPathExtension;
        if (base.length > 0) [names addObject:base];
    }];
    return names;
}

+ (NSArray<NSURL *> *)topLevelTeXFilesInDirectory:(NSURL *)directoryURL {
    NSArray<NSURL *> *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directoryURL
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:nil];
    NSMutableArray *result = [NSMutableArray array];
    for (NSURL *u in items) {
        if ([u.pathExtension.lowercaseString isEqualToString:@"tex"]) [result addObject:u];
    }
    return result;
}

/// 读取候选 .tex 的内容；按修改时间缓存，文件没变就不重复读盘（主文件推断每次加载 / 编译都会跑）。
+ (nullable NSString *)cachedContentsOfTeXFileURL:(NSURL *)url {
    static NSCache<NSString *, NSArray *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
    });
    NSDate *modified = nil;
    [url removeCachedResourceValueForKey:NSURLContentModificationDateKey];
    [url getResourceValue:&modified forKey:NSURLContentModificationDateKey error:nil];
    NSArray *entry = [cache objectForKey:url.path];
    if (modified && entry && [entry[0] isEqualToDate:modified]) return entry[1];
    NSString *content = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (modified && content) [cache setObject:@[modified, content] forKey:url.path];
    return content;
}

+ (nullable NSURL *)mainFileURLForDocumentURL:(NSURL *)documentURL content:(NSString *)content {
    if (!documentURL) return nil;
    content = content ?: @"";

    // 1. 魔法注释
    NSURL *root = [TMMagicComments rootFileURLForDocumentURL:documentURL content:content];
    if (root && [[NSFileManager defaultManager] fileExistsAtPath:root.path]) return root;

    // 2. 自己就是主文件
    if ([self contentDeclaresDocumentClass:content]) return documentURL;

    // 3. 同目录候选
    NSURL *dir = documentURL.URLByDeletingLastPathComponent;
    NSString *myBase = documentURL.lastPathComponent.stringByDeletingPathExtension;
    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    for (NSURL *u in [self topLevelTeXFilesInDirectory:dir]) {
        if ([u.URLByStandardizingPath isEqual:documentURL.URLByStandardizingPath]) continue;
        NSString *c = [self cachedContentsOfTeXFileURL:u];
        if (![self contentDeclaresDocumentClass:c]) continue;
        if ([[self referencedBaseNamesInContent:c] containsObject:myBase]) return u;
        [candidates addObject:u];
    }
    // 子目录里的 chapter 文件：再向上看一层父目录
    if (candidates.count == 0) {
        NSURL *parent = dir.URLByDeletingLastPathComponent;
        if (parent && ![parent isEqual:dir]) {
            NSString *relBase = [NSString stringWithFormat:@"%@/%@", dir.lastPathComponent, myBase];
            for (NSURL *u in [self topLevelTeXFilesInDirectory:parent]) {
                NSString *c = [self cachedContentsOfTeXFileURL:u];
                if (![self contentDeclaresDocumentClass:c]) continue;
                NSSet *refs = [self referencedBaseNamesInContent:c];
                if ([refs containsObject:myBase] || [refs containsObject:relBase]) return u;
                [candidates addObject:u];
            }
        }
    }
    return candidates.count == 1 ? candidates.firstObject : nil;
}

+ (BOOL)canRegenerateBibliographyForTeXFileURL:(NSURL *)texURL {
    NSString *content = [NSString stringWithContentsOfURL:texURL encoding:NSUTF8StringEncoding error:nil];
    if (content.length == 0) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"\\\\(bibliography|addbibresource)\\s*(?:\\[[^\\]]*\\])?\\s*\\{([^}]*)\\}"
                                                       options:0 error:nil];
    });
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:content];
    NSURL *dir = texURL.URLByDeletingLastPathComponent;
    for (NSTextCheckingResult *m in [re matchesInString:content options:0 range:NSMakeRange(0, content.length)]) {
        if ([scan isIgnorableAtIndex:m.range.location]) continue;   // 注释掉的不算
        BOOL bibtex = [[content substringWithRange:[m rangeAtIndex:1]] isEqualToString:@"bibliography"];
        for (NSString *part in [[content substringWithRange:[m rangeAtIndex:2]] componentsSeparatedByString:@","]) {
            NSString *name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) continue;
            if (bibtex && ![name.pathExtension.lowercaseString isEqualToString:@"bib"]) name = [name stringByAppendingPathExtension:@"bib"];
            NSString *path = name.isAbsolutePath ? name : [dir.path stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;
        }
    }
    return NO;
}

+ (nullable NSURL *)guessMainFileInDirectory:(NSURL *)directoryURL {
    NSArray<NSString *> *preferredNames = @[@"main", @"thesis", @"paper", @"report", @"article", @"book", @"dissertation"];
    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    NSMutableDictionary<NSURL *, NSNumber *> *refCounts = [NSMutableDictionary dictionary];

    for (NSURL *u in [self topLevelTeXFilesInDirectory:directoryURL]) {
        NSString *c = [self cachedContentsOfTeXFileURL:u];
        if (![self contentDeclaresDocumentClass:c]) continue;
        [candidates addObject:u];
        refCounts[u] = @([self referencedBaseNamesInContent:c].count);
    }
    if (candidates.count == 0) return nil;
    if (candidates.count == 1) return candidates.firstObject;

    for (NSString *name in preferredNames) {
        for (NSURL *u in candidates) {
            if ([u.lastPathComponent.stringByDeletingPathExtension.lowercaseString isEqualToString:name]) return u;
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [refCounts[b] compare:refCounts[a]];
    }];
    return candidates.firstObject;
}

@end
