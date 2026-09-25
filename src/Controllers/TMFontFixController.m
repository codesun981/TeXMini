#import "TMFontFixController.h"
#import "TMFontSettings.h"
#import "TMFontCatalog.h"
#import "TMDocumentFontView.h"
#import "TMEditorTextView.h"
#import "TMCompiler.h"
#import "TMProject.h"

@interface TMFontFixController ()
@property (nonatomic, weak) id<TMFontFixHost> host;
/// 用户拒绝过替换的缺失字体：本次会话不再为它们弹窗（自动编译时不反复打扰）。
@property (nonatomic, strong) NSMutableSet<NSString *> *declinedFontFixes;
@property (nonatomic, assign) BOOL isShowingFontFixAlert;
@end

@implementation TMFontFixController

- (instancetype)initWithHost:(id<TMFontFixHost>)host {
    self = [super init];
    if (self) _host = host;
    return self;
}

#pragma mark - 读写辅助

- (BOOL)isCurrentDocumentURL:(nullable NSURL *)url {
    NSURL *current = self.host.currentDocumentFileURL;
    if (!url || !current) return url == current;
    return [url.URLByStandardizingPath.URLByResolvingSymlinksInPath.path
            isEqualToString:current.URLByStandardizingPath.URLByResolvingSymlinksInPath.path];
}

/// 编辑器里的是当前文件的最新内容；其他文件读磁盘。
- (nullable NSString *)latestContentOfFileURL:(nullable NSURL *)url {
    if ([self isCurrentDocumentURL:url]) return self.host.editorTextView.string;
    return [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
}

/// 当前文件可撤销地改；其他文件直接写盘。返回 NO 表示写盘失败（已弹错误）。
- (BOOL)writeContent:(NSString *)content toFileURL:(nullable NSURL *)url actionName:(NSString *)actionName {
    if ([self isCurrentDocumentURL:url]) {
        [self.host.editorTextView replaceTextWith:content actionName:actionName];
        return YES;
    }
    NSError *err = nil;
    if (![content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        [[NSAlert alertWithError:err] beginSheetModalForWindow:self.host.window completionHandler:nil];
        return NO;
    }
    return YES;
}

#pragma mark - 文档字体

/// 编辑 › 文档字体…：字体设置写在主文件的导言区；当前文件不是主文件时先问要不要打开主文件。
- (void)showDocumentFontsSheet {
    if (![TMFontSettings contentHasPreamble:self.host.editorTextView.string]) {
        NSURL *main = [self.host mainFileURLForCompile];
        if (!main || [self isCurrentDocumentURL:main]) {
            [self.host showInfoMessage:@"当前文档没有导言区（\\documentclass … \\begin{document}），无法设置字体"];
            return;
        }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"字体设置写在主文件的导言区";
        alert.informativeText = [NSString stringWithFormat:@"当前文件没有 \\documentclass。要打开主文件 %@ 吗？", main.lastPathComponent];
        [alert addButtonWithTitle:@"打开主文件"];
        [alert addButtonWithTitle:@"取消"];
        [alert beginSheetModalForWindow:self.host.window completionHandler:^(NSModalResponse response) {
            if (response != NSAlertFirstButtonReturn) return;
            [self.host openDocumentAtURL:main];
            // 用户可能在“保存更改？”里取消了切换
            if ([self isCurrentDocumentURL:main] && [TMFontSettings contentHasPreamble:self.host.editorTextView.string]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [self showDocumentFontsSheet]; });
            }
        }];
        return;
    }
    [[TMFontCatalog shared] loadWithCompletion:^(NSArray<TMFontFamily *> *families) {
        [self presentDocumentFontsSheetWithFamilies:families];
    }];
}

