#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TMLaTeXHighlighter : NSObject

+ (void)highlightTextStorage:(NSTextStorage *)textStorage inRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
