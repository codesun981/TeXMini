#import "TMOutlineItem.h"

@implementation TMOutlineItem

- (instancetype)initWithTitle:(NSString *)title
                        level:(TMOutlineLevel)level
                   lineNumber:(NSInteger)lineNumber
                 charLocation:(NSUInteger)charLocation {
    self = [super init];
    if (self) {
        _title = [title copy] ?: @"";
        _level = level;
        _lineNumber = lineNumber;
        _charLocation = charLocation;
        _children = [NSMutableArray array];
    }
    return self;
}

- (void)addChild:(TMOutlineItem *)child {
    child.parent = self;
    [self.children addObject:child];
}

- (NSString *)levelName {
    switch (self.level) {
        case TMOutlineLevelPart: return @"part";
        case TMOutlineLevelChapter: return @"chapter";
        case TMOutlineLevelSection: return @"section";
        case TMOutlineLevelSubsection: return @"subsection";
        case TMOutlineLevelSubsubsection: return @"subsubsection";
        case TMOutlineLevelParagraph: return @"paragraph";
    }
}

- (NSString *)badgeText {
    switch (self.level) {
        case TMOutlineLevelPart: return @"Part";
        case TMOutlineLevelChapter: return @"Ch";
        case TMOutlineLevelSection: return @"H1";
        case TMOutlineLevelSubsection: return @"H2";
        case TMOutlineLevelSubsubsection: return @"H3";
        case TMOutlineLevelParagraph: return @"¶";
    }
}

- (NSString *)iconSystemName {
    switch (self.level) {
        case TMOutlineLevelPart: return @"book.closed";
        case TMOutlineLevelChapter: return @"book";
        case TMOutlineLevelSection: return @"number";
        case TMOutlineLevelSubsection: return @"list.bullet.indent";
        case TMOutlineLevelSubsubsection: return @"text.alignleft";
        case TMOutlineLevelParagraph: return @"paragraphsign";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<TMOutlineItem: L%ld (%@) '%@', %lu children>",
            (long)self.lineNumber, self.levelName, self.title, (unsigned long)self.children.count];
}

@end
