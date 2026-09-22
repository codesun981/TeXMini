#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析 TeXShop / VS Code 通用的魔法注释，例如：
///   % !TEX program = xelatex
///   % !TEX root = ../main.tex
@interface TMMagicComments : NSObject

/// 扫描前 30 行，返回 key 小写化后的字典（program / root / encoding …），值保留原大小写并去掉首尾空白。
+ (NSDictionary<NSString *, NSString *> *)magicCommentsInString:(NSString *)string;

/// 若声明了 root，返回相对文档目录解析后的标准化 URL；否则返回 nil。
+ (nullable NSURL *)rootFileURLForDocumentURL:(NSURL *)documentURL content:(NSString *)content;

@end

NS_ASSUME_NONNULL_END
