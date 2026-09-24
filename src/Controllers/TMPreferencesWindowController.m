#import "TMPreferencesWindowController.h"
#import "TMPreferences.h"
#import "TMCompiler.h"

@interface TMPreferencesWindowController ()
@property (nonatomic, strong) NSPopUpButton *fontPopup;
@property (nonatomic, strong) NSTextField *fontSizeField;
@property (nonatomic, strong) NSStepper *fontSizeStepper;
@property (nonatomic, strong) NSButton *softWrapCheck;
@property (nonatomic, strong) NSButton *currentLineCheck;
@property (nonatomic, strong) NSButton *autoSaveCheck;
@property (nonatomic, strong) NSButton *restoreSessionCheck;
@property (nonatomic, strong) NSPopUpButton *enginePopup;
@property (nonatomic, strong) NSButton *autoCompileCheck;
@property (nonatomic, strong) NSButton *shellEscapeCheck;
@property (nonatomic, strong) NSButton *auxBesideSourceCheck;
@property (nonatomic, strong) NSTextField *extraArgsField;
@property (nonatomic, assign) BOOL isLoading;
@end

@implementation TMPreferencesWindowController

+ (instancetype)shared {
    static TMPreferencesWindowController *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[TMPreferencesWindowController alloc] init]; });
    return shared;
}

- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 360)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"偏好设置";
    [window center];
    self = [super initWithWindow:window];
    if (self) {
        [self buildUI];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferencesDidChange:)
                                                     name:TMPreferencesDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)showPreferences {
    [self loadValues];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - 构建界面

- (NSTextField *)label:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.alignment = NSTextAlignmentRight;
    l.textColor = [NSColor labelColor];
    return l;
}

- (NSTextField *)sectionLabel:(NSString *)text {
    NSTextField *l = [NSTextField labelWithString:text];
    l.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    return l;
}

- (NSTextField *)hint:(NSString *)text {
    NSTextField *l = [NSTextField wrappingLabelWithString:text];
    l.font = [NSFont systemFontOfSize:11];
    l.textColor = [NSColor secondaryLabelColor];
    l.preferredMaxLayoutWidth = 300;
    return l;
}