- (void)presentDocumentFontsSheetWithFamilies:(NSArray<TMFontFamily *> *)families {
    NSString *content = self.host.editorTextView.string;
    NSString *cls = [TMFontSettings documentClassInContent:content] ?: @"";
    BOOL ctex = [TMFontSettings isCTeXContent:content];
    TMDocumentFontView *fontView = [[TMDocumentFontView alloc] initWithFamilies:families
                                                                        current:[TMFontSettings settingsInContent:content]
                                                                    sizeOptions:[TMFontSettings sizeOptionsForDocumentClass:cls]
                                                                cjkDefaultTitle:ctex ? @"文档默认（ctex 自动：宋体）" : @"不设置"];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"文档字体";
    alert.informativeText = @"写入当前文件的导言区，⌘Z 可撤销。字体设置需要 XeLaTeX 编译（自动模式会自动切换）。";
    [alert addButtonWithTitle:@"应用"];
    [alert addButtonWithTitle:@"取消"];
    alert.buttons[1].keyEquivalent = @"\e";
    alert.accessoryView = fontView;
    alert.window.initialFirstResponder = fontView.latinPopup;

    [alert beginSheetModalForWindow:self.host.window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) return;
        TMDocumentFontSettings *settings = fontView.selectedSettings;
        NSString *latest = self.host.editorTextView.string;
        NSString *updated = [TMFontSettings contentByApplyingSettings:settings
                                                          cjkFakeBold:fontView.selectedCJKFontNeedsFakeBold
                                                            toContent:latest];
        if (!updated || [updated isEqualToString:latest]) return;
        [self.host.editorTextView replaceTextWith:updated actionName:@"设置文档字体"];

        NSString *engine = [[TMCompiler sharedCompiler] effectiveEngineNameForContent:updated directoryURL:self.host.currentDocumentFileURL.URLByDeletingLastPathComponent reason:NULL];
        BOOL usesFonts = settings.latinFont || settings.cjkFont;
        BOOL engineOK = [engine isEqualToString:@"xelatex"] || ([engine isEqualToString:@"lualatex"] && [TMFontSettings isCTeXContent:updated]);
        if (usesFonts && !engineOK) {
            [self.host showInfoMessage:[NSString stringWithFormat:@"已写入字体设置，但当前引擎是 %@：请在状态栏切换到 XeLaTeX 或自动", engine]];
            return;
        }
        [self.host compileCurrentDocument];
    }];
}

#pragma mark - 缺失字体：一键替换

/// 编译失败且日志里有“找不到字体”时调用：ctex fontset 引起的建议删掉 fontset，其余按替换表找本机可用的字体。
- (void)offerFontFixForLog:(NSString *)log {
    NSArray<NSString *> *missing = [TMFontSettings missingFontNamesInLog:log];
    if (missing.count == 0 || self.isShowingFontFixAlert) return;
    if (!self.declinedFontFixes) self.declinedFontFixes = [NSMutableSet set];
    if ([[NSSet setWithArray:missing] isSubsetOfSet:self.declinedFontFixes]) return;

    NSString *fontset = [TMFontSettings failingCTeXFontsetInLog:log];
    if (fontset) {
        [self offerRemovingCTeXFontset:fontset missingFonts:missing];
        return;
    }
    [[TMFontCatalog shared] loadWithCompletion:^(NSArray<TMFontFamily *> *families) {
        [self offerReplacingMissingFonts:missing];
    }];
}

- (void)offerRemovingCTeXFontset:(NSString *)fontset missingFonts:(NSArray<NSString *> *)missing {
    NSURL *main = [self.host mainFileURLForCompile];
    NSString *content = [self latestContentOfFileURL:main] ?: @"";
    NSString *fixed = [TMFontSettings contentByRemovingCTeXFontset:fontset inContent:content];
    if (!fixed) {
        [self.host showInfoMessage:[NSString stringWithFormat:@"ctex 的 fontset=%@ 需要本机没有的字体（%@），请删掉这个选项", fontset, missing.firstObject]];
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"本机没有 fontset=%@ 需要的字体", fontset];
    alert.informativeText = [NSString stringWithFormat:@"ctex 的 fontset=%@ 要用“%@”等字体，这台 Mac 上没有。\n\n删掉这个选项后，ctex 会自动使用 macOS 自带的宋体、黑体、楷体；换回 Windows 编译也同样能自动适配。",
                             fontset, missing.firstObject];
    [alert addButtonWithTitle:@"删除选项并重新编译"];
    [alert addButtonWithTitle:@"取消"];
    alert.buttons[1].keyEquivalent = @"\e";
    self.isShowingFontFixAlert = YES;
    [alert beginSheetModalForWindow:self.host.window completionHandler:^(NSModalResponse response) {
        self.isShowingFontFixAlert = NO;
        if (response != NSAlertFirstButtonReturn) {
            [self.declinedFontFixes addObjectsFromArray:missing];
            return;
        }
        if ([self writeContent:fixed toFileURL:main actionName:@"删除 ctex fontset"]) [self.host compileCurrentDocument];
    }];
}

/// 当前文件 + 主文件 + 项目里的 .tex / .sty / .cls（模板常把字体写死在 .cls 里）。
- (NSArray<NSURL *> *)fontFixCandidateFileURLs {
    NSMutableOrderedSet<NSURL *> *urls = [NSMutableOrderedSet orderedSet];
    if (self.host.currentDocumentFileURL) [urls addObject:self.host.currentDocumentFileURL.URLByStandardizingPath];
    NSURL *main = [self.host mainFileURLForCompile];
    if (main) [urls addObject:main.URLByStandardizingPath];
    if (self.host.projectRootURL) {
        NSMutableArray<TMFileNode *> *stack = [[TMProject fileTreeForDirectory:self.host.projectRootURL maxDepth:4] mutableCopy];
        while (stack.count && urls.count < 300) {
            TMFileNode *node = stack.lastObject;
            [stack removeLastObject];
            if (node.isDirectory) { [stack addObjectsFromArray:node.children]; continue; }
            if ([@[@"tex", @"sty", @"cls"] containsObject:node.url.pathExtension.lowercaseString]) [urls addObject:node.url.URLByStandardizingPath];
        }
    }
    return urls.array;
}

