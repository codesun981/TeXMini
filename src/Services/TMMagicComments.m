#import "TMMagicComments.h"

static const NSUInteger kTMMagicCommentMaxLines = 30;

@implementation TMMagicComments

+ (NSDictionary<NSString *, NSString *> *)magicCommentsInString:(NSString *)string {
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*%+\\s*!\\s*TEX\\s+([A-Za-z_-]+)\\s*=\\s*(.*?)\\s*$"
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:nil];
    });

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (string.length == 0) return result;

    __block NSUInteger lineCount = 0;
    [string enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        if (++lineCount > kTMMagicCommentMaxLines) { *stop = YES; return; }
        NSTextCheckingResult *m = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
        if (!m) return;
        NSString *key = [[line substringWithRange:[m rangeAtIndex:1]] lowercaseString];
        NSString *value = [line substringWithRange:[m rangeAtIndex:2]];
        if (value.length > 0 && !result[key]) result[key] = value;
    }];
    return result;
}

+ (nullable NSURL *)rootFileURLForDocumentURL:(NSURL *)documentURL content:(NSString *)content {
    NSString *root = [self magicCommentsInString:content][@"root"];
    if (root.length == 0) return nil;
    NSURL *dir = documentURL.URLByDeletingLastPathComponent;
    NSURL *url = [NSURL fileURLWithPath:root relativeToURL:dir];
    return url.URLByStandardizingPath.absoluteURL;
}

@end
