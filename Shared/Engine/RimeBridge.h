#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RimeCandidateInfo : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy, nullable) NSString *comment;
@end

@interface RimeContextSnapshot : NSObject
@property (nonatomic, copy, nullable) NSString *commitText;
@property (nonatomic, copy, nullable) NSString *preedit;
@property (nonatomic, copy) NSArray<RimeCandidateInfo *> *candidates;
@property (nonatomic, assign) BOOL isLastPage;
@property (nonatomic, assign) NSInteger pageSize;
@property (nonatomic, assign) BOOL isComposing;
@property (nonatomic, assign) BOOL isAsciiMode;
@end

/// ObjC++ 对 librime C API 的薄封装（不含 Lua）
@interface RimeBridge : NSObject

+ (instancetype)shared;

- (BOOL)startWithSharedDir:(NSString *)sharedDir
                   userDir:(NSString *)userDir
            forceFullCheck:(BOOL)forceFullCheck
                     error:(NSError * _Nullable * _Nullable)error;
- (void)shutdown;
// 外部已经 finalize 过 librime 时，只清会话标记，避免再 finalize 一次。
- (void)noteAPIShutdown;
- (BOOL)isStarted;

- (BOOL)selectSchema:(NSString *)schemaId;
- (BOOL)processKey:(int)keyCode modifiers:(int)modifiers;
- (BOOL)selectCandidateAtIndex:(int)index;
/// 按全局候选序号选中（展开面板用）
- (BOOL)selectCandidateAbsoluteIndex:(int)index;
- (BOOL)changePage:(BOOL)backward;
- (void)clearComposition;
- (nullable RimeContextSnapshot *)currentContext;
// 尚未被方案格式化的原始输入，反查时仍带前缀 z。
- (nullable NSString *)rawInput;
/// 拉取当前输入的全部候选（跨页）
- (NSArray<RimeCandidateInfo *> *)allCandidates;
- (BOOL)deploy;
- (void)syncUserData;

@end

NS_ASSUME_NONNULL_END
