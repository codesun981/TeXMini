#import <Cocoa/Cocoa.h>
#import "TMLogParser.h"

NS_ASSUME_NONNULL_BEGIN

@class TMLogDrawerView;

@protocol TMLogDrawerViewDelegate <NSObject>
@optional
/// 用户点击了问题列表里的一条（line 可能为 0）。
- (void)logDrawerView:(TMLogDrawerView *)drawer didSelectIssue:(TMLogIssue *)issue;
@end

/// 底部抽屉：左上角「问题 | 原始日志」切换。问题页是可点击的错误/警告表格，原始日志页是逐行着色的完整输出。
@interface TMLogDrawerView : NSView

@property (nonatomic, weak, nullable) id<TMLogDrawerViewDelegate> delegate;
@property (nonatomic, assign) BOOL isExpanded;

- (void)appendLogText:(NSString *)text;
/// 清空原始日志与问题列表（编译开始时调用）。
- (void)clearLog;
/// 编译结束后填入解析结果；有问题时自动切到问题页，否则停在原始日志。
- (void)setIssues:(NSArray<TMLogIssue *> *)issues;
- (void)toggleAnimated;

@end

NS_ASSUME_NONNULL_END
