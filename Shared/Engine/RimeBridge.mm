#import "RimeBridge.h"
#include "rime_api.h"
#include <string.h>
#include <stdlib.h>

@implementation RimeCandidateInfo
@end

@implementation RimeContextSnapshot
@end

@interface RimeBridge ()
@property (nonatomic, assign) BOOL started;
@property (nonatomic, assign) RimeSessionId sessionId;
@property (nonatomic, assign) RimeApi *api;
@property (nonatomic, copy) NSString *userDataDir;
@end

@implementation RimeBridge

+ (instancetype)shared {
    static RimeBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RimeBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _api = rime_get_api();
    }
    return self;
}

- (BOOL)startWithSharedDir:(NSString *)sharedDir
                   userDir:(NSString *)userDir
            forceFullCheck:(BOOL)forceFullCheck
                     error:(NSError *__autoreleasing  _Nullable *)error {
    if (!_api) {
        if (error) {
            *error = [NSError errorWithDomain:@"RimeBridge" code:1 userInfo:@{NSLocalizedDescriptionKey: @"rime_get_api failed"}];
        }
        return NO;
    }
    if (_started) {
        return YES;
    }

    // 确保用户目录存在
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:userDir withIntermediateDirectories:YES attributes:nil error:nil];
    self.userDataDir = userDir;

    NSString *tableBin = [userDir stringByAppendingPathComponent:@"build/wubi86_jidian.table.bin"];
    BOOL hasTable = [fm fileExistsAtPath:tableBin];
    // App 已部署过则勿在扩展里全量重编；仅缺产物或显式要求时 full_check
    BOOL doFull = forceFullCheck || !hasTable;

    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = sharedDir.fileSystemRepresentation;
    traits.user_data_dir = userDir.fileSystemRepresentation;
    traits.distribution_name = "玫枫五笔";
    traits.distribution_code_name = "MeifengWubi";
    traits.distribution_version = "1.0.0";
    traits.app_name = "rime.meifeng";
    traits.min_log_level = 2; // ERROR
    traits.log_dir = ""; // stderr only，避免扩展写日志失败
    // modules 置空：仅内置 core，不加载 Lua 等外部插件
    traits.modules = NULL;

    _api->setup(&traits);
    _api->initialize(&traits);

    Bool maintenance = _api->start_maintenance(doFull ? True : False);
    if (maintenance && _api->join_maintenance_thread) {
        _api->join_maintenance_thread();
    }
    // 轻量维护后仍无词库：再强制全量一次（首次安装）
    if (![fm fileExistsAtPath:tableBin] && !doFull) {
        maintenance = _api->start_maintenance(True);
        if (maintenance && _api->join_maintenance_thread) {
            _api->join_maintenance_thread();
        }
    }

    _sessionId = _api->create_session();
    if (!_sessionId) {
        if (error) {
            *error = [NSError errorWithDomain:@"RimeBridge" code:2 userInfo:@{NSLocalizedDescriptionKey: @"create_session failed"}];
        }
        _api->finalize();
        return NO;
    }

    _started = YES;
    _api->select_schema(_sessionId, "wubi86_jidian");
    return YES;
}

- (void)shutdown {
    if (!_api || !_started) { return; }
    if (_sessionId) {
        _api->destroy_session(_sessionId);
        _sessionId = 0;
    }
    _api->finalize();
    _started = NO;
}

- (void)noteAPIShutdown {
    _sessionId = 0;
    _started = NO;
}

- (BOOL)isStarted {
    return _started;
}

- (BOOL)selectSchema:(NSString *)schemaId {
    if (!_started || !_sessionId) { return NO; }
    return _api->select_schema(_sessionId, schemaId.UTF8String);
}

- (BOOL)processKey:(int)keyCode modifiers:(int)modifiers {
    if (!_started || !_sessionId) { return NO; }
    return _api->process_key(_sessionId, keyCode, modifiers);
}

- (BOOL)selectCandidateAtIndex:(int)index {
    if (!_started || !_sessionId) { return NO; }
    if (_api->select_candidate_on_current_page) {
        return _api->select_candidate_on_current_page(_sessionId, (size_t)index);
    }
    return _api->process_key(_sessionId, '1' + index, 0);
}

- (BOOL)selectCandidateAbsoluteIndex:(int)index {
    if (!_started || !_sessionId) { return NO; }
    if (_api->select_candidate) {
        return _api->select_candidate(_sessionId, (size_t)index);
    }
    return [self selectCandidateAtIndex:index];
}