- (void)offerReplacingMissingFonts:(NSArray<NSString *> *)missing {
    TMFontCatalog *catalog = [TMFontCatalog shared];
    NSArray<NSURL *> *urls = [self fontFixCandidateFileURLs];
    NSURL *currentURL = self.host.currentDocumentFileURL.URLByStandardizingPath;
    NSString *currentText = self.host.editorTextView.string;

    // 替换表：日志报的缺失字体 + 文件里其他本机也没有的“换台电脑就没了”的字体，一次改完，免得编译一次报一个
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary<NSURL *, NSString *> *contents = [NSMutableDictionary dictionary];
        NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSetWithArray:missing];
        for (NSURL *url in urls) {
            NSString *text = [url isEqual:currentURL] ? currentText : [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
            if (text.length == 0 || text.length > 2000000) continue;
            contents[url] = text;
            [names addObjectsFromArray:[TMFontSettings knownReplaceableFontNamesInContent:text]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary<NSString *, NSString *> *replacements = [NSMutableDictionary dictionary];
            NSMutableArray<NSString *> *unresolved = [NSMutableArray array];
            for (NSString *name in names) {
                BOOL reportedMissing = [missing containsObject:name];
                if (!reportedMissing && [catalog familyNamed:name]) continue; // 本机有，不动
                NSString *to = nil;
                for (NSString *candidate in [TMFontSettings replacementCandidatesForFont:name]) {
                    if ([catalog familyNamed:candidate]) { to = [catalog familyNamed:candidate].familyName; break; }
                }
                if (to) replacements[name] = to;
                else if (reportedMissing) [unresolved addObject:name];
            }

            NSMutableDictionary<NSURL *, NSString *> *fixed = [NSMutableDictionary dictionary];
            for (NSURL *url in contents) {
                NSUInteger n = 0;
                NSString *out = [TMFontSettings contentByReplacingFonts:replacements inContent:contents[url] count:&n];
                if (n > 0) fixed[url] = out;
            }
            if (fixed.count == 0) {
                [self.host showInfoMessage:[NSString stringWithFormat:@"本机没有字体“%@”，可在 编辑 › 文档字体… 里换一个", missing.firstObject]];
                return;
            }
            [self confirmFontReplacements:replacements unresolved:unresolved files:fixed missing:missing];
        });
    });
}

- (void)confirmFontReplacements:(NSDictionary<NSString *, NSString *> *)replacements
                     unresolved:(NSArray<NSString *> *)unresolved
                          files:(NSDictionary<NSURL *, NSString *> *)files
                        missing:(NSArray<NSString *> *)missing {
    if (self.isShowingFontFixAlert) return;
    NSMutableString *info = [NSMutableString string];
    for (NSString *from in [replacements.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        TMFontFamily *to = [[TMFontCatalog shared] familyNamed:replacements[from]];
        NSString *toTitle = [to.displayName isEqualToString:to.familyName] ? to.familyName
                                                                           : [NSString stringWithFormat:@"%@（%@）", to.displayName, to.familyName];
        [info appendFormat:@"%@ → %@\n", from, toTitle];
    }
    for (NSString *name in unresolved) [info appendFormat:@"%@ → 没有合适的替代，请在 编辑 › 文档字体… 里另选\n", name];
    NSMutableArray<NSString *> *fileNames = [NSMutableArray array];
    for (NSURL *url in files) [fileNames addObject:url.lastPathComponent];
    [info appendFormat:@"\n将修改：%@\n只改字体命令所在的行。", [fileNames componentsJoinedByString:@"、"]];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = missing.count == 1 ? [NSString stringWithFormat:@"本机没有字体“%@”", missing.firstObject] : @"本机缺少文档用到的字体";
    alert.informativeText = info;
    [alert addButtonWithTitle:@"替换并重新编译"];
    [alert addButtonWithTitle:@"取消"];
    alert.buttons[1].keyEquivalent = @"\e";
    self.isShowingFontFixAlert = YES;
    [alert beginSheetModalForWindow:self.host.window completionHandler:^(NSModalResponse response) {
        self.isShowingFontFixAlert = NO;
        if (response != NSAlertFirstButtonReturn) {
            [self.declinedFontFixes addObjectsFromArray:missing];
            return;
        }
        for (NSURL *url in files) {
            if (![self writeContent:files[url] toFileURL:url actionName:@"替换缺失字体"]) return;
        }
        [self.host compileCurrentDocument];
    }];
}

@end
