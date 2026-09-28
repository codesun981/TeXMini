#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "TMMainWindowController.h"
#import "TMCompiler.h"
#import "TMRecentFiles.h"
#import "TMPreferences.h"

// 不创建 NSApplication 或窗口；用替身隔离界面，执行真实控制器保存/会话逻辑。
@interface TMMainWindowController (LifecycleTests)
- (void)closeProjectAndShowWelcome;
- (BOOL)autoSaveIfNeeded;
- (NSURL *)expectedPDFURLForMainFile;
- (void)checkForExternalModification;
- (void)windowWillClose:(NSNotification *)notification;
- (void)resetCompilationState;
@end

@interface TestEditor : NSObject
@property(copy) NSString *string;
@property NSRange selectedRange;
- (BOOL)hasMarkedText;
@end
@implementation TestEditor
- (BOOL)hasMarkedText { return NO; }
@end

@interface FailingDocument : TMDocument
@end
@implementation FailingDocument
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
    return NO;
}
- (BOOL)saveScratchToURL:(NSURL *)url error:(NSError **)error { return [self saveToURL:url error:error]; }
@end

@interface LifecycleController : TMMainWindowController
@property NSUInteger reportedErrors;
@property NSUInteger writes;
@end
@implementation LifecycleController
- (BOOL)isShowingWelcome { return NO; }
- (void)didWriteCurrentFile { self.writes++; }
- (void)refreshWindowTitle {}
- (void)refreshIssueMarks {}
- (void)reportSaveError:(NSError *)error { self.reportedErrors++; }
- (NSURL *)scratchFileURLNamed:(NSString *)name { return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]]; }
- (void)loadDocumentIntoEditor { [self saveSessionState]; }
- (void)resetCompilationState {}
- (void)setProjectRootURL:(NSURL *)url reload:(BOOL)reload { [self setValue:url forKey:@"projectRootURL"]; }
- (void)removeScratchDirectory {}
- (void)hidePDFSearchBar {}
- (void)showPDFIfExistsAtURL:(NSURL *)url {}
- (void)showWelcome {}
@end

@interface TestStatus : NSObject
@property(copy) NSString *message;
- (void)showInfoMessage:(NSString *)message;
@end
@implementation TestStatus
- (void)showInfoMessage:(NSString *)message { self.message = message; }
@end

@interface TestWatcher : NSObject
@property BOOL stopped;
- (void)stop;
@end
@implementation TestWatcher
- (void)stop { self.stopped = YES; }
@end

