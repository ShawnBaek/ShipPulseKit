#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns any Objective-C exception it raised instead of crashing.
/// Swift can't catch NSException, and CloudKit can raise one when it opens a container.
/// This can't catch a trap (`EXC_BREAKPOINT`), which is what CloudKit does on iOS when the app
/// has no iCloud entitlement, so `CloudKitEntitlements` must be checked before calling CloudKit.
FOUNDATION_EXPORT NSException * _Nullable SPKCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
