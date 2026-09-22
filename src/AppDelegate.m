#import "AppDelegate.h"
#import "TMDocument.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setupMainMenu];

    if (!self.mainWindowController) {
        TMDocument *initialDoc = [TMDocument documentWithDefaultTemplate];
        self.mainWindowController = [[TMMainWindowController alloc] initWithDocument:initialDoc];
    }
    [self.mainWindowController showWindow:nil];
    [self.mainWindowController.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    NSURL *fileURL = [NSURL fileURLWithPath:filename];
    if (self.mainWindowController) {
        [self.mainWindowController openDocumentAtURL:fileURL];
    } else {
        TMDocument *doc = [TMDocument documentWithContentsOfURL:fileURL error:nil];
        self.mainWindowController = [[TMMainWindowController alloc] initWithDocument:doc];
        [self.mainWindowController showWindow:nil];
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
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"保存" action:@selector(saveDocumentAction:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"另存为…" action:@selector(saveDocumentAsAction:) keyEquivalent:@"S"];
    [fileMenu addItemWithTitle:@"导出 PDF…" action:@selector(exportPDFAction:) keyEquivalent:@"e"];
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
    [editMenu addItemWithTitle:@"拼写检查（输入时）" action:@selector(toggleContinuousSpellChecking:) keyEquivalent:@""];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];

    // 4. 编译菜单 (TeX / Compile)
    NSMenuItem *compileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *compileMenu = [[NSMenu alloc] initWithTitle:@"编译"];
    [compileMenu addItemWithTitle:@"保存并编译" action:@selector(compileDocumentAction:) keyEquivalent:@"b"];
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
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fontUp = [viewMenu addItemWithTitle:@"编辑器字体放大" action:@selector(editorFontUpAction:) keyEquivalent:@"="];
    fontUp.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *fontDown = [viewMenu addItemWithTitle:@"编辑器字体缩小" action:@selector(editorFontDownAction:) keyEquivalent:@"-"];
    fontDown.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    NSMenuItem *fontReset = [viewMenu addItemWithTitle:@"编辑器字体恢复默认" action:@selector(editorFontResetAction:) keyEquivalent:@"0"];
    fontReset.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
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
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"tex"] ?: UTTypePlainText];
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        [self.mainWindowController openDocumentAtURL:panel.URL];
    }
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

- (void)forwardSyncAction:(id)sender {
    [self.mainWindowController forwardSyncToPDF];
}

- (void)cleanAuxAction:(id)sender {
    [self.mainWindowController.documentModel cleanAuxiliaryFiles];
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

- (void)exportPDFAction:(id)sender {
    NSURL *pdfURL = self.mainWindowController.documentModel.expectedPDFURL;
    if (!pdfURL || ![[NSFileManager defaultManager] fileExistsAtPath:pdfURL.path]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"尚未生成 PDF";
        alert.informativeText = @"请先按下 ⌘B 进行编译，成功生成 PDF 后方可导出。";
        [alert runModal];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"pdf"] ?: UTTypePDF];
    panel.nameFieldStringValue = pdfURL.lastPathComponent;
    if ([panel runModal] == NSModalResponseOK && panel.URL) {
        NSError *err = nil;
        [[NSFileManager defaultManager] removeItemAtURL:panel.URL error:nil];
        if (![[NSFileManager defaultManager] copyItemAtURL:pdfURL toURL:panel.URL error:&err]) {
            [[NSAlert alertWithError:err] runModal];
        }
    }
}

@end
