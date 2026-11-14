#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A Vulkan host for the core's hardware renderer: instance, surface, device and
/// presentation. Opaque so the rest of the frontend never touches Vulkan types.
typedef struct AZVulkanHost AZVulkanHost;

/// Creates the instance, picks a physical device, creates a Metal-backed surface
/// for `metalLayer` (a CAMetalLayer) and asks the core's negotiation interface to
/// create the logical device and queues.
///
/// `negotiationInterface` is the core's
/// retro_hw_render_context_negotiation_interface_vulkan, passed as an opaque
/// pointer. On failure returns NULL and writes a human-readable reason, which is
/// what the app shows instead of a black screen.
FOUNDATION_EXPORT AZVulkanHost *_Nullable AZVulkanHostCreate(void *_Nullable metalLayer,
                                                             const void *negotiationInterface,
                                                             char *error,
                                                             unsigned long errorSize);

FOUNDATION_EXPORT void AZVulkanHostDestroy(AZVulkanHost *_Nullable host);

/// The image the core renders into is sized by the core's own geometry, which the
/// frontend learns from SET_GEOMETRY / SET_SYSTEM_AV_INFO.
FOUNDATION_EXPORT void AZVulkanHostSetSourceSize(AZVulkanHost *host,
                                                 unsigned width,
                                                 unsigned height);

/// Fills in a retro_hw_render_interface_vulkan (passed as an opaque pointer).
FOUNDATION_EXPORT BOOL AZVulkanHostFillInterface(AZVulkanHost *host, void *interface);

/// Blits the core's latest image into the Metal drawable and presents it.
/// Called for frames the core marks RETRO_HW_FRAME_BUFFER_VALID.
FOUNDATION_EXPORT void AZVulkanHostPresent(AZVulkanHost *host);

/// What the GPU/driver reports, for the overlay.
FOUNDATION_EXPORT const char *AZVulkanHostDescription(AZVulkanHost *host);

NS_ASSUME_NONNULL_END
