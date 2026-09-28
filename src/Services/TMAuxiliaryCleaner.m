#import "TMAuxiliaryCleaner.h"
#import "TMCompiler.h"
#import "TMDocument.h"
#import "TMProject.h"
#import <sys/stat.h>
#import <errno.h>

@implementation TMAuxiliaryCleaner

static BOOL TMURLIsInsideDirectory(NSURL *url, NSURL *directory) {
    NSString *root = [directory.URLByStandardizingPath.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
    return [url.URLByStandardizingPath.URLByResolvingSymlinksInPath.path hasPrefix:root];
}

/// 只删除目录内的普通产物文件；同名文件夹、特殊文件和越过目录边界的符号链接都保留。
static BOOL TMRemoveKnownAuxiliaryFile(NSURL *url, NSURL *directory) {
    struct stat info;
    if (lstat(url.path.fileSystemRepresentation, &info) != 0) return errno == ENOENT;
    if (!S_ISREG(info.st_mode) || !TMURLIsInsideDirectory(url, directory)) return YES;
    return [NSFileManager.defaultManager removeItemAtURL:url error:nil];
}

+ (BOOL)cleanAuxiliaryFilesForTeXFileURL:(NSURL *)texURL
                           outputPaths:(TMCompilerOutputPaths *)paths
           legacyAuxiliaryDirectoryURL:(NSURL *)legacyDirectory
                   keepingBibliography:(BOOL)keepBibliography {
    NSURL *sourceDirectory = texURL.URLByDeletingLastPathComponent;
    NSMutableOrderedSet<NSURL *> *directories = [NSMutableOrderedSet orderedSet];
    for (NSURL *url in @[sourceDirectory, paths.outputDirectoryURL, paths.auxiliaryDirectoryURL]) {
        [directories addObject:url.URLByStandardizingPath.URLByResolvingSymlinksInPath];
    }
    if (legacyDirectory) [directories addObject:legacyDirectory.URLByStandardizingPath.URLByResolvingSymlinksInPath];
    NSOrderedSet<NSString *> *names = [NSOrderedSet orderedSetWithArray:@[texURL.lastPathComponent.stringByDeletingPathExtension, paths.jobName]];
    // 每份 .tex 独立判断；不能证明它依赖的全部 .bib 都存在时，任何产物位置的 .bbl 都保留。
    BOOL keepBBL = keepBibliography || ![TMProject canRegenerateBibliographyForTeXFileURL:texURL];
    NSRegularExpression *chapterRE = [NSRegularExpression regularExpressionWithPattern:@"\\\\@input\\{([^}]+\\.aux)\\}" options:0 error:nil];
    BOOL success = YES;
    for (NSURL *directory in directories) {
        for (NSString *name in names) {
            NSURL *mainAux = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"aux"]];
            NSString *content = [NSString stringWithContentsOfURL:mainAux encoding:NSUTF8StringEncoding error:nil];
            // 各章 aux 在独立 auxdir 时没有相邻 .tex：用实际源目录验证来源，再在产物目录里删除。
            for (NSTextCheckingResult *match in [chapterRE matchesInString:content ?: @"" options:0 range:NSMakeRange(0, content.length)]) {
                NSString *relative = [content substringWithRange:[match rangeAtIndex:1]];
                if (relative.isAbsolutePath || [relative.pathComponents containsObject:@".."]) continue;
                NSURL *chapterSource = [sourceDirectory URLByAppendingPathComponent:[relative.stringByDeletingPathExtension stringByAppendingPathExtension:@"tex"]];
                BOOL isDirectory = NO;
                if (!TMURLIsInsideDirectory(chapterSource, sourceDirectory) ||
                    ![NSFileManager.defaultManager fileExistsAtPath:chapterSource.path isDirectory:&isDirectory] || isDirectory) continue;
                NSURL *chapterAux = [directory URLByAppendingPathComponent:relative];
                if (!TMRemoveKnownAuxiliaryFile(chapterAux, directory)) success = NO;
            }
            for (NSString *extension in TMDocument.auxiliaryExtensions) {
                if (keepBBL && [extension isEqualToString:@"bbl"]) continue;
                NSURL *url = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:extension]];
                if (!TMRemoveKnownAuxiliaryFile(url, directory)) success = NO;
            }
        }
    }
    return success;
}

@end
