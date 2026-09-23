#import "TMFontCatalog.h"
#import <CoreText/CoreText.h>

@interface TMFontFamily ()
@property (nonatomic, copy, readwrite) NSString *familyName;
@property (nonatomic, copy, readwrite) NSString *displayName;
@property (nonatomic, assign, readwrite) BOOL supportsChinese;
@property (nonatomic, assign, readwrite) BOOL hasBold;
@end

@implementation TMFontFamily
@end

@interface TMFontCatalog ()
@property (nonatomic, copy, readwrite, nullable) NSArray<TMFontFamily *> *families;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, TMFontFamily *> *familiesByLowercaseName;
@property (nonatomic, strong) NSMutableArray *pendingCompletions;
@end

@implementation TMFontCatalog

+ (instancetype)shared {
    static TMFontCatalog *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[TMFontCatalog alloc] init]; });
    return shared;
}

- (void)loadWithCompletion:(void (^)(NSArray<TMFontFamily *> *))completion {
    if (self.families) { completion(self.families); return; }
    BOOL alreadyLoading = self.pendingCompletions != nil;
    if (!alreadyLoading) self.pendingCompletions = [NSMutableArray array];
    [self.pendingCompletions addObject:[completion copy]];
    if (alreadyLoading) return;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<TMFontFamily *> *families = [TMFontCatalog enumerateSystemFamilies];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *byName = [NSMutableDictionary dictionary];
            for (TMFontFamily *f in families) byName[f.familyName.lowercaseString] = f;
            self.familiesByLowercaseName = byName;
            self.families = families;
            NSArray *callbacks = self.pendingCompletions;
            self.pendingCompletions = nil;
            for (void (^cb)(NSArray *) in callbacks) cb(families);
        });
    });
}

- (nullable TMFontFamily *)familyNamed:(NSString *)name {
    return self.familiesByLowercaseName[name.lowercaseString];
}

+ (NSArray<TMFontFamily *> *)enumerateSystemFamilies {
    NSArray<NSString *> *names = CFBridgingRelease(CTFontManagerCopyAvailableFontFamilyNames());
    NSMutableArray<TMFontFamily *> *result = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        CTFontDescriptorRef desc = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)@{(id)kCTFontFamilyNameAttribute: name});
        NSArray *members = CFBridgingRelease(CTFontDescriptorCreateMatchingFontDescriptors(desc, NULL));
        NSString *localized = CFBridgingRelease(CTFontDescriptorCopyLocalizedAttribute(desc, kCTFontFamilyNameAttribute, NULL));
        CFRelease(desc);
        if (members.count == 0) continue;

        BOOL usable = YES, chinese = NO, bold = NO;
        for (id member in members) {
            CTFontDescriptorRef m = (__bridge CTFontDescriptorRef)member;
            NSURL *url = CFBridgingRelease(CTFontDescriptorCopyAttribute(m, kCTFontURLAttribute));
            NSNumber *format = CFBridgingRelease(CTFontDescriptorCopyAttribute(m, kCTFontFormatAttribute));
            if ([url.path containsString:@"/PrivateFrameworks/"] || format.intValue == kCTFontFormatBitmap) { usable = NO; break; }
            if (!chinese) {
                NSArray<NSString *> *langs = CFBridgingRelease(CTFontDescriptorCopyAttribute(m, kCTFontLanguagesAttribute));
                for (NSString *l in langs) if ([l hasPrefix:@"zh"]) { chinese = YES; break; }
            }
            NSDictionary *traits = CFBridgingRelease(CTFontDescriptorCopyAttribute(m, kCTFontTraitsAttribute));
            if ([traits[(id)kCTFontSymbolicTrait] unsignedIntValue] & kCTFontBoldTrait) bold = YES;
        }
        if (!usable) continue;

        TMFontFamily *f = [[TMFontFamily alloc] init];
        f.familyName = name;
        f.displayName = localized.length ? localized : name;
        f.supportsChinese = chinese;
        f.hasBold = bold;
        [result addObject:f];
    }
    [result sortUsingComparator:^NSComparisonResult(TMFontFamily *a, TMFontFamily *b) {
        return [a.familyName localizedCaseInsensitiveCompare:b.familyName];
    }];
    return result;
}

@end
