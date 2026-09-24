#import "TMPreferences.h"

NSNotificationName const TMPreferencesDidChangeNotification = @"TMPreferencesDidChangeNotification";

static NSString *const kFontName = @"TMEditorFontName";
static NSString *const kFontSize = @"TMEditorFontSize";
static NSString *const kSoftWrap = @"TMSoftWrap";
static NSString *const kCurrentLine = @"TMHighlightCurrentLine";
static NSString *const kAutoSave = @"TMAutoSave";
static NSString *const kRestoreSession = @"TMRestoreLastSession";
static NSString *const kEngine = @"TMEngine";
static NSString *const kAutoCompile = @"TMAutoCompile";
static NSString *const kShellEscape = @"TMShellEscape";
static NSString *const kAuxFilesBesideSource = @"TMAuxFilesBesideSource";
static NSString *const kExtraArgs = @"TMLatexmkExtraArgs";
static NSString *const kPDFInverted = @"TMPDFInverted";

@implementation TMPreferences

+ (instancetype)shared {
    static TMPreferences *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[TMPreferences alloc] init]; });
    return shared;
}

+ (void)registerDefaults {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kFontName: @"Menlo",
        kFontSize: @13.5,
        kSoftWrap: @YES,
        kCurrentLine: @YES,
        kAutoSave: @YES,
        kRestoreSession: @YES,
        kEngine: @0,
        kAutoCompile: @NO,
        kShellEscape: @NO,
        kAuxFilesBesideSource: @NO,
        kExtraArgs: @"",
        kPDFInverted: @NO
    }];
}

- (NSUserDefaults *)defaults {
    return [NSUserDefaults standardUserDefaults];
}

- (void)didChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:TMPreferencesDidChangeNotification object:self];
}

#pragma mark - 编辑器

- (NSString *)editorFontName {
    NSString *name = [self.defaults stringForKey:kFontName];
    return name.length ? name : @"Menlo";
}
- (void)setEditorFontName:(NSString *)editorFontName {
    [self.defaults setObject:editorFontName ?: @"Menlo" forKey:kFontName];
    [self didChange];
}

- (CGFloat)editorFontSize {
    CGFloat size = [self.defaults doubleForKey:kFontSize];
    return (size >= 9.0 && size <= 30.0) ? size : 13.5;
}
- (void)setEditorFontSize:(CGFloat)editorFontSize {
    [self.defaults setDouble:MAX(9.0, MIN(30.0, editorFontSize)) forKey:kFontSize];
    [self didChange];
}

- (BOOL)softWrapEnabled { return [self.defaults boolForKey:kSoftWrap]; }
- (void)setSoftWrapEnabled:(BOOL)v { [self.defaults setBool:v forKey:kSoftWrap]; [self didChange]; }

- (BOOL)highlightsCurrentLine { return [self.defaults boolForKey:kCurrentLine]; }
- (void)setHighlightsCurrentLine:(BOOL)v { [self.defaults setBool:v forKey:kCurrentLine]; [self didChange]; }

- (BOOL)autoSaveEnabled { return [self.defaults boolForKey:kAutoSave]; }
- (void)setAutoSaveEnabled:(BOOL)v { [self.defaults setBool:v forKey:kAutoSave]; [self didChange]; }

#pragma mark - 启动

- (BOOL)restoreLastSession { return [self.defaults boolForKey:kRestoreSession]; }
- (void)setRestoreLastSession:(BOOL)v { [self.defaults setBool:v forKey:kRestoreSession]; [self didChange]; }

#pragma mark - 编译

- (NSInteger)defaultEngine { return [self.defaults integerForKey:kEngine]; }
- (void)setDefaultEngine:(NSInteger)v { [self.defaults setInteger:v forKey:kEngine]; [self didChange]; }

- (BOOL)autoCompileEnabled { return [self.defaults boolForKey:kAutoCompile]; }
- (void)setAutoCompileEnabled:(BOOL)v { [self.defaults setBool:v forKey:kAutoCompile]; [self didChange]; }

- (BOOL)shellEscapeEnabled { return [self.defaults boolForKey:kShellEscape]; }
- (void)setShellEscapeEnabled:(BOOL)v { [self.defaults setBool:v forKey:kShellEscape]; [self didChange]; }
- (BOOL)auxFilesBesideSource { return [self.defaults boolForKey:kAuxFilesBesideSource]; }
- (void)setAuxFilesBesideSource:(BOOL)v { [self.defaults setBool:v forKey:kAuxFilesBesideSource]; [self didChange]; }

- (NSString *)latexmkExtraArguments { return [self.defaults stringForKey:kExtraArgs] ?: @""; }
- (void)setLatexmkExtraArguments:(NSString *)v { [self.defaults setObject:v ?: @"" forKey:kExtraArgs]; [self didChange]; }

#pragma mark - PDF

- (BOOL)pdfInverted { return [self.defaults boolForKey:kPDFInverted]; }
- (void)setPdfInverted:(BOOL)v { [self.defaults setBool:v forKey:kPDFInverted]; [self didChange]; }

#pragma mark - 工具

+ (NSArray<NSString *> *)argumentsFromString:(NSString *)string {
    NSMutableArray<NSString *> *args = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    BOOL inQuotes = NO;
    BOOL hasToken = NO;
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '"') {
            inQuotes = !inQuotes;
            hasToken = YES;
        } else if (!inQuotes && (c == ' ' || c == '\t' || c == '\n')) {
            if (hasToken) { [args addObject:[current copy]]; [current setString:@""]; hasToken = NO; }
        } else {
            [current appendFormat:@"%C", c];
            hasToken = YES;
        }
    }
    if (hasToken) [args addObject:[current copy]];
    return args;
}

@end
