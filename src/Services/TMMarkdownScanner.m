#import "TMMarkdownScanner.h"

@implementation TMMarkdownScanResult {
    TMMarkdownRegion *_regions;
    NSUInteger _count;
    NSUInteger _capacity;
}

- (void)dealloc {
    free(_regions);
}

- (NSUInteger)regionCount { return _count; }
- (const TMMarkdownRegion *)regions { return _regions; }

- (void)add:(TMMarkdownRegionKind)kind from:(NSUInteger)start to:(NSUInteger)end {
    if (end <= start) return;
    if (_count == _capacity) {
        _capacity = _capacity ? _capacity * 2 : 128;
        _regions = realloc(_regions, _capacity * sizeof(TMMarkdownRegion));
    }
    _regions[_count++] = (TMMarkdownRegion){kind, NSMakeRange(start, end - start)};
}

static int TMCompareMarkdownRegions(const void *a, const void *b) {
    NSUInteger la = ((const TMMarkdownRegion *)a)->range.location;
    NSUInteger lb = ((const TMMarkdownRegion *)b)->range.location;
    return la < lb ? -1 : (la > lb ? 1 : 0);
}

- (void)finish {
    qsort(_regions, _count, sizeof(TMMarkdownRegion), TMCompareMarkdownRegions);
}

@end

@implementation TMMarkdownScanner {
    const unichar *_s;
    NSUInteger _n;
    TMMarkdownScanResult *_result;
}

+ (TMMarkdownScanResult *)scanString:(NSString *)string {
    return [[[TMMarkdownScanner alloc] init] scan:string ?: @""];
}

- (TMMarkdownScanResult *)scan:(NSString *)string {
    _n = string.length;
    unichar *buffer = malloc(MAX(_n, 1) * sizeof(unichar));
    [string getCharacters:buffer range:NSMakeRange(0, _n)];
    _s = buffer;
    _result = [[TMMarkdownScanResult alloc] init];

    NSUInteger fenceStart = NSNotFound;
    NSUInteger i = 0;
    while (i < _n) {
        NSUInteger lineEnd = i;
        while (lineEnd < _n && _s[lineEnd] != '\n') lineEnd++;
        NSUInteger indent = i;
        while (indent < lineEnd && (_s[indent] == ' ' || _s[indent] == '\t')) indent++;
        BOOL isFence = [self isFenceAt:indent lineEnd:lineEnd];

        if (fenceStart != NSNotFound) {
            // 代码块内部原样，直到闭合围栏
            if (isFence) {
                [_result add:TMMarkdownRegionCode from:fenceStart to:lineEnd];
                fenceStart = NSNotFound;
            }
        } else if (isFence) {
            fenceStart = i;
        } else {
            [self scanLineFrom:i indent:indent to:lineEnd];
        }
        i = lineEnd + 1;
    }
    // 没闭合的围栏：到文末都算代码
    if (fenceStart != NSNotFound) [_result add:TMMarkdownRegionCode from:fenceStart to:_n];

    free(buffer);
    _s = NULL;
    [_result finish];
    return _result;
}

- (BOOL)isFenceAt:(NSUInteger)i lineEnd:(NSUInteger)lineEnd {
    if (i + 3 > lineEnd) return NO;
    unichar c = _s[i];
    return (c == '`' || c == '~') && _s[i + 1] == c && _s[i + 2] == c;
}

- (void)scanLineFrom:(NSUInteger)start indent:(NSUInteger)i to:(NSUInteger)end {
    if (i >= end) return;
    unichar c = _s[i];

    // # 标题（# 后面要有空格或直接行尾）
    if (c == '#') {
        NSUInteger j = i;
        while (j < end && _s[j] == '#') j++;
        if (j - i <= 6 && (j == end || _s[j] == ' ' || _s[j] == '\t')) {
            [_result add:TMMarkdownRegionHeading from:i to:end];
            [_result add:TMMarkdownRegionMarker from:i to:j];
            [self scanInlineFrom:j to:end];
            return;
        }
    }

    // 分隔线：--- *** ___（可夹空格）
    if (c == '-' || c == '*' || c == '_') {
        NSUInteger marks = 0;
        BOOL onlyMarks = YES;
        for (NSUInteger j = i; j < end; j++) {
            if (_s[j] == c) marks++;
            else if (_s[j] != ' ' && _s[j] != '\t') { onlyMarks = NO; break; }
        }
        if (onlyMarks && marks >= 3) {
            [_result add:TMMarkdownRegionMarker from:i to:end];
            return;
        }
    }

    // > 引用
    if (c == '>') {
        [_result add:TMMarkdownRegionQuote from:i to:end];
        [_result add:TMMarkdownRegionMarker from:i to:i + 1];
        [self scanInlineFrom:i + 1 to:end];
        return;
    }

    // 列表：- * + 或 1. 1)，后面跟空格
    NSUInteger markerEnd = NSNotFound;
    if ((c == '-' || c == '*' || c == '+') && i + 1 < end && _s[i + 1] == ' ') {
        markerEnd = i + 1;
    } else if (c >= '0' && c <= '9') {
        NSUInteger j = i;
        while (j < end && _s[j] >= '0' && _s[j] <= '9') j++;
        if (j < end && (_s[j] == '.' || _s[j] == ')') && j + 1 < end && _s[j + 1] == ' ') markerEnd = j + 1;
    }
    if (markerEnd != NSNotFound) {
        [_result add:TMMarkdownRegionMarker from:i to:markerEnd];
        i = markerEnd;
    }
    [self scanInlineFrom:i to:end];
}

