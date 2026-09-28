#import "TMDocument.h"
#import "TMProject.h"
#import "TMMagicComments.h"
#import "TMLaTeXScanner.h"
#include <sys/stat.h>

@interface TMProjectReference : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL changesInputDirectory;
@property (nonatomic) BOOL resetsInputDirectory;
@property (nonatomic, copy) NSString *importDirectory;
@end
@implementation TMProjectReference
@end

@interface TMProjectCandidate : NSObject
@property (nonatomic, copy) NSArray<NSNumber *> *fingerprint;
@property (nonatomic) BOOL declaresDocumentClass;
@property (nonatomic, copy) NSArray<TMProjectReference *> *references;
@end
@implementation TMProjectCandidate
@end

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

/// 保留完整相对路径及 import 的查找上下文；普通 input 的路径相对于编译工作目录。
+ (NSArray<TMProjectReference *> *)fileReferencesInContent:(NSString *)content {
    NSMutableArray *references = [NSMutableArray array];
    if (content.length == 0) return references;
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"\\\\(input|include|subfile|import|subimport)\\*?(?![A-Za-z@])\\s*(?:\\{([^{}]*)\\}|([^\\s%{}]+))(?:\\s*\\{([^{}]*)\\})?"
                                                          options:0
                                                            error:nil];
    });
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:content];
    NSCharacterSet *dynamic = [NSCharacterSet characterSetWithCharactersInString:@"\\{}#$%"];
    [regex enumerateMatchesInString:content options:0 range:NSMakeRange(0, content.length)
                         usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        if ([scan isIgnorableAtIndex:m.range.location]) return;
        NSString *command = [content substringWithRange:[m rangeAtIndex:1]];
        NSRange first = [m rangeAtIndex:2].location != NSNotFound ? [m rangeAtIndex:2] : [m rangeAtIndex:3];
        NSString *path = [[content substringWithRange:first] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL imports = [command isEqualToString:@"import"] || [command isEqualToString:@"subimport"];
        NSString *importDirectory = imports ? path : nil;
        if (imports) {
            if ([m rangeAtIndex:4].location == NSNotFound) return;
            path = [path stringByAppendingPathComponent:[content substringWithRange:[m rangeAtIndex:4]]];
        }
        if (!path.length || [path rangeOfCharacterFromSet:dynamic].location != NSNotFound) return;
        if (!path.pathExtension.length) path = [path stringByAppendingPathExtension:@"tex"];
        TMProjectReference *reference = [TMProjectReference new];
        reference.path = path;
        reference.importDirectory = importDirectory;
        reference.resetsInputDirectory = [command isEqualToString:@"import"];
        reference.changesInputDirectory = imports || [command isEqualToString:@"subfile"];
        [references addObject:reference];
    }];
    return references;
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

static NSArray<NSNumber *> *TMCandidateFingerprint(NSURL *url) {
    struct stat info;
    if (stat(url.fileSystemRepresentation, &info) != 0) return nil;
    return @[@(info.st_dev), @(info.st_ino), @(info.st_size),
             @(info.st_mtimespec.tv_sec), @(info.st_mtimespec.tv_nsec),
             @(info.st_ctimespec.tv_sec), @(info.st_ctimespec.tv_nsec)];
}

/// 仅缓存候选的解析事实，不缓存最终主文件关系；每次推断仍检查目录成员与文件指纹。
+ (nullable TMProjectCandidate *)cachedCandidateForTeXFileURL:(NSURL *)url {
    static NSCache<NSString *, TMProjectCandidate *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 256;
    });
    NSString *key = url.URLByStandardizingPath.path;
    NSArray *fingerprint = TMCandidateFingerprint(url);
    if (!fingerprint) { [cache removeObjectForKey:key]; return nil; }
    TMProjectCandidate *entry = [cache objectForKey:key];
    if ([entry.fingerprint isEqual:fingerprint]) return entry;
    NSString *content = [TMDocument documentWithContentsOfURL:url error:nil].content;
    if (!content) { [cache removeObjectForKey:key]; return nil; }
    entry = [TMProjectCandidate new];
    entry.fingerprint = fingerprint;
    entry.declaresDocumentClass = [self contentDeclaresDocumentClass:content];
    entry.references = [self fileReferencesInContent:content];
    // 读取期间发生原子替换或写入时，不把快照绑定到旧指纹；下次调用重新读取。
    if ([fingerprint isEqual:TMCandidateFingerprint(url)]) [cache setObject:entry forKey:key];
    else [cache removeObjectForKey:key];
    return entry;
}

+ (BOOL)fileURL:(NSURL *)fileURL referencesDocument:(NSString *)targetPath
      inputDirectory:(NSURL *)inputDirectory rootDirectory:(NSURL *)rootDirectory visited:(NSMutableSet<NSString *> *)visited {
    // 限制依赖图规模并切断循环；每次调用只重新读取指纹改变的节点。
    if (visited.count >= 128) return NO;
    NSString *key = [NSString stringWithFormat:@"%@|%@", fileURL.path, inputDirectory.path];
    if ([visited containsObject:key]) return NO;
    [visited addObject:key];
    TMProjectCandidate *file = [self cachedCandidateForTeXFileURL:fileURL];
    for (TMProjectReference *reference in file.references) {
        NSURL *base = reference.resetsInputDirectory ? rootDirectory : inputDirectory;
        NSURL *child = [NSURL fileURLWithPath:reference.path relativeToURL:base].URLByStandardizingPath.absoluteURL;
        if ([child.URLByResolvingSymlinksInPath.path isEqualToString:targetPath]) return YES;
        if (![self.editableExtensions containsObject:child.pathExtension.lowercaseString]) continue;
        NSURL *childInputDirectory = reference.importDirectory
            ? [NSURL fileURLWithPath:reference.importDirectory isDirectory:YES relativeToURL:base].URLByStandardizingPath.absoluteURL
            : reference.changesInputDirectory ? child.URLByDeletingLastPathComponent : inputDirectory;
        if ([self fileURL:child referencesDocument:targetPath inputDirectory:childInputDirectory rootDirectory:rootDirectory visited:visited]) return YES;
    }
    return NO;
}

