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

/// Circle pad, each axis in -32768...32767, Y positive downwards (the core
/// negates it when it reads the analog device).
FOUNDATION_EXPORT void AZCoreSetCirclePad(int x, int y);

/// Touchscreen position in frame coordinates: x is -1 at the left edge and 1 at
/// the right, y is -1 at the top and 1 at the bottom. The core maps that onto
/// the bottom screen for whichever layout is active, so this frontend never has
/// to know where the bottom screen sits.
///
/// A press is held for a few frames after `pressed` goes back to NO: the core
/// samples input once per frame, and a tap that ends between two samples would
/// otherwise be lost entirely.
FOUNDATION_EXPORT void AZCoreSetPointer(float x, float y, BOOL pressed);

/// Counters for the touch path, cumulative since the core started.
///
/// `polls` counts the times the core asked for a pointer — it asks up to four
/// times a frame (pressed, count, x, y), so it climbs on its own while a game
/// runs. `pressedFrames` counts the frames in which the core saw a press, which
/// is the number that has to reach 2 for a tap to reach the game.
FOUNDATION_EXPORT void AZCorePointerStats(unsigned long long *polls,
                                          unsigned long long *pressedFrames);

/// Audio the core produces, handed over as interleaved stereo int16 frames. The
/// pointer is only valid for the duration of the call. Azahar drives this from
/// audio_sample_batch only: it registers audio_sample but never calls it.
typedef void (*AZCoreAudioCallback)(const int16_t *_Nullable frames,
                                    size_t frameCount,
                                    void *_Nullable context);

FOUNDATION_EXPORT void AZCoreSetAudioCallback(AZCoreAudioCallback _Nullable callback,
                                              void *_Nullable context);

/// Sample rate the content asked for, in Hz (Azahar's audio core runs at 32728
/// for every title, but the number comes from the core, not from here).
FOUNDATION_EXPORT double AZCoreSampleRate(void);

/// How many audio_sample_batch calls and stereo frames the core has produced.
/// The first number answers "is the core calling us at all", the second "how
/// much sound it thinks it has made".
FOUNDATION_EXPORT unsigned long long AZCoreAudioBatchCalls(void);
FOUNDATION_EXPORT unsigned long long AZCoreAudioFramesProduced(void);

/// Size in bytes of one save state, or 0 when the core cannot serialise this
/// content. Must be called on the emulation thread while a game is loaded.
FOUNDATION_EXPORT size_t AZCoreSerializeSize(void);

/// Writes / restores one save state. Emulation thread only, game loaded.
FOUNDATION_EXPORT BOOL AZCoreSaveState(NSString *path);
FOUNDATION_EXPORT BOOL AZCoreLoadState(NSString *path);

/// Size of the frame the core currently produces, in its own pixels. The present
/// path letterboxes this into the drawable, and touch input is normalised over
/// the same rectangle.
FOUNDATION_EXPORT CGSize AZCoreSourceSize(void);

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

/// Presents the stacked layout with a hinge between the two screens.
///
/// `hinge` is the gap as a fraction of the presented pair's height, 0 to present
/// the core's frame as it is. The core stacks the screens flush, so the visible
/// hinge comes from here. Safe to call before the core is initialised: the value
/// is applied when the presentation host is created.
FOUNDATION_EXPORT void AZCoreSetStackedPresentation(float hinge);

NS_ASSUME_NONNULL_END