/// 行内：`代码` 优先（里面不再解析），然后链接、**粗**、*斜*、~~删~~
- (void)scanInlineFrom:(NSUInteger)start to:(NSUInteger)end {
    NSUInteger i = start;
    while (i < end) {
        unichar c = _s[i];
        if (c == '\\' && i + 1 < end) { i += 2; continue; }

        if (c == '`') {
            NSUInteger ticks = i;
            while (ticks < end && _s[ticks] == '`') ticks++;
            NSUInteger width = ticks - i;
            NSUInteger close = [self findRun:'`' width:width from:ticks to:end];
            if (close != NSNotFound) {
                [_result add:TMMarkdownRegionCode from:i to:close + width];
                i = close + width;
                continue;
            }
            i = ticks;
            continue;
        }

        if (c == '[' || (c == '!' && i + 1 < end && _s[i + 1] == '[')) {
            NSUInteger open = c == '!' ? i + 1 : i;
            NSUInteger closeBracket = [self find:']' from:open + 1 to:end];
            if (closeBracket != NSNotFound && closeBracket + 1 < end && _s[closeBracket + 1] == '(') {
                NSUInteger closeParen = [self find:')' from:closeBracket + 2 to:end];
                if (closeParen != NSNotFound) {
                    [_result add:TMMarkdownRegionLink from:i to:closeParen + 1];
                    i = closeParen + 1;
                    continue;
                }
            }
        }

        if ((c == '*' || c == '_' || c == '~') && i + 1 < end) {
            BOOL doubled = _s[i + 1] == c;
            if (c == '~' && !doubled) { i++; continue; }
            NSUInteger width = doubled ? 2 : 1;
            NSUInteger contentStart = i + width;
            // 标记后面紧跟空格的不是强调（例如 "a * b"）
            if (contentStart < end && _s[contentStart] != ' ') {
                NSUInteger close = [self findRun:c width:width from:contentStart + 1 to:end];
                // _ 夹在单词里（snake_case）不算
                BOOL wordInner = c == '_' && i > start && [self isWordChar:_s[i - 1]];
                if (close != NSNotFound && _s[close - 1] != ' ' && !wordInner) {
                    TMMarkdownRegionKind kind = c == '~' ? TMMarkdownRegionStrike
                                              : (doubled ? TMMarkdownRegionStrong : TMMarkdownRegionEmphasis);
                    [_result add:kind from:i to:close + width];
                    [self scanInlineFrom:contentStart to:close];
                    i = close + width;
                    continue;
                }
            }
            i += width;
            continue;
        }
        i++;
    }
}

- (BOOL)isWordChar:(unichar)c {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

- (NSUInteger)find:(unichar)target from:(NSUInteger)i to:(NSUInteger)end {
    for (; i < end; i++) {
        if (_s[i] == '\\') { i++; continue; }
        if (_s[i] == target) return i;
    }
    return NSNotFound;
}

/// 恰好 width 个连续 c（不多不少）的位置
- (NSUInteger)findRun:(unichar)c width:(NSUInteger)width from:(NSUInteger)i to:(NSUInteger)end {
    while (i < end) {
        if (_s[i] == '\\') { i += 2; continue; }
        if (_s[i] != c) { i++; continue; }
        NSUInteger j = i;
        while (j < end && _s[j] == c) j++;
        if (j - i == width) return i;
        i = j;
    }
    return NSNotFound;
}

@end
