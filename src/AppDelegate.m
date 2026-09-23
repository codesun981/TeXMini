#import "AppDelegate.h"
#import "TMDocument.h"
#import "TMCompiler.h"
#import "TMRecentFiles.h"
#import "TMPreferences.h"
#import "TMPreferencesWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface AppDelegate () <NSMenuDelegate>
@property (nonatomic, strong) NSMenu *recentMenu;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    [TMPreferences registerDefaults];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupMainMenu];

    if (!self.mainWindowController) {
        TMDocument *initialDoc = [TMDocument documentWithDefaultTemplate];
        self.mainWindowController = [[TMMainWindowController alloc] initWithDocument:initialDoc];
    }
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self checkMacTeXInstallation];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    NSURL *fileURL = [NSURL fileURLWithPath:filename];
    if (self.mainWindowController) {
        [self.mainWindowController openDocumentAtURL:fileURL];
    } else {
        TMDocument *doc = [TMDocument documentWithContentsOfURL:fileURL error:nil];
        self.mainWindowController = [[TMMainWindowController alloc] initWithDocument:doc];
        [self.mainWindowController showWindow:nil];
        if (doc) [TMRecentFiles noteFileURL:fileURL];
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.mainWindowController && ![self.mainWindowController confirmDiscardChangesWithTitle:@"退出前是否保存更改？"]) {
        return NSTerminateCancel;
    }
    return NSTerminateNow;
}

