#import "RimeMaintenanceDeployer.h"
#include "rime_api.h"
#include <string.h>

@implementation RimeMaintenanceDeployer

+ (BOOL)deployWithSharedDir:(NSString *)sharedDir
                    userDir:(NSString *)userDir
                      error:(NSError *__autoreleasing _Nullable * _Nullable)error {
    RimeApi *api = rime_get_api();
    if (!api) {
        if (error) {
            *error = [NSError errorWithDomain:@"RimeMaintenance" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"rime_get_api failed"}];
        }
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:userDir withIntermediateDirectories:YES attributes:nil error:nil];

    // 清掉 build 缓存，强制按当前 yaml 全量重编
    NSString *buildPath = [userDir stringByAppendingPathComponent:@"build"];
    if ([fm fileExistsAtPath:buildPath]) {
        [fm removeItemAtPath:buildPath error:nil];
    }

    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = sharedDir.fileSystemRepresentation;
    traits.user_data_dir = userDir.fileSystemRepresentation;
    traits.distribution_name = "玫枫五笔";
    traits.distribution_code_name = "MeifengWubi";
    traits.distribution_version = "1.0.0";
    traits.app_name = "rime.meifeng.deploy";
    traits.min_log_level = 2;
    traits.log_dir = "";
    traits.modules = NULL;

    api->setup(&traits);
    api->initialize(&traits);

    Bool ok = False;
    if (api->start_maintenance) {
        ok = api->start_maintenance(True);
        if (ok && api->join_maintenance_thread) {
            api->join_maintenance_thread();
        }
    }
    if (!ok && api->deploy) {
        ok = api->deploy();
    }

    api->finalize();

    if (!ok) {
        if (error) {
            *error = [NSError errorWithDomain:@"RimeMaintenance" code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"start_maintenance failed"}];
        }
        return NO;
    }
    return YES;
}

@end
