#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TMLogIssueKind) {
    TMLogIssueError = 0,
    TMLogIssueWarning,
    TMLogIssueBadBox
};

@interface TMLogIssue : NSObject
@property (nonatomic, assign) TMLogIssueKind kind;
@property (nonatomic, copy) NSString *message;
/// 源文件行号，0 表示日志里没给出。
@property (nonatomic, assign) NSInteger line;
/// 日志里给出的源文件名（-file-line-error 格式，如 "./chapters/ch1.tex"）；nil 表示未知。
@property (nonatomic, copy, nullable) NSString *filePath;
/// 状态栏 / 问题列表用的短标签：错误 / 警告 / 坏盒子。
@property (nonatomic, readonly) NSString *kindLabel;
@end

/// 从 (pdf|xe|lua)latex / latexmk 的输出里提取错误、警告和坏盒子。
@interface TMLogParser : NSObject

+ (NSArray<TMLogIssue *> *)issuesFromLog:(NSString *)log;
+ (nullable TMLogIssue *)firstErrorInIssues:(NSArray<TMLogIssue *> *)issues;
+ (NSUInteger)countOfKind:(TMLogIssueKind)kind inIssues:(NSArray<TMLogIssue *> *)issues;

@end

NS_ASSUME_NONNULL_END