- (BOOL)changePage:(BOOL)backward {
    if (!_started || !_sessionId) { return NO; }
    if (_api->change_page) {
        return _api->change_page(_sessionId, backward);
    }
    return _api->process_key(_sessionId, backward ? 0xff55 : 0xff56, 0);
}

- (void)clearComposition {
    if (!_started || !_sessionId) { return; }
    _api->clear_composition(_sessionId);
}

- (NSArray<RimeCandidateInfo *> *)allCandidates {
    if (!_started || !_sessionId || !_api->candidate_list_begin) {
        return self.currentContext.candidates ?: @[];
    }
    RimeCandidateListIterator it = {0};
    if (!_api->candidate_list_begin(_sessionId, &it)) {
        return self.currentContext.candidates ?: @[];
    }
    NSMutableArray<RimeCandidateInfo *> *list = [NSMutableArray array];
    while (_api->candidate_list_next(&it)) {
        RimeCandidateInfo *c = [RimeCandidateInfo new];
        c.text = it.candidate.text ? [NSString stringWithUTF8String:it.candidate.text] : @"";
        c.comment = it.candidate.comment ? [NSString stringWithUTF8String:it.candidate.comment] : @"";
        [list addObject:c];
        if (list.count >= 120) { break; } // 扩展内存保护
    }
    _api->candidate_list_end(&it);
    return list;
}

- (RimeContextSnapshot *)currentContext {
    if (!_started || !_sessionId) { return nil; }

    RimeContextSnapshot *snap = [RimeContextSnapshot new];
    snap.candidates = @[];

    RIME_STRUCT(RimeCommit, commit);
    if (_api->get_commit(_sessionId, &commit)) {
        if (commit.text) {
            snap.commitText = [NSString stringWithUTF8String:commit.text];
        }
        _api->free_commit(&commit);
    }

    RIME_STRUCT(RimeContext, ctx);
    if (_api->get_context(_sessionId, &ctx)) {
        if (ctx.composition.preedit) {
            snap.preedit = [NSString stringWithUTF8String:ctx.composition.preedit];
        }
        snap.isLastPage = ctx.menu.is_last_page;
        snap.pageSize = ctx.menu.page_size;
        NSMutableArray<RimeCandidateInfo *> *list = [NSMutableArray array];
        for (int i = 0; i < ctx.menu.num_candidates; i++) {
            RimeCandidateInfo *c = [RimeCandidateInfo new];
            if (ctx.menu.candidates[i].text) {
                c.text = [NSString stringWithUTF8String:ctx.menu.candidates[i].text];
            } else {
                c.text = @"";
            }
            if (ctx.menu.candidates[i].comment) {
                c.comment = [NSString stringWithUTF8String:ctx.menu.candidates[i].comment];
            } else {
                c.comment = @"";
            }
            [list addObject:c];
        }
        snap.candidates = list;
        _api->free_context(&ctx);
    }

    RIME_STRUCT(RimeStatus, status);
    if (_api->get_status(_sessionId, &status)) {
        snap.isComposing = status.is_composing;
        snap.isAsciiMode = status.is_ascii_mode;
        _api->free_status(&status);
    }
    return snap;
}

- (BOOL)deploy {
    if (!_api || !_started) { return NO; }

    // 扩展内禁止整目录删 build：大词库重编易失败/被杀，导致「部署后无候选」
    // 交给 librime 增量检测 yaml 变更即可
    Bool ok = False;
    if (_api->start_maintenance) {
        ok = _api->start_maintenance(True);
        if (ok && _api->join_maintenance_thread) {
            _api->join_maintenance_thread();
        }
    }
    if (!ok && _api->deploy) {
        ok = _api->deploy();
    }

    if (_sessionId) {
        _api->destroy_session(_sessionId);
        _sessionId = 0;
    }
    _sessionId = _api->create_session();
    if (_sessionId) {
        _api->select_schema(_sessionId, "wubi86_jidian");
    } else {
        // 会话没建起来时完整收尾；下次 start 才能从干净状态重新 initialize。
        _api->finalize();
        _started = NO;
    }
    return _sessionId != 0;
}

- (void)syncUserData {
    if (!_api || !_started) { return; }
    if (_api->sync_user_data) {
        _api->sync_user_data();
    }
}

@end
