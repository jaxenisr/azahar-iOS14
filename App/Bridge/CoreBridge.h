#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Called once per emulated frame, on the emulation thread, with an image that
/// is only valid for the duration of the call. Retain it to keep it.
typedef void (*AZCoreFrameCallback)(CGImageRef _Nullable image, void *_Nullable context);

/// Called when the core shows a message to the user (missing system files, an
/// encrypted ROM, a fatal error). The string is only valid for the call.
typedef void (*AZCoreMessageCallback)(const char *_Nullable message, void *_Nullable context);

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

/// Requests a core option value. Call before AZCoreInitialize: the core reads its
/// options back while it registers them, and an override wins over its default.
FOUNDATION_EXPORT void AZCoreSetOption(NSString *key, NSString *value);

FOUNDATION_EXPORT void AZCoreSetFrameCallback(AZCoreFrameCallback _Nullable callback,
                                              void *_Nullable context);
FOUNDATION_EXPORT void AZCoreSetMessageCallback(AZCoreMessageCallback _Nullable callback,
                                                void *_Nullable context);

/// Loads a ROM. Returns NO when the core refuses the file and sets AZCoreLastError
/// to the core's own explanation (encrypted ROM, unsupported format, ...).
FOUNDATION_EXPORT BOOL AZCoreLoadGame(NSString *path);

/// Runs exactly one frame. Must only be called from one thread, after a successful
/// AZCoreLoadGame.
FOUNDATION_EXPORT void AZCoreRunFrame(void);

/// Unloads the current game. Frames must not be requested afterwards.
FOUNDATION_EXPORT void AZCoreUnloadGame(void);

/// Frame rate the loaded content asked for, in Hz (60 before a game is loaded).
FOUNDATION_EXPORT double AZCoreFrameRate(void);

/// Number of frames handed to the frame callback since the current game loaded.
FOUNDATION_EXPORT unsigned long long AZCoreFramesDelivered(void);

/// libretro joystick state: bit N is RETRO_DEVICE_ID_JOYPAD_* button N.
FOUNDATION_EXPORT void AZCoreSetButtons(unsigned mask);

/// Circle pad, each axis in -32768...32767.
FOUNDATION_EXPORT void AZCoreSetCirclePad(int x, int y);

/// Most recent message the core wanted to show, or nil.
FOUNDATION_EXPORT NSString *_Nullable AZCoreLastMessage(void);

/// The CAMetalLayer the Vulkan renderer presents into. Set before loading content.
FOUNDATION_EXPORT void AZCoreSetMetalLayer(void *_Nullable layer);

/// YES asks for the Vulkan hardware renderer (the default); NO pins the core's
/// software rasteriser, which is only useful when isolating a GPU problem.
FOUNDATION_EXPORT void AZCoreSetRendererPreference(BOOL preferVulkan);

/// What is actually rendering: the Vulkan device name, or the software path and
/// the reason it was chosen. Valid after a load attempt.
FOUNDATION_EXPORT const char *AZCoreRendererName(void);

/// YES when frames are arriving from the GPU rather than as CPU bitmaps.
FOUNDATION_EXPORT BOOL AZCoreUsesHardwareVideo(void);

NS_ASSUME_NONNULL_END
