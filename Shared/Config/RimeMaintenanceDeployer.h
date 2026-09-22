#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 基于当前用户配置目录执行 librime 全量部署（供主 App / Web 管理调用）
@interface RimeMaintenanceDeployer : NSObject

/// sharedDir 与 userDir 通常相同（App Group rime 目录）
+ (BOOL)deployWithSharedDir:(NSString *)sharedDir
                    userDir:(NSString *)userDir
                      error:(NSError *__autoreleasing _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