#pragma mark - 菜单栏配置

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // 1. App 菜单
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TeXMini"];
    [appMenu addItemWithTitle:@"关于 TeXMini" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"偏好设置…" action:@selector(showPreferencesAction:) keyEquivalent:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"隐藏 TeXMini" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"隐藏其他" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [[appMenu.itemArray lastObject] setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
    [appMenu addItemWithTitle:@"全部显示" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"退出 TeXMini" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    // 2. 文件菜单 (File)
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"文件"];
    [fileMenu addItemWithTitle:@"新建" action:@selector(newDocumentAction:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"打开…" action:@selector(openDocumentAction:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"打开文件夹…" action:@selector(openFolderAction:) keyEquivalent:@"O"];
    NSMenuItem *recentItem = [[NSMenuItem alloc] initWithTitle:@"打开最近" action:nil keyEquivalent:@""];
    self.recentMenu = [[NSMenu alloc] initWithTitle:@"打开最近"];
    self.recentMenu.delegate = self;
    recentItem.submenu = self.recentMenu;
    [fileMenu addItem:recentItem];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"保存" action:@selector(saveDocumentAction:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"另存为…" action:@selector(saveDocumentAsAction:) keyEquivalent:@"S"];
    // ⌘E 已被“使用所选内容查找”占用（编辑器有焦点时会被抢走），导出改用 ⇧⌘E
    [fileMenu addItemWithTitle:@"导出 PDF…" action:@selector(exportPDFAction:) keyEquivalent:@"E"];
    [fileMenu addItemWithTitle:@"在访达中显示 PDF" action:@selector(revealPDFAction:) keyEquivalent:@"R"];
    [fileMenu addItemWithTitle:@"打印 PDF…" action:@selector(printPDFAction:) keyEquivalent:@"p"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w"];
    fileMenuItem.submenu = fileMenu;
    [mainMenu addItem:fileMenuItem];

    // 3. 编辑菜单 (Edit - 标准系统剪切、复制、撤销 + 查找 + LaTeX 编辑动作)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *findItem = [[NSMenuItem alloc] initWithTitle:@"查找" action:nil keyEquivalent:@""];
    NSMenu *findMenu = [[NSMenu alloc] initWithTitle:@"查找"];
    [self addFinderItemTo:findMenu title:@"查找…" key:@"f" mask:NSEventModifierFlagCommand tag:NSTextFinderActionShowFindInterface];
    [self addFinderItemTo:findMenu title:@"查找并替换…" key:@"f" mask:NSEventModifierFlagCommand | NSEventModifierFlagOption tag:NSTextFinderActionShowReplaceInterface];
    [self addFinderItemTo:findMenu title:@"查找下一个" key:@"g" mask:NSEventModifierFlagCommand tag:NSTextFinderActionNextMatch];
    [self addFinderItemTo:findMenu title:@"查找上一个" key:@"g" mask:NSEventModifierFlagCommand | NSEventModifierFlagShift tag:NSTextFinderActionPreviousMatch];
    [self addFinderItemTo:findMenu title:@"使用所选内容查找" key:@"e" mask:NSEventModifierFlagCommand tag:NSTextFinderActionSetSearchString];
    [self addFinderItemTo:findMenu title:@"隐藏查找栏" key:@"" mask:0 tag:NSTextFinderActionHideFindInterface];
    findItem.submenu = findMenu;
    [editMenu addItem:findItem];
    [editMenu addItemWithTitle:@"跳转到行…" action:@selector(gotoLineAction:) keyEquivalent:@"l"];
    [editMenu addItem:[NSMenuItem separatorItem]];

    [editMenu addItemWithTitle:@"切换注释" action:@selector(toggleComment:) keyEquivalent:@"/"];
    [editMenu addItemWithTitle:@"增加缩进" action:@selector(indentSelection:) keyEquivalent:@"]"];
    [editMenu addItemWithTitle:@"减少缩进" action:@selector(outdentSelection:) keyEquivalent:@"["];
    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *spellingItem = [[NSMenuItem alloc] initWithTitle:@"拼写和语法" action:nil keyEquivalent:@""];
    NSMenu *spellingMenu = [[NSMenu alloc] initWithTitle:@"拼写和语法"];
    [spellingMenu addItemWithTitle:@"显示拼写和语法" action:@selector(showGuessPanel:) keyEquivalent:@":"];
    [spellingMenu addItemWithTitle:@"检查文稿" action:@selector(checkSpelling:) keyEquivalent:@";"];
    [spellingMenu addItem:[NSMenuItem separatorItem]];
    [spellingMenu addItemWithTitle:@"输入时检查拼写" action:@selector(toggleContinuousSpellChecking:) keyEquivalent:@""];
    [spellingMenu addItemWithTitle:@"随拼写检查语法" action:@selector(toggleGrammarChecking:) keyEquivalent:@""];
    spellingItem.submenu = spellingMenu;
    [editMenu addItem:spellingItem];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];

    // 4. 编译菜单 (TeX / Compile)
    NSMenuItem *compileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *compileMenu = [[NSMenu alloc] initWithTitle:@"编译"];
    [compileMenu addItemWithTitle:@"保存并编译" action:@selector(compileDocumentAction:) keyEquivalent:@"b"];
    NSMenuItem *cleanBuild = [compileMenu addItemWithTitle:@"清理并重新编译" action:@selector(cleanAndRebuildAction:) keyEquivalent:@"b"];
    cleanBuild.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [compileMenu addItemWithTitle:@"取消编译" action:@selector(cancelCompileAction:) keyEquivalent:@"."];
    [compileMenu addItemWithTitle:@"自动编译（停止输入后）" action:@selector(toggleAutoCompileAction:) keyEquivalent:@""];
    [compileMenu addItemWithTitle:@"允许 Shell Escape (-shell-escape)" action:@selector(toggleShellEscapeAction:) keyEquivalent:@""];
    [compileMenu addItem:[NSMenuItem separatorItem]];
    [compileMenu addItemWithTitle:@"正向跳转至 PDF" action:@selector(forwardSyncAction:) keyEquivalent:@"j"];
    [compileMenu addItem:[NSMenuItem separatorItem]];
    [compileMenu addItemWithTitle:@"清理辅助文件" action:@selector(cleanAuxAction:) keyEquivalent:@"k"];
    compileMenuItem.submenu = compileMenu;
    [mainMenu addItem:compileMenuItem];

    // 5. 视图菜单 (View)
    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"视图"];
    [viewMenu addItemWithTitle:@"切换大纲视图" action:@selector(toggleOutlineAction:) keyEquivalent:@"1"];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"放大" action:@selector(zoomInAction:) keyEquivalent:@"+"];
    [viewMenu addItemWithTitle:@"缩小" action:@selector(zoomOutAction:) keyEquivalent:@"-"];
    [viewMenu addItemWithTitle:@"适合宽度" action:@selector(pdfFitWidthAction:) keyEquivalent:@"0"];
    NSMenuItem *actual = [viewMenu addItemWithTitle:@"实际大小" action:@selector(pdfActualSizeAction:) keyEquivalent:@"0"];
    actual.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *prevPage = [viewMenu addItemWithTitle:@"上一页" action:@selector(pdfPreviousPageAction:) keyEquivalent:[NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey]];
    prevPage.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *nextPage = [viewMenu addItemWithTitle:@"下一页" action:@selector(pdfNextPageAction:) keyEquivalent:[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey]];
    nextPage.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fontUp = [viewMenu addItemWithTitle:@"编辑器字体放大" action:@selector(editorFontUpAction:) keyEquivalent:@"="];
    fontUp.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *fontDown = [viewMenu addItemWithTitle:@"编辑器字体缩小" action:@selector(editorFontDownAction:) keyEquivalent:@"-"];
    fontDown.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *fontReset = [viewMenu addItemWithTitle:@"编辑器字体恢复默认" action:@selector(editorFontResetAction:) keyEquivalent:@"0"];
    fontReset.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *wrapItem = [viewMenu addItemWithTitle:@"自动换行" action:@selector(toggleSoftWrapAction:) keyEquivalent:@"w"];
    wrapItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [viewMenu addItemWithTitle:@"切换日志抽屉" action:@selector(toggleLogAction:) keyEquivalent:@"L"];
    viewMenuItem.submenu = viewMenu;
    [mainMenu addItem:viewMenuItem];

    // 6. 窗口菜单 (Window)
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"];
    [windowMenu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"缩放" action:@selector(performZoom:) keyEquivalent:@""];
    windowMenuItem.submenu = windowMenu;
    [mainMenu addItem:windowMenuItem];

    [NSApp setMainMenu:mainMenu];
}

#pragma mark - 最近打开

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != self.recentMenu) return;
    [menu removeAllItems];

    NSArray<NSURL *> *urls = [TMRecentFiles recentFileURLs];
    NSArray<NSURL *> *folders = [TMRecentFiles recentFolderURLs];
    for (NSURL *url in urls) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:url.lastPathComponent action:@selector(openRecentAction:) keyEquivalent:@""];
        item.representedObject = url;
        item.toolTip = url.path;
        item.image = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
        item.image.size = NSMakeSize(16, 16);
        item.target = self;
        [menu addItem:item];
    }
    if (folders.count > 0) {
        if (urls.count > 0) [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"最近项目文件夹" action:nil keyEquivalent:@""];
        header.enabled = NO;
        [menu addItem:header];
        for (NSURL *url in folders) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:url.lastPathComponent action:@selector(openRecentAction:) keyEquivalent:@""];
            item.representedObject = url;
            item.toolTip = url.path;
            item.image = [[NSWorkspace sharedWorkspace] iconForFile:url.path];
            item.image.size = NSMakeSize(16, 16);
            item.target = self;
            item.indentationLevel = 1;
            [menu addItem:item];
        }
    }
    if (urls.count == 0 && folders.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"无最近项目" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"清除菜单" action:@selector(clearRecentAction:) keyEquivalent:@""];
    clear.target = self;
    clear.enabled = urls.count > 0 || folders.count > 0;
    [menu addItem:clear];
}

