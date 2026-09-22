#import <Cocoa/Cocoa.h>
#import "TMOutlineItem.h"

NS_ASSUME_NONNULL_BEGIN

@class TMOutlineSidebarView;

@protocol TMOutlineSidebarViewDelegate <NSObject>
@optional
- (void)outlineSidebarView:(TMOutlineSidebarView *)sidebar didSelectItem:(TMOutlineItem *)item;
- (void)outlineSidebarViewDidRequestToggle:(TMOutlineSidebarView *)sidebar;
@end

@interface TMOutlineSidebarView : NSVisualEffectView

@property (nonatomic, weak, nullable) id<TMOutlineSidebarViewDelegate> delegate;
@property (nonatomic, readonly) NSArray<TMOutlineItem *> *rootItems;
@property (nonatomic, readonly) NSArray<TMOutlineItem *> *flatItems;

/**
 * 更新大纲数据源并刷新视图。
 * @param rootItems 树状根节点列表
 * @param flatItems 扁平列表
 */
- (void)updateWithRootItems:(NSArray<TMOutlineItem *> *)rootItems
                  flatItems:(NSArray<TMOutlineItem *> *)flatItems;

/**
 * 根据源码光标行号高亮对应的大纲项（不触发点击回调）
 */
- (void)highlightItemForLineNumber:(NSInteger)lineNumber;

@end

NS_ASSUME_NONNULL_END
