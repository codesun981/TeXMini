#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMOutlineLevel) {
    TMOutlineLevelPart = 0,
    TMOutlineLevelChapter = 1,
    TMOutlineLevelSection = 2,
    TMOutlineLevelSubsection = 3,
    TMOutlineLevelSubsubsection = 4,
    TMOutlineLevelParagraph = 5
};

@interface TMOutlineItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) TMOutlineLevel level;
@property (nonatomic, assign) NSInteger lineNumber;
@property (nonatomic, assign) NSUInteger charLocation;
@property (nonatomic, weak, nullable) TMOutlineItem *parent;
@property (nonatomic, strong) NSMutableArray<TMOutlineItem *> *children;

@property (nonatomic, readonly) NSString *levelName;
@property (nonatomic, readonly) NSString *badgeText;
@property (nonatomic, readonly) NSString *iconSystemName;

- (instancetype)initWithTitle:(NSString *)title
                        level:(TMOutlineLevel)level
                   lineNumber:(NSInteger)lineNumber
                 charLocation:(NSUInteger)charLocation;

- (void)addChild:(TMOutlineItem *)child;

@end

NS_ASSUME_NONNULL_END
