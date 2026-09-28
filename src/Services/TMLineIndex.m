#import "TMLineIndex.h"

@implementation TMLineIndex {
    NSData *_starts;
}

- (instancetype)initWithString:(NSString *)string {
    if ((self = [super init])) {
        _length = string.length;
        NSMutableData *starts = [NSMutableData data];
        NSUInteger zero = 0;
        [starts appendBytes:&zero length:sizeof(zero)];
        unichar buffer[4096];
        for (NSUInteger offset = 0; offset < _length; offset += 4096) {
            NSUInteger count = MIN((NSUInteger)4096, _length - offset);
            [string getCharacters:buffer range:NSMakeRange(offset, count)];
            for (NSUInteger i = 0; i < count; i++) {
                if (buffer[i] == '\n') {
                    NSUInteger next = offset + i + 1;
                    [starts appendBytes:&next length:sizeof(next)];
                }
            }
        }
        _starts = starts;
    }
    return self;
}

- (NSUInteger)lineCount { return _starts.length / sizeof(NSUInteger); }

- (NSUInteger)lineNumberForCharacterIndex:(NSUInteger)index {
    index = MIN(index, self.length);
    const NSUInteger *starts = _starts.bytes;
    NSUInteger lo = 0, hi = self.lineCount;
    while (hi - lo > 1) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (starts[mid] <= index) lo = mid; else hi = mid;
    }
    return lo + 1;
}

- (NSUInteger)startOfLine:(NSUInteger)line {
    if (line == 0 || line > self.lineCount) return NSNotFound;
    return ((const NSUInteger *)_starts.bytes)[line - 1];
}
@end