- (void)buildUI {
    NSView *content = self.window.contentView;

    // 字体：列出所有等宽字体家族
    _fontPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *fixed = [[NSFontManager sharedFontManager] availableFontNamesWithTraits:NSFixedPitchFontMask];
    NSMutableOrderedSet<NSString *> *families = [NSMutableOrderedSet orderedSet];
    for (NSString *name in fixed) {
        NSFont *f = [NSFont fontWithName:name size:12];
        if (f.familyName.length) [families addObject:f.familyName];
    }
    [families sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { return [a localizedCaseInsensitiveCompare:b]; }];
    for (NSString *family in families) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:family action:nil keyEquivalent:@""];
        item.representedObject = family;
        [_fontPopup.menu addItem:item];
    }
    _fontPopup.target = self;
    _fontPopup.action = @selector(fontChanged:);

    _fontSizeField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _fontSizeField.alignment = NSTextAlignmentRight;
    _fontSizeField.target = self;
    _fontSizeField.action = @selector(fontSizeFieldChanged:);
    NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
    nf.minimum = @9;
    nf.maximum = @30;
    nf.maximumFractionDigits = 1;
    _fontSizeField.formatter = nf;
    [_fontSizeField.widthAnchor constraintEqualToConstant:52].active = YES;

    _fontSizeStepper = [[NSStepper alloc] initWithFrame:NSZeroRect];
    _fontSizeStepper.minValue = 9;
    _fontSizeStepper.maxValue = 30;
    _fontSizeStepper.increment = 1;
    _fontSizeStepper.target = self;
    _fontSizeStepper.action = @selector(fontSizeStepperChanged:);

    NSStackView *fontRow = [NSStackView stackViewWithViews:@[_fontPopup, _fontSizeField, _fontSizeStepper]];
    fontRow.spacing = 6;

    _softWrapCheck = [NSButton checkboxWithTitle:@"自动换行" target:self action:@selector(toggleChanged:)];
    _currentLineCheck = [NSButton checkboxWithTitle:@"高亮当前行" target:self action:@selector(toggleChanged:)];
    _autoSaveCheck = [NSButton checkboxWithTitle:@"自动保存（停止输入 1 秒后保存 .tex，不编译）" target:self action:@selector(toggleChanged:)];
    _restoreSessionCheck = [NSButton checkboxWithTitle:@"启动时打开上次的项目（关闭则显示首页）" target:self action:@selector(toggleChanged:)];

    _enginePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_enginePopup addItemsWithTitles:@[@"自动 (latexmk：魔法注释 / 中文自动 XeLaTeX)", @"XeLaTeX", @"pdfLaTeX", @"LuaLaTeX"]];
    _enginePopup.target = self;
    _enginePopup.action = @selector(engineChanged:);

    _autoCompileCheck = [NSButton checkboxWithTitle:@"停止输入 1.5 秒后自动编译" target:self action:@selector(toggleChanged:)];
    _shellEscapeCheck = [NSButton checkboxWithTitle:@"允许 -shell-escape（minted、TikZ externalize 需要）" target:self action:@selector(toggleChanged:)];

    _auxBesideSourceCheck = [NSButton checkboxWithTitle:@"中间文件（.aux、.log 等）放在源文件旁" target:self action:@selector(toggleChanged:)];

    _extraArgsField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _extraArgsField.placeholderString = @"例如 -bibtex -f";
    _extraArgsField.target = self;
    _extraArgsField.action = @selector(extraArgsChanged:);
    _extraArgsField.delegate = (id)self;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self sectionLabel:@"编辑器"], [NSGridCell emptyContentView]],
        @[[self label:@"字体："], fontRow],
        @[[NSGridCell emptyContentView], _softWrapCheck],
        @[[NSGridCell emptyContentView], _currentLineCheck],
        @[[NSGridCell emptyContentView], _autoSaveCheck],
        @[[NSGridCell emptyContentView], _restoreSessionCheck],
        @[[self sectionLabel:@"编译"], [NSGridCell emptyContentView]],
        @[[self label:@"默认引擎："], _enginePopup],
        @[[NSGridCell emptyContentView], _autoCompileCheck],
        @[[NSGridCell emptyContentView], _shellEscapeCheck],
        @[[NSGridCell emptyContentView], _auxBesideSourceCheck],
        @[[NSGridCell emptyContentView], [self hint:@"默认放在 ~/Library/Caches/TeXMini，项目文件夹里只留 PDF 和 .synctex.gz。"]],
        @[[self label:@"附加参数："], _extraArgsField],
        @[[NSGridCell emptyContentView], [self hint:@"传给 latexmk（或无 latexmk 时直接传给引擎）。单个文件也可用 % !TEX program = xelatex 指定引擎。"]],
    ]];
    grid.rowSpacing = 10;
    grid.columnSpacing = 10;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:0].width = 90;
    [grid columnAtIndex:1].width = 340;
    // 分节标题跨两列
    [grid mergeCellsInHorizontalRange:NSMakeRange(0, 2) verticalRange:NSMakeRange(0, 1)];
    [grid mergeCellsInHorizontalRange:NSMakeRange(0, 2) verticalRange:NSMakeRange(6, 1)];
    [grid cellAtColumnIndex:0 rowIndex:0].xPlacement = NSGridCellPlacementLeading;
    [grid cellAtColumnIndex:0 rowIndex:6].xPlacement = NSGridCellPlacementLeading;
    [grid rowAtIndex:6].topPadding = 8;

    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]
    ]];
}

#pragma mark - 读写