- (void)openRecentAction:(NSMenuItem *)sender {
    NSURL *url = sender.representedObject;
    if ([url isKindOfClass:[NSURL class]]) {
        [self.mainWindowController openDocumentAtURL:url];
        [self.mainWindowController.window makeKeyAndOrderFront:nil];
    }
}

- (void)clearRecentAction:(id)sender {
    [TMRecentFiles clear];
}

#pragma mark - 菜单快捷响应

- (void)addFinderItemTo:(NSMenu *)menu title:(NSString *)title key:(NSString *)key mask:(NSEventModifierFlags)mask tag:(NSInteger)tag {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(performTextFinderAction:) keyEquivalent:key];
    item.keyEquivalentModifierMask = mask;
    item.tag = tag;
    [menu addItem:item];
}

- (void)gotoLineAction:(id)sender {
    [self.mainWindowController promptGotoLine];
}

- (void)newDocumentAction:(id)sender {
    if (self.mainWindowController) {
        [self.mainWindowController newDocumentAction:sender];
        [self.mainWindowController.window makeKeyAndOrderFront:nil];
    } else {
        TMDocument *doc = [TMDocument documentWithBlankTemplate];
        self.mainWindowController = [[TMMainWindowController alloc] initWithDocument:doc];
        [self.mainWindowController showWindow:nil];
    }
}

- (void)openDocumentAction:(id)sender {
    [self.mainWindowController openFileAction:sender];
}

- (void)openFolderAction:(id)sender {
    [self.mainWindowController openFolderAction:sender];
}

- (void)saveDocumentAction:(id)sender {
    [self.mainWindowController saveCurrentDocument];
}