+ (nullable NSURL *)mainFileURLForDocumentURL:(NSURL *)documentURL content:(NSString *)content {
    if (!documentURL) return nil;
    content = content ?: @"";

    // 1. 魔法注释
    NSURL *root = [TMMagicComments rootFileURLForDocumentURL:documentURL content:content];
    if (root && [[NSFileManager defaultManager] fileExistsAtPath:root.path]) return root;

    // 2. 自己就是主文件
    if ([self contentDeclaresDocumentClass:content]) return documentURL;

    // 3. 从当前目录向上寻找确实引用当前文件的主文件；最多检查 8 层祖先，不递归扫描目录。
    NSURL *dir = documentURL.URLByDeletingLastPathComponent;
    NSString *targetPath = documentURL.URLByStandardizingPath.URLByResolvingSymlinksInPath.path;
    NSArray<NSURL *> *fallbackCandidates = nil;
    for (NSUInteger level = 0; level < 8; level++) {
        NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
        NSMutableArray<NSURL *> *matches = [NSMutableArray array];
        for (NSURL *u in [self topLevelTeXFilesInDirectory:dir]) {
            if ([u.URLByStandardizingPath isEqual:documentURL.URLByStandardizingPath]) continue;
            TMProjectCandidate *candidate = [self cachedCandidateForTeXFileURL:u];
            if (!candidate.declaresDocumentClass) continue;
            [candidates addObject:u];
            if ([self fileURL:u referencesDocument:targetPath inputDirectory:dir rootDirectory:dir visited:[NSMutableSet set]]) [matches addObject:u];
        }
        // 两个主文件共同引用同一章节时无法确定目标，交给显式 root，不能依赖目录枚举顺序。
        if (matches.count) return matches.count == 1 ? matches.firstObject : nil;
        if (level < 2 && !fallbackCandidates.count && candidates.count) fallbackCandidates = candidates;
        NSURL *parent = dir.URLByDeletingLastPathComponent;
        if (!parent || [parent isEqual:dir]) break;
        dir = parent;
    }
    // 保留原来的便捷回退：仅当前目录或紧邻父目录恰好有一个候选时采用它。
    return fallbackCandidates.count == 1 ? fallbackCandidates.firstObject : nil;
}

+ (BOOL)canRegenerateBibliographyForTeXFileURL:(NSURL *)texURL {
    NSString *content = [TMDocument documentWithContentsOfURL:texURL error:nil].content;
    if (content.length == 0) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"\\\\(bibliography|addbibresource)\\s*(?:\\[[^\\]]*\\])?\\s*\\{([^}]*)\\}"
                                                       options:0 error:nil];
    });
    TMLaTeXScanResult *scan = [TMLaTeXScanner scanString:content];
    // 输入依赖可能增加其他数据库或宏定义；无法解释完整 TeX 程序时保守保留 .bbl。
    NSRegularExpression *inputs = [NSRegularExpression regularExpressionWithPattern:@"\\\\(?:input|include|subfile|import|subimport)(?![A-Za-z@])" options:0 error:nil];
    for (NSTextCheckingResult *input in [inputs matchesInString:content options:0 range:NSMakeRange(0, content.length)]) {
        if (![scan isIgnorableAtIndex:input.range.location]) return NO;
    }
    NSURL *dir = texURL.URLByDeletingLastPathComponent;
    BOOL foundResource = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSCharacterSet *dynamicCharacters = [NSCharacterSet characterSetWithCharactersInString:@"\\{}#$%"];
    for (NSTextCheckingResult *m in [re matchesInString:content options:0 range:NSMakeRange(0, content.length)]) {
        if ([scan isIgnorableAtIndex:m.range.location]) continue;   // 注释掉的不算
        BOOL bibtex = [[content substringWithRange:[m rangeAtIndex:1]] isEqualToString:@"bibliography"];
        NSString *resources = [content substringWithRange:[m rangeAtIndex:2]];
        for (NSString *part in bibtex ? [resources componentsSeparatedByString:@","] : @[resources]) {
            NSString *name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            // 只要一个来源丢失或依赖宏展开，就不能证明整份 .bbl 可以恢复。
            if (name.length == 0 || [name rangeOfCharacterFromSet:dynamicCharacters].location != NSNotFound) return NO;
            if (bibtex && ![name.pathExtension.lowercaseString isEqualToString:@"bib"]) name = [name stringByAppendingPathExtension:@"bib"];
            NSString *path = name.isAbsolutePath ? name : [dir.path stringByAppendingPathComponent:name];
            BOOL isDirectory = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory || ![fm isReadableFileAtPath:path]) return NO;
            foundResource = YES;
        }
    }
    return foundResource;
}

+ (nullable NSURL *)guessMainFileInDirectory:(NSURL *)directoryURL {
    NSArray<NSString *> *preferredNames = @[@"main", @"thesis", @"paper", @"report", @"article", @"book", @"dissertation"];
    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    NSMutableDictionary<NSURL *, NSNumber *> *refCounts = [NSMutableDictionary dictionary];

    for (NSURL *u in [self topLevelTeXFilesInDirectory:directoryURL]) {
        TMProjectCandidate *candidate = [self cachedCandidateForTeXFileURL:u];
        if (!candidate.declaresDocumentClass) continue;
        [candidates addObject:u];
        refCounts[u] = @(candidate.references.count);
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
