#import <Cocoa/Cocoa.h>
#import "TMOutlineItem.h"
#import "TMFileBrowserView.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMSidebarMode) {
    TMSidebarModeOutline = 0,
    TMSidebarModeFiles = 1
};

@class TMOutlineSidebarView;

@protocol TMOutlineSidebarViewDelegate <NSObject>
@optional
- (void)outlineSidebarView:(TMOutlineSidebarView *)sidebar didSelectItem:(TMOutlineItem *)item;
- (void)outlineSidebarViewDidRequestToggle:(TMOutlineSidebarView *)sidebar;
@end

/// 左侧侧边栏：顶部“大纲 | 文件”切换，下面是章节大纲或项目文件树。
@interface TMOutlineSidebarView : NSVisualEffectView

@property (nonatomic, weak, nullable) id<TMOutlineSidebarViewDelegate> delegate;
@property (nonatomic, readonly) NSArray<TMOutlineItem *> *rootItems;
@property (nonatomic, readonly) NSArray<TMOutlineItem *> *flatItems;
/// 文件页；控制器负责设置其 delegate 与根目录。
@property (nonatomic, strong, readonly) TMFileBrowserView *fileBrowserView;
/// YES 时上下同时显示大纲和文件，NO 时保留顶部单页切换。
@property (nonatomic, assign) BOOL combinedMode;
/// 当前显示的页，持久化到 NSUserDefaults。
@property (nonatomic, assign) TMSidebarMode mode;

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
