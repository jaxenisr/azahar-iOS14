#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns nil, or the exception it raised as @{ name, reason,
/// callStack }.
///
/// AVFAudio raises NSException for a format or a graph it refuses, and Swift
/// cannot catch one: it unwinds through the Swift frames and terminates the
/// process. An Objective-C @try is the only place it can be stopped, so every
/// call into the audio graph goes through here.
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable AZTryCatch(void (^block)(void));

/// Logs the name and reason of any uncaught exception before the process dies,
/// so a crash report is not the only record of it.
FOUNDATION_EXPORT void AZInstallExceptionHandler(void);

NS_ASSUME_NONNULL_END