- (void)loadValues {
    self.isLoading = YES;
    TMPreferences *p = [TMPreferences shared];

    NSString *family = [NSFont fontWithName:p.editorFontName size:12].familyName ?: p.editorFontName;
    NSInteger idx = [_fontPopup indexOfItemWithTitle:family];
    if (idx < 0) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:family action:nil keyEquivalent:@""];
        item.representedObject = p.editorFontName;
        [_fontPopup.menu insertItem:item atIndex:0];
        idx = 0;
    }
    [_fontPopup selectItemAtIndex:idx];
    _fontSizeField.doubleValue = p.editorFontSize;
    _fontSizeStepper.doubleValue = p.editorFontSize;
    _softWrapCheck.state = p.softWrapEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _currentLineCheck.state = p.highlightsCurrentLine ? NSControlStateValueOn : NSControlStateValueOff;
    _autoSaveCheck.state = p.autoSaveEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _restoreSessionCheck.state = p.restoreLastSession ? NSControlStateValueOn : NSControlStateValueOff;
    NSInteger engine = p.defaultEngine;
    [_enginePopup selectItemAtIndex:(engine >= 0 && engine < _enginePopup.numberOfItems) ? engine : 0];
    _autoCompileCheck.state = p.autoCompileEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _shellEscapeCheck.state = p.shellEscapeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _auxBesideSourceCheck.state = p.auxFilesBesideSource ? NSControlStateValueOn : NSControlStateValueOff;
    _extraArgsField.stringValue = p.latexmkExtraArguments;
    self.isLoading = NO;
}

- (void)preferencesDidChange:(NSNotification *)note {
    // 菜单里的开关（自动编译 / shell-escape / 自动换行）改了，窗口若开着要跟着刷新
    if (self.window.isVisible && !self.isLoading) [self loadValues];
}

- (void)fontChanged:(id)sender {
    if (self.isLoading) return;
    NSString *family = _fontPopup.selectedItem.representedObject ?: _fontPopup.titleOfSelectedItem;
    // 用家族名找常规字重的 PostScript 名，保证 NSFont fontWithName: 能命中
    NSFont *f = [[NSFontManager sharedFontManager] fontWithFamily:family traits:0 weight:5 size:12];
    [TMPreferences shared].editorFontName = f.fontName ?: family;
}

- (void)fontSizeFieldChanged:(id)sender {
    if (self.isLoading) return;
    [TMPreferences shared].editorFontSize = _fontSizeField.doubleValue;
    _fontSizeStepper.doubleValue = [TMPreferences shared].editorFontSize;
}

- (void)fontSizeStepperChanged:(id)sender {
    if (self.isLoading) return;
    [TMPreferences shared].editorFontSize = _fontSizeStepper.doubleValue;
    _fontSizeField.doubleValue = [TMPreferences shared].editorFontSize;
}

- (void)toggleChanged:(NSButton *)sender {
    if (self.isLoading) return;
    BOOL on = sender.state == NSControlStateValueOn;
    TMPreferences *p = [TMPreferences shared];
    if (sender == _softWrapCheck) p.softWrapEnabled = on;
    else if (sender == _currentLineCheck) p.highlightsCurrentLine = on;
    else if (sender == _autoSaveCheck) p.autoSaveEnabled = on;
    else if (sender == _restoreSessionCheck) p.restoreLastSession = on;
    else if (sender == _autoCompileCheck) p.autoCompileEnabled = on;
    else if (sender == _shellEscapeCheck) p.shellEscapeEnabled = on;
    else if (sender == _auxBesideSourceCheck) p.auxFilesBesideSource = on;
}

- (void)engineChanged:(id)sender {
    if (self.isLoading) return;
    [TMPreferences shared].defaultEngine = _enginePopup.indexOfSelectedItem;
}

- (void)extraArgsChanged:(id)sender {
    if (self.isLoading) return;
    [TMPreferences shared].latexmkExtraArguments = _extraArgsField.stringValue;
}

/// 失焦（切窗口 / 关闭）也保存附加参数，不必非按回车
- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (obj.object == _extraArgsField) [self extraArgsChanged:nil];
}

@end
