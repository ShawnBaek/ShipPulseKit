#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns any Objective-C exception it raised instead of crashing.
/// Swift can't catch NSException, and `CKContainer.defaultContainer` raises one when the app
/// has no iCloud container entitlement.
FOUNDATION_EXPORT NSException * _Nullable SPKCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