@interface ExternalChangeController : LifecycleController
@property NSUInteger reads;
@property NSUInteger reloads;
@property NSUInteger prompts;
@property BOOL failFirstRead;
@property(strong) dispatch_semaphore_t readStarted;
@property(strong) dispatch_semaphore_t readMayFinish;
@property(copy) NSModalResponse (^response)(NSURL *url);
@end
@implementation ExternalChangeController
- (TMDocument *)readExternalDocumentAtURL:(NSURL *)url error:(NSError **)error {
    self.reads++;
    if (self.readStarted) dispatch_semaphore_signal(self.readStarted);
    if (self.readMayFinish) dispatch_semaphore_wait(self.readMayFinish, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    if (self.failFirstRead && self.reads == 1) {
        if (error) *error = [NSError errorWithDomain:TMDocumentErrorDomain code:TMDocumentErrorExternalChange userInfo:nil];
        return nil;
    }
    return [TMDocument documentWithContentsOfURL:url error:error];
}
- (NSModalResponse)responseToExternalChangeAtURL:(NSURL *)url {
    self.prompts++;
    return self.response ? self.response(url) : NSAlertSecondButtonReturn;
}
- (void)reloadDocumentFromDisk:(TMDocument *)document {
    self.reloads++;
    self.documentModel = document;
    [[self valueForKey:@"editorTextView"] setString:document.content];
}
@end

static NSUInteger compiled;
static void CaptureCompile(id self, SEL command, NSURL *url) { compiled++; }
static BOOL AutoSaveEnabled(id self, SEL command) { return YES; }
static LifecycleController *Controller(TMDocument *document, NSString *content) {
    LifecycleController *controller = [[LifecycleController alloc] initWithWindow:nil];
    controller.documentModel = document;
    TestEditor *editor = [TestEditor new];
    editor.string = content;
    editor.selectedRange = NSMakeRange(4, 0);
    [controller setValue:editor forKey:@"editorTextView"];
    return controller;
}

static NSUInteger failures;
#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); failures++; } } while (0)

static BOOL WaitUntil(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && deadline.timeIntervalSinceNow > 0) {
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return done();
}

static void ActualReset(LifecycleController *controller) {
    IMP reset = class_getMethodImplementation(TMMainWindowController.class, @selector(resetCompilationState));
    ((void (*)(id, SEL))reset)(controller, @selector(resetCompilationState));
}

static void CheckCleanupLifecycle(NSURL *file) {
    [@"\\documentclass{article}\n" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    LifecycleController *controller = Controller([TMDocument documentWithContentsOfURL:file error:nil], @"LOCAL EDIT");
    NSUInteger before = compiled;
    [controller setValue:@YES forKey:@"isCleaningAuxiliaryFiles"];
    [controller compileCurrentDocument];
    CHECK(compiled == before && controller.writes == 0);
    CHECK([[controller valueForKey:@"compileAfterAuxiliaryCleanup"] boolValue]);
    ActualReset(controller);
    CHECK([[controller valueForKey:@"isCleaningAuxiliaryFiles"] boolValue]);
    CHECK(![[controller valueForKey:@"compileAfterAuxiliaryCleanup"] boolValue]);
    [controller setValue:@NO forKey:@"isCleaningAuxiliaryFiles"];

    TMCompiler *compiler = TMCompiler.sharedCompiler;
    for (NSNumber *mode in @[@0, @1, @2]) {
        NSURL *aux = [file.URLByDeletingPathExtension URLByAppendingPathExtension:@"aux"];
        [@"generated" writeToURL:aux atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [compiler setValue:@1 forKey:@"activeCompilationCount"]; // 可控的旧编译排空门禁
        [controller cleanAndRebuild];
        CHECK([NSFileManager.defaultManager fileExistsAtPath:aux.path]);
        CHECK([[controller valueForKey:@"isCleaningAuxiliaryFiles"] boolValue]);
        if (mode.integerValue == 2) {
            [controller compileCurrentDocument];
            [controller cancelCompilation]; // 取消也应取消清理后的待编译
        } else {
            ActualReset(controller); // 换文档使旧的自动重编失效
            controller.documentModel = [TMDocument documentWithContentsOfURL:file error:nil];
            if (mode.integerValue == 1) [controller compileCurrentDocument];
        }
        [compiler setValue:@0 forKey:@"activeCompilationCount"];
        CHECK(WaitUntil(^BOOL { return ![[controller valueForKey:@"isCleaningAuxiliaryFiles"] boolValue]; }));
        CHECK(![NSFileManager.defaultManager fileExistsAtPath:aux.path]);
        if (mode.integerValue == 1) before++;
        CHECK(compiled == before);
    }
}

static ExternalChangeController *ExternalController(NSURL *file, NSString *text) {
    [@"BASE" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    ExternalChangeController *controller = [[ExternalChangeController alloc] initWithWindow:nil];
    controller.documentModel = [TMDocument documentWithContentsOfURL:file error:nil];
    TestEditor *editor = [TestEditor new];
    editor.string = text;
    [controller setValue:editor forKey:@"editorTextView"];
    [controller setValue:[TestStatus new] forKey:@"statusBar"];
    [@"REMOTE" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return controller;
}

static void CheckExternalChanges(NSURL *file) {
    // 读入期间再次被替换：首读失败后必须重试，不能只报错后等待下一次焦点变化。
    ExternalChangeController *retry = ExternalController(file, @"BASE");
    retry.failFirstRead = YES;
    [retry checkForExternalModification];
    CHECK(WaitUntil(^BOOL{ return retry.reloads == 1; }));
    CHECK(retry.reads >= 2);
    CHECK([retry.documentModel.content isEqualToString:@"REMOTE"]);
    [retry windowWillClose:nil];

    // 冲突选择期间的第二次外部写入不能被 guard 吞掉；先选择载入旧快照，再自动接上最新版。
    ExternalChangeController *prompt = ExternalController(file, @"LOCAL");
    prompt.documentModel.isDirty = YES;
    prompt.response = ^NSModalResponse(NSURL *url) {
        [@"LATEST" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return NSAlertFirstButtonReturn;
    };
    [prompt checkForExternalModification];
    CHECK(WaitUntil(^BOOL{ return [prompt.documentModel.content isEqualToString:@"LATEST"]; }));
    CHECK(prompt.prompts == 1);
    CHECK(prompt.reloads == 2);
    CHECK(!prompt.documentModel.hasExternalChanges);
    [prompt windowWillClose:nil];

    // 自动保存撞上外部改动，保持两个版本；只有明确“保留我的更改”后下一次保存才允许写入。
    ExternalChangeController *autoSave = ExternalController(file, @"LOCAL");
    autoSave.documentModel.isDirty = YES;
    CHECK(![autoSave autoSaveIfNeeded]);
    CHECK(autoSave.writes == 0);
    CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"REMOTE"]);
    CHECK(WaitUntil(^BOOL{ return autoSave.prompts == 1; }));
    CHECK([[[autoSave valueForKey:@"editorTextView"] string] isEqualToString:@"LOCAL"]);
    CHECK([autoSave autoSaveIfNeeded]);
    CHECK(autoSave.writes == 1);
    CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"LOCAL"]);
    [autoSave windowWillClose:nil];

    // 后台请求已开始后关窗：失效代次并关闭 watcher，旧快照不能再改控制器。
    ExternalChangeController *closing = ExternalController(file, @"BASE");
    closing.readStarted = dispatch_semaphore_create(0);
    closing.readMayFinish = dispatch_semaphore_create(0);
    TestWatcher *watcher = [TestWatcher new];
    [closing setValue:watcher forKey:@"fileWatcher"];
    TMDocument *original = closing.documentModel;
    [closing checkForExternalModification];
    CHECK(dispatch_semaphore_wait(closing.readStarted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
    NSUInteger generation = [[closing valueForKey:@"externalChangeCheckGeneration"] unsignedIntegerValue];
    [closing windowWillClose:nil];
    CHECK([[closing valueForKey:@"externalChangeCheckGeneration"] unsignedIntegerValue] != generation);
    CHECK(watcher.stopped);
    CHECK([closing valueForKey:@"fileWatcher"] == nil);
    dispatch_semaphore_signal(closing.readMayFinish);
    NSDate *drain = [NSDate dateWithTimeIntervalSinceNow:0.3];
    while (drain.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:drain];
    CHECK(closing.documentModel == original);
    CHECK(closing.reloads == 0);
}

int main(void) {
    @autoreleasepool {
        method_setImplementation(class_getInstanceMethod(TMCompiler.class, @selector(compileFileAtURL:)), (IMP)CaptureCompile);
        method_setImplementation(class_getInstanceMethod(TMPreferences.class, @selector(autoSaveEnabled)), (IMP)AutoSaveEnabled);
        NSFileManager *fm = NSFileManager.defaultManager;
        NSDictionary *oldDefaults = [NSUserDefaults.standardUserDefaults dictionaryRepresentation];
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        [fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *file = [root URLByAppendingPathComponent:@"main.tex"];
        [@"OLD" writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
        for (NSNumber *scratch in @[@NO, @YES]) {
            FailingDocument *doc = [FailingDocument new];
            doc.fileURL = scratch.boolValue ? nil : file;
            doc.isDirty = YES;
            LifecycleController *controller = Controller(doc, @"NEW");
            [controller setValue:@[@"previous issue"] forKey:@"lastIssues"];
            [controller compileCurrentDocument];
            CHECK(compiled == 0);
            CHECK(controller.writes == 0);
            CHECK(controller.reportedErrors == 1);
            CHECK(doc.isDirty);
            CHECK([[controller valueForKey:@"lastIssues"] count] == 1);
        }
        CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"OLD"]);

        TMDocument *doc = [TMDocument documentWithContentsOfURL:file error:nil];
        LifecycleController *controller = Controller(doc, @"NEW");
        doc.isDirty = YES;
        [controller compileCurrentDocument];
        CHECK(compiled == 1);
        CHECK(controller.writes == 1);
        CHECK(!doc.isDirty);
        CHECK([[NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"NEW"]);

        [controller setValue:root forKey:@"projectRootURL"];
        [controller closeProjectAndShowWelcome];
        [controller saveSessionState]; // 首页退出时再次保存
        CHECK([[TMRecentFiles sessionFileURL].path isEqualToString:file.path]);
        CHECK([[TMRecentFiles sessionFolderURL].path isEqualToString:root.path]);
        CHECK([TMRecentFiles sessionSelection] == 4);
        controller.documentModel = [TMDocument documentWithBlankTemplate];
        [controller saveSessionState]; // 真正新建未命名文档仍清空旧会话
        CHECK([TMRecentFiles sessionFileURL] == nil);
        CHECK([TMRecentFiles sessionFolderURL] == nil);

        TMCompiler *compiler = TMCompiler.sharedCompiler;
        NSArray *oldArgs = compiler.extraArguments;
        compiler.extraArguments = @[@"-outdir=build", @"-jobname=paper"];
        controller.documentModel = doc;
        CHECK([[controller expectedPDFURLForMainFile].path isEqualToString:[root.path stringByAppendingPathComponent:@"build/paper.pdf"]]);
        compiler.extraArguments = oldArgs;
        CheckExternalChanges(file);
        CheckCleanupLifecycle(file);
        for (NSString *key in @[@"TMSessionFile", @"TMSessionFolder", @"TMSessionSelection"]) {
            if (oldDefaults[key]) [NSUserDefaults.standardUserDefaults setObject:oldDefaults[key] forKey:key];
            else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }
        [fm removeItemAtURL:root error:nil];
        printf("controller lifecycle: %s (%lu failures)\n", failures ? "FAILED" : "OK", (unsigned long)failures);
    }
    return failures ? 1 : 0;
}
