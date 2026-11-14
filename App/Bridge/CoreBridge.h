#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// libretro API version reported by the linked Azahar core.
FOUNDATION_EXPORT unsigned AZCoreAPIVersion(void);

/// Human-readable description of the linked core (name, version, extensions).
/// Does not initialise emulation.
FOUNDATION_EXPORT NSString *AZCoreDescribe(void);

/// Initialises the core. Must be called before anything else that runs emulation.
/// The directories are where the core keeps system files and save data.
FOUNDATION_EXPORT BOOL AZCoreInitialize(NSString *saveDirectory, NSString *systemDirectory);

/// Description of the last initialisation failure, or nil.
FOUNDATION_EXPORT NSString *_Nullable AZCoreLastError(void);

/// Shuts the core down and releases its global state.
FOUNDATION_EXPORT void AZCoreShutdown(void);

NS_ASSUME_NONNULL_END
