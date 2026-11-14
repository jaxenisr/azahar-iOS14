#import "CoreVulkan.h"

#import <QuartzCore/QuartzCore.h>

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_metal.h>

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <vector>

#include "libretro.h"
#include "libretro_vulkan.h"

// Vulkan presentation for the core's hardware renderer, through MoltenVK.
//
// The core does not own a swapchain. It renders into its own image, calls
// set_image with a VkImageView and then asks for a video frame; this file blits
// that image into a CAMetalLayer drawable and presents it. Every stage reports
// what failed and why: a silent fall back to the software rasteriser is exactly
// the failure this frontend must not hide.

namespace {

void say(const char *format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    std::fprintf(stderr, "[azahar:vulkan] %s", buffer);
}

const char *result_name(VkResult result) {
    switch (result) {
    case VK_SUCCESS: return "VK_SUCCESS";
    case VK_NOT_READY: return "VK_NOT_READY";
    case VK_TIMEOUT: return "VK_TIMEOUT";
    case VK_ERROR_OUT_OF_HOST_MEMORY: return "out of host memory";
    case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "out of device memory";
    case VK_ERROR_INITIALIZATION_FAILED: return "initialization failed";
    case VK_ERROR_DEVICE_LOST: return "device lost";
    case VK_ERROR_MEMORY_MAP_FAILED: return "memory map failed";
    case VK_ERROR_LAYER_NOT_PRESENT: return "layer not present";
    case VK_ERROR_EXTENSION_NOT_PRESENT: return "extension not present";
    case VK_ERROR_FEATURE_NOT_PRESENT: return "feature not present";
    case VK_ERROR_INCOMPATIBLE_DRIVER: return "incompatible driver";
    case VK_ERROR_SURFACE_LOST_KHR: return "surface lost";
    case VK_ERROR_OUT_OF_DATE_KHR: return "swapchain out of date";
    case VK_SUBOPTIMAL_KHR: return "swapchain suboptimal";
    default: return "VkResult (see code)";
    }
}

void set_error(char *error, unsigned long size, const char *stage, VkResult result) {
    if (error == nullptr || size == 0) {
        return;
    }
    std::snprintf(error, size, "%s: %s", stage, result_name(result));
}

void set_message(char *error, unsigned long size, const char *message) {
    if (error == nullptr || size == 0) {
        return;
    }
    std::snprintf(error, size, "%s", message);
}

bool has_extension(const std::vector<VkExtensionProperties> &available, const char *name) {
    for (const auto &extension : available) {
        if (std::strcmp(extension.extensionName, name) == 0) {
            return true;
        }
    }
    return false;
}

} // namespace

struct AZVulkanHost {
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice gpu = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    uint32_t queue_family = 0;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    PFN_vkGetInstanceProcAddr gipa = nullptr;
    PFN_vkGetDeviceProcAddr gdpa = nullptr;

    void *layer = nullptr; // CAMetalLayer, borrowed

    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat swapchain_format = VK_FORMAT_UNDEFINED;
    VkExtent2D extent = {0, 0};
    std::vector<VkImage> swapchain_images;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkCommandBuffer command_buffer = VK_NULL_HANDLE;
    VkSemaphore acquired = VK_NULL_HANDLE;
    VkSemaphore rendered = VK_NULL_HANDLE;

    // The core's current frame, valid between set_image and the video callback.
    VkImage frame_image = VK_NULL_HANDLE;
    VkImageView frame_view = VK_NULL_HANDLE;
    VkImageLayout frame_layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    VkFormat frame_format = VK_FORMAT_UNDEFINED;
    bool have_frame = false;

    unsigned source_width = 0;
    unsigned source_height = 0;

    std::mutex queue_mutex;
    char description[192] = {0};
    bool reported_present_error = false;
};