- (void)saveDocumentAsAction:(id)sender {
    [self.mainWindowController saveDocumentAs];
}

- (void)compileDocumentAction:(id)sender {
    [self.mainWindowController compileCurrentDocument];
}

- (void)cancelCompileAction:(id)sender {
    [self.mainWindowController cancelCompilation];
}

- (void)toggleAutoCompileAction:(id)sender {
    self.mainWindowController.autoCompileEnabled = !self.mainWindowController.autoCompileEnabled;
}

- (void)toggleShellEscapeAction:(id)sender {
    [TMPreferences shared].shellEscapeEnabled = ![TMPreferences shared].shellEscapeEnabled;
}

- (void)toggleSoftWrapAction:(id)sender {
    [TMPreferences shared].softWrapEnabled = ![TMPreferences shared].softWrapEnabled;
}

- (void)showPreferencesAction:(id)sender {
    [[TMPreferencesWindowController shared] showPreferences];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    SEL action = menuItem.action;
    if (action == @selector(cancelCompileAction:)) {
        return [self.mainWindowController isCompiling];
    }
    if (action == @selector(toggleAutoCompileAction:)) {
        menuItem.state = self.mainWindowController.autoCompileEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(toggleShellEscapeAction:)) {
        menuItem.state = [TMPreferences shared].shellEscapeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(toggleSoftWrapAction:)) {
        menuItem.state = [TMPreferences shared].softWrapEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    if (action == @selector(exportPDFAction:) || action == @selector(revealPDFAction:)) {
        return self.mainWindowController.currentPDFURL != nil;
    }
    if (action == @selector(printPDFAction:) || action == @selector(pdfFitWidthAction:) ||
        action == @selector(pdfActualSizeAction:) || action == @selector(pdfPreviousPageAction:) ||
        action == @selector(pdfNextPageAction:) || action == @selector(zoomInAction:) || action == @selector(zoomOutAction:)) {
        return [self.mainWindowController hasPDF];
    }
    return YES;
}

- (void)checkMacTeXInstallation {
    if ([TMCompiler isMacTeXInstalled]) return;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"未检测到 LaTeX 发行版";
    alert.informativeText = @"TeXMini 需要 MacTeX（或 BasicTeX）提供 latexmk / pdflatex / xelatex。\n"
                            @"已查找：/Library/TeX/texbin、/usr/local/bin、/opt/homebrew/bin。\n\n"
                            @"安装完成后重新启动 TeXMini 即可编译。";
    [alert addButtonWithTitle:@"前往下载 MacTeX"];
    [alert addButtonWithTitle:@"稍后"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://tug.org/mactex/"]];
    }
}

- (void)forwardSyncAction:(id)sender {
    [self.mainWindowController forwardSyncToPDF];
}

- (void)cleanAuxAction:(id)sender {
    [self.mainWindowController cleanAuxiliaryFilesForMainFile];
}

- (void)cleanAndRebuildAction:(id)sender {
    [self.mainWindowController cleanAndRebuild];
}

- (void)toggleOutlineAction:(id)sender {
    [self.mainWindowController toggleOutlineSidebar];
}

- (void)toggleLogAction:(id)sender {
    [self.mainWindowController toggleLogDrawer];
}

- (void)zoomInAction:(id)sender {
    [self.mainWindowController zoomIn];
}

- (void)zoomOutAction:(id)sender {
    [self.mainWindowController zoomOut];
}

- (void)editorFontUpAction:(id)sender {
    [self.mainWindowController increaseEditorFontSize];
}

- (void)editorFontDownAction:(id)sender {
    [self.mainWindowController decreaseEditorFontSize];
}

- (void)editorFontResetAction:(id)sender {
    [self.mainWindowController resetEditorFontSize];
}

- (void)pdfFitWidthAction:(id)sender { [self.mainWindowController pdfFitWidth]; }
- (void)pdfActualSizeAction:(id)sender { [self.mainWindowController pdfActualSize]; }
- (void)pdfPreviousPageAction:(id)sender { [self.mainWindowController pdfPreviousPage]; }
- (void)pdfNextPageAction:(id)sender { [self.mainWindowController pdfNextPage]; }
- (void)printPDFAction:(id)sender { [self.mainWindowController printPDF]; }

- (void)exportPDFAction:(id)sender {
    [self.mainWindowController exportPDF];
}

- (void)revealPDFAction:(id)sender {
    [self.mainWindowController revealPDFInFinder];
}

@end
