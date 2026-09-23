#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// ⌘, 偏好设置：一页搞定，改动立即生效并通过 TMPreferencesDidChangeNotification 广播。
@interface TMPreferencesWindowController : NSWindowController

+ (instancetype)shared;
- (void)showPreferences;

@end

NS_ASSUME_NONNULL_END