namespace {

bool create_instance(AZVulkanHost *host,
                     const VkApplicationInfo *application_info,
                     char *error,
                     unsigned long error_size) {
    uint32_t count = 0;
    vkEnumerateInstanceExtensionProperties(nullptr, &count, nullptr);
    std::vector<VkExtensionProperties> available(count);
    if (count > 0) {
        vkEnumerateInstanceExtensionProperties(nullptr, &count, available.data());
    }

    std::vector<const char *> extensions;
    for (const char *required : {VK_KHR_SURFACE_EXTENSION_NAME,
                                 VK_EXT_METAL_SURFACE_EXTENSION_NAME}) {
        if (!has_extension(available, required)) {
            say("instance extension %s is not available\n", required);
            set_error(error, error_size, "Vulkan instance extension unavailable",
                      VK_ERROR_EXTENSION_NOT_PRESENT);
            return false;
        }
        extensions.push_back(required);
    }
    bool portability = false;
    if (has_extension(available, "VK_KHR_portability_enumeration")) {
        extensions.push_back("VK_KHR_portability_enumeration");
        portability = true;
    }
    if (has_extension(available, "VK_KHR_get_physical_device_properties2")) {
        extensions.push_back("VK_KHR_get_physical_device_properties2");
    }

    VkApplicationInfo fallback = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    fallback.pApplicationName = "Azahar iPad";
    fallback.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    fallback.pEngineName = "Azahar";
    fallback.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    fallback.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo info = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    info.pApplicationInfo = application_info != nullptr ? application_info : &fallback;
    info.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    info.ppEnabledExtensionNames = extensions.data();
    if (portability) {
        info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    const VkResult result = vkCreateInstance(&info, nullptr, &host->instance);
    if (result != VK_SUCCESS) {
        say("vkCreateInstance failed: %s\n", result_name(result));
        set_error(error, error_size, "Vulkan instance creation failed", result);
        return false;
    }
    say("instance created (Vulkan %u.%u.%u)\n", VK_VERSION_MAJOR(info.pApplicationInfo->apiVersion),
        VK_VERSION_MINOR(info.pApplicationInfo->apiVersion),
        VK_VERSION_PATCH(info.pApplicationInfo->apiVersion));
    return true;
}

bool create_surface(AZVulkanHost *host, char *error, unsigned long error_size) {
    if (host->layer == nullptr) {
        set_message(error, error_size, "no Metal layer to present into");
        return false;
    }
    VkMetalSurfaceCreateInfoEXT info = {VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    info.pLayer = (__bridge CAMetalLayer *)host->layer;
    const VkResult result = vkCreateMetalSurfaceEXT(host->instance, &info, nullptr, &host->surface);
    if (result != VK_SUCCESS) {
        say("vkCreateMetalSurfaceEXT failed: %s\n", result_name(result));
        set_error(error, error_size, "Metal surface creation failed", result);
        return false;
    }
    return true;
}

bool choose_gpu(AZVulkanHost *host, char *error, unsigned long error_size) {
    uint32_t count = 0;
    vkEnumeratePhysicalDevices(host->instance, &count, nullptr);
    if (count == 0) {
        say("no Vulkan physical device; MoltenVK does not appear to be registered\n");
        set_message(error, error_size, "no Vulkan physical device (MoltenVK missing)");
        return false;
    }
    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(host->instance, &count, devices.data());

    for (VkPhysicalDevice gpu : devices) {
        uint32_t family_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &family_count, nullptr);
        std::vector<VkQueueFamilyProperties> families(family_count);
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &family_count, families.data());

        for (uint32_t index = 0; index < family_count; ++index) {
            if ((families[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 0) {
                continue;
            }
            VkBool32 present = VK_FALSE;
            if (host->surface != VK_NULL_HANDLE) {
                vkGetPhysicalDeviceSurfaceSupportKHR(gpu, index, host->surface, &present);
                if (present == VK_FALSE) {
                    continue;
                }
            }
            host->gpu = gpu;
            host->queue_family = index;
            VkPhysicalDeviceProperties properties = {};
            vkGetPhysicalDeviceProperties(gpu, &properties);
            std::snprintf(host->description, sizeof(host->description), "%s",
                          properties.deviceName);
            say("physical device: %s (queue family %u)\n", properties.deviceName, index);
            return true;
        }
    }
    set_message(error, error_size, "no Vulkan queue with graphics and presentation");
    return false;
}

bool create_swapchain(AZVulkanHost *host) {
    if (host->device == VK_NULL_HANDLE || host->surface == VK_NULL_HANDLE) {
        return false;
    }

    VkSurfaceCapabilitiesKHR capabilities = {};
    if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(host->gpu, host->surface, &capabilities) !=
        VK_SUCCESS) {
        say("cannot query surface capabilities\n");
        return false;
    }

    uint32_t format_count = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(host->gpu, host->surface, &format_count, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(format_count);
    if (format_count > 0) {
        vkGetPhysicalDeviceSurfaceFormatsKHR(host->gpu, host->surface, &format_count,
                                             formats.data());
    }
    if (formats.empty()) {
        say("surface has no formats\n");
        return false;
    }
    VkSurfaceFormatKHR chosen = formats.front();
    for (const auto &format : formats) {
        if (format.format == host->frame_format) {
            chosen = format;
            break;
        }
    }

    VkExtent2D extent = capabilities.currentExtent;
    if (extent.width == UINT32_MAX || extent.height == UINT32_MAX) {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)host->layer;
        CGSize drawable = layer.drawableSize;
        if (drawable.width < 1.0 || drawable.height < 1.0) {
            const CGFloat scale = layer.contentsScale > 0 ? layer.contentsScale : 2.0;
            drawable = CGSizeMake(layer.bounds.size.width * scale,
                                  layer.bounds.size.height * scale);
            layer.drawableSize = drawable;
        }
        extent.width = static_cast<uint32_t>(drawable.width);
        extent.height = static_cast<uint32_t>(drawable.height);
        if (extent.width < capabilities.minImageExtent.width) {
            extent.width = capabilities.minImageExtent.width;
        }
        if (extent.height < capabilities.minImageExtent.height) {
            extent.height = capabilities.minImageExtent.height;
        }
        if (extent.width > capabilities.maxImageExtent.width) {
            extent.width = capabilities.maxImageExtent.width;
        }
        if (extent.height > capabilities.maxImageExtent.height) {
            extent.height = capabilities.maxImageExtent.height;
        }
    }
    if (extent.width == 0 || extent.height == 0) {
        say("swapchain extent is empty\n");
        return false;
    }

    uint32_t image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 && image_count > capabilities.maxImageCount) {
        image_count = capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR info = {VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    info.surface = host->surface;
    info.minImageCount = image_count;
    info.imageFormat = chosen.format;
    info.imageColorSpace = chosen.colorSpace;
    info.imageExtent = extent;
    info.imageArrayLayers = 1;
    info.imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    info.preTransform = capabilities.currentTransform;
    info.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    info.clipped = VK_TRUE;

    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkResult result = vkCreateSwapchainKHR(host->device, &info, nullptr, &swapchain);
    if (result != VK_SUCCESS) {
        say("vkCreateSwapchainKHR failed: %s (%ux%u, format %d)\n", result_name(result),
            extent.width, extent.height, static_cast<int>(chosen.format));
        return false;
    }
    host->swapchain = swapchain;
    host->swapchain_format = chosen.format;
    host->extent = extent;

    uint32_t images = 0;
    vkGetSwapchainImagesKHR(host->device, host->swapchain, &images, nullptr);
    host->swapchain_images.resize(images);
    vkGetSwapchainImagesKHR(host->device, host->swapchain, &images, host->swapchain_images.data());
    say("swapchain ready: %ux%u, %u images, format %d\n", extent.width, extent.height, images,
        static_cast<int>(chosen.format));

    VkCommandPoolCreateInfo pool_info = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool_info.queueFamilyIndex = host->queue_family;
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    if (vkCreateCommandPool(host->device, &pool_info, nullptr, &host->command_pool) != VK_SUCCESS) {
        return false;
    }
    VkCommandBufferAllocateInfo allocate = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    allocate.commandPool = host->command_pool;
    allocate.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocate.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(host->device, &allocate, &host->command_buffer) != VK_SUCCESS) {
        return false;
    }

    VkSemaphoreCreateInfo semaphore_info = {VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    vkCreateSemaphore(host->device, &semaphore_info, nullptr, &host->acquired);
    vkCreateSemaphore(host->device, &semaphore_info, nullptr, &host->rendered);
    return host->acquired != VK_NULL_HANDLE && host->rendered != VK_NULL_HANDLE;
}

void destroy_swapchain(AZVulkanHost *host) {
    if (host->command_pool != VK_NULL_HANDLE) {
        vkDestroyCommandPool(host->device, host->command_pool, nullptr);
        host->command_pool = VK_NULL_HANDLE;
        host->command_buffer = VK_NULL_HANDLE;
    }
    if (host->acquired != VK_NULL_HANDLE) {
        vkDestroySemaphore(host->device, host->acquired, nullptr);
        host->acquired = VK_NULL_HANDLE;
    }
    if (host->rendered != VK_NULL_HANDLE) {
        vkDestroySemaphore(host->device, host->rendered, nullptr);
        host->rendered = VK_NULL_HANDLE;
    }
    if (host->swapchain != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(host->device, host->swapchain, nullptr);
        host->swapchain = VK_NULL_HANDLE;
    }
    host->swapchain_images.clear();
}

void barrier(VkCommandBuffer command,
             VkImage image,
             VkImageLayout from,
             VkImageLayout to,
             VkAccessFlags src_access,
             VkAccessFlags dst_access,
             VkPipelineStageFlags src_stage,
             VkPipelineStageFlags dst_stage) {
    VkImageMemoryBarrier image_barrier = {VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
    image_barrier.oldLayout = from;
    image_barrier.newLayout = to;
    image_barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    image_barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    image_barrier.image = image;
    image_barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    image_barrier.subresourceRange.baseMipLevel = 0;
    image_barrier.subresourceRange.levelCount = 1;
    image_barrier.subresourceRange.baseArrayLayer = 0;
    image_barrier.subresourceRange.layerCount = 1;
    image_barrier.srcAccessMask = src_access;
    image_barrier.dstAccessMask = dst_access;
    vkCmdPipelineBarrier(command, src_stage, dst_stage, 0, 0, nullptr, 0, nullptr, 1,
                         &image_barrier);
}

void set_image_callback(void *handle,
                        const retro_vulkan_image *image,
                        uint32_t num_semaphores,
                        const VkSemaphore *semaphores,
                        uint32_t src_queue_family) {
    (void)num_semaphores;
    (void)semaphores;
    (void)src_queue_family;
    auto *host = static_cast<AZVulkanHost *>(handle);
    if (host == nullptr || image == nullptr) {
        return;
    }
    host->frame_view = image->image_view;
    host->frame_image = image->create_info.image;
    host->frame_layout = image->image_layout;
    host->frame_format = image->create_info.format;
    host->have_frame = host->frame_image != VK_NULL_HANDLE;
}

uint32_t get_sync_index_callback(void *handle) {
    (void)handle;
    // Presentation is synchronous below (the queue is drained each frame), so the
    // core can treat every frame as index 0 and reuse one set of resources.
    return 0;
}

uint32_t get_sync_index_mask_callback(void *handle) {
    (void)handle;
    return 1;
}

void wait_sync_index_callback(void *handle) {
    auto *host = static_cast<AZVulkanHost *>(handle);
    if (host != nullptr && host->device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(host->device);
    }
}

void lock_queue_callback(void *handle) {
    auto *host = static_cast<AZVulkanHost *>(handle);
    if (host != nullptr) {
        host->queue_mutex.lock();
    }
}

void unlock_queue_callback(void *handle) {
    auto *host = static_cast<AZVulkanHost *>(handle);
    if (host != nullptr) {
        host->queue_mutex.unlock();
    }
}

void set_signal_semaphore_callback(void *handle, VkSemaphore semaphore) {
    (void)handle;
    (void)semaphore;
}

void set_command_buffers_callback(void *handle,
                                  uint32_t num_cmd,
                                  const VkCommandBuffer *cmd) {
    (void)handle;
    (void)num_cmd;
    (void)cmd;
}

} // namespace

AZVulkanHost *AZVulkanHostCreate(void *metalLayer,
                                 const void *negotiationInterface,
                                 char *error,
                                 unsigned long errorSize) {
    const auto *negotiation =
        static_cast<const retro_hw_render_context_negotiation_interface_vulkan *>(
            negotiationInterface);
    if (negotiation == nullptr || negotiation->create_device == nullptr) {
        set_message(error, errorSize, "the core offered no Vulkan negotiation interface");
        return nullptr;
    }

    auto *host = new AZVulkanHost();
    host->layer = metalLayer;
    host->gipa = vkGetInstanceProcAddr;

    const VkApplicationInfo *application = negotiation->get_application_info != nullptr
                                               ? negotiation->get_application_info()
                                               : nullptr;
    if (!create_instance(host, application, error, errorSize)) {
        AZVulkanHostDestroy(host);
        return nullptr;
    }
    if (!create_surface(host, error, errorSize)) {
        AZVulkanHostDestroy(host);
        return nullptr;
    }
    if (!choose_gpu(host, error, errorSize)) {
        AZVulkanHostDestroy(host);
        return nullptr;
    }

    const char *extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkPhysicalDeviceFeatures features = {};
    retro_vulkan_context context = {};
    if (!negotiation->create_device(&context, host->instance, host->gpu, host->surface,
                                    host->gipa, extensions, 1, nullptr, 0, &features)) {
        say("the core's create_device refused this device\n");
        set_message(error, errorSize, "the core could not create a Vulkan device");
        AZVulkanHostDestroy(host);
        return nullptr;
    }

    host->device = context.device;
    host->queue = context.queue;
    host->queue_family = context.queue_family_index;
    host->gdpa = (PFN_vkGetDeviceProcAddr)host->gipa(host->instance, "vkGetDeviceProcAddr");

    say("device created through negotiation (%s), queue family %u\n", host->description,
        host->queue_family);
    return host;
}

void AZVulkanHostDestroy(AZVulkanHost *host) {
    if (host == nullptr) {
        return;
    }
    if (host->device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(host->device);
        destroy_swapchain(host);
        vkDestroyDevice(host->device, nullptr);
        host->device = VK_NULL_HANDLE;
    }
    if (host->surface != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR(host->instance, host->surface, nullptr);
        host->surface = VK_NULL_HANDLE;
    }
    if (host->instance != VK_NULL_HANDLE) {
        vkDestroyInstance(host->instance, nullptr);
        host->instance = VK_NULL_HANDLE;
    }
    delete host;
}

void AZVulkanHostSetSourceSize(AZVulkanHost *host, unsigned width, unsigned height) {
    if (host == nullptr) {
        return;
    }
    host->source_width = width;
    host->source_height = height;
}

BOOL AZVulkanHostFillInterface(AZVulkanHost *host, void *interface) {
    if (host == nullptr || interface == nullptr) {
        return NO;
    }
    auto *out = static_cast<retro_hw_render_interface_vulkan *>(interface);
    out->interface_type = RETRO_HW_RENDER_INTERFACE_VULKAN;
    out->interface_version = RETRO_HW_RENDER_INTERFACE_VULKAN_VERSION;
    out->handle = host;
    out->instance = host->instance;
    out->gpu = host->gpu;
    out->device = host->device;
    out->queue = host->queue;
    out->queue_index = host->queue_family;
    out->get_instance_proc_addr = host->gipa;
    out->get_device_proc_addr = host->gdpa;
    out->set_image = set_image_callback;
    out->get_sync_index = get_sync_index_callback;
    out->get_sync_index_mask = get_sync_index_mask_callback;
    out->set_command_buffers = set_command_buffers_callback;
    out->wait_sync_index = wait_sync_index_callback;
    out->lock_queue = lock_queue_callback;
    out->unlock_queue = unlock_queue_callback;
    out->set_signal_semaphore = set_signal_semaphore_callback;
    return YES;
}

void AZVulkanHostPresent(AZVulkanHost *host) {
    if (host == nullptr || !host->have_frame || host->device == VK_NULL_HANDLE) {
        return;
    }
    if (host->swapchain == VK_NULL_HANDLE && !create_swapchain(host)) {
        return;
    }

    uint32_t index = 0;
    VkResult result = vkAcquireNextImageKHR(host->device, host->swapchain, UINT64_MAX,
                                            host->acquired, VK_NULL_HANDLE, &index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        destroy_swapchain(host);
        return;
    }
    if (result != VK_SUCCESS) {
        if (!host->reported_present_error) {
            host->reported_present_error = true;
            say("vkAcquireNextImageKHR failed: %s\n", result_name(result));
        }
        return;
    }

    vkResetCommandBuffer(host->command_buffer, 0);
    VkCommandBufferBeginInfo begin = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(host->command_buffer, &begin) != VK_SUCCESS) {
        return;
    }

    barrier(host->command_buffer, host->frame_image, host->frame_layout,
            VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT,
            VK_PIPELINE_STAGE_TRANSFER_BIT);
    barrier(host->command_buffer, host->swapchain_images[index], VK_IMAGE_LAYOUT_UNDEFINED,
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
            VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);

    const int32_t source_width = static_cast<int32_t>(host->source_width > 0
                                                          ? host->source_width
                                                          : host->extent.width);
    const int32_t source_height = static_cast<int32_t>(host->source_height > 0
                                                           ? host->source_height
                                                           : host->extent.height);

    VkImageBlit blit = {};
    blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    blit.srcSubresource.layerCount = 1;
    blit.srcOffsets[0] = {0, 0, 0};
    blit.srcOffsets[1] = {source_width, source_height, 1};
    blit.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    blit.dstSubresource.layerCount = 1;
    blit.dstOffsets[0] = {0, 0, 0};
    blit.dstOffsets[1] = {static_cast<int32_t>(host->extent.width),
                          static_cast<int32_t>(host->extent.height), 1};
    vkCmdBlitImage(host->command_buffer, host->frame_image,
                   VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, host->swapchain_images[index],
                   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);

    barrier(host->command_buffer, host->swapchain_images[index],
            VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            VK_ACCESS_TRANSFER_WRITE_BIT, 0, VK_PIPELINE_STAGE_TRANSFER_BIT,
            VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
    // Leave the core's image in the layout it believes it is in.
    barrier(host->command_buffer, host->frame_image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            host->frame_layout, VK_ACCESS_TRANSFER_READ_BIT, VK_ACCESS_SHADER_READ_BIT,
            VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_GRAPHICS_BIT);

    if (vkEndCommandBuffer(host->command_buffer) != VK_SUCCESS) {
        return;
    }

    VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
    submit.waitSemaphoreCount = 1;
    submit.pWaitSemaphores = &host->acquired;
    submit.pWaitDstStageMask = &wait_stage;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &host->command_buffer;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &host->rendered;

    host->queue_mutex.lock();
    vkQueueSubmit(host->queue, 1, &submit, VK_NULL_HANDLE);
    vkQueueWaitIdle(host->queue);
    host->queue_mutex.unlock();

    VkPresentInfoKHR present = {VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present.waitSemaphoreCount = 1;
    present.pWaitSemaphores = &host->rendered;
    present.swapchainCount = 1;
    present.pSwapchains = &host->swapchain;
    present.pImageIndices = &index;

    host->queue_mutex.lock();
    result = vkQueuePresentKHR(host->queue, &present);
    vkQueueWaitIdle(host->queue);
    host->queue_mutex.unlock();

    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        destroy_swapchain(host);
    } else if (result != VK_SUCCESS && !host->reported_present_error) {
        host->reported_present_error = true;
        say("vkQueuePresentKHR failed: %s\n", result_name(result));
    }
}

const char *AZVulkanHostDescription(AZVulkanHost *host) {
    if (host == nullptr || host->description[0] == '\0') {
        return "Vulkan (MoltenVK)";
    }
    return host->description;
}
