#import "CoreBridge.h"
#import "CoreVulkan.h"

#import <CoreGraphics/CoreGraphics.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>
#include <map>
#include <string>

#include "libretro.h"
#include "libretro_vulkan.h"

// Frontend for Azahar's libretro core.
//
// The core owns everything: it reads content, manages its own threads and asks
// the frontend only for a surface to draw into, input state and some paths. The
// install order below matters: every callback has to be in place before
// retro_init(), because the core registers its options and directories during
// initialisation.
//
// Rendering: the core prefers Vulkan. For a hardware context it does not load
// content inside retro_load_game; it hands the frontend a negotiation interface,
// the frontend creates the device, and loading happens inside the context_reset
// callback the frontend invokes. When any of that cannot be provided the core
// falls back to its software rasteriser, and this bridge records the reason so the
// overlay can report it instead of silently showing 9%.

namespace {

std::string g_save_directory;
std::string g_system_directory;
std::string g_last_error;
std::string g_last_message;
bool g_initialised = false;
bool g_game_loaded = false;

FILE *g_log_file = nullptr;

std::atomic<double> g_frame_rate{60.0};
std::atomic<unsigned long long> g_frames_delivered{0};
std::atomic<unsigned long long> g_audio_frames{0};
std::atomic<unsigned> g_buttons{0};
std::atomic<int> g_circle_x{0};
std::atomic<int> g_circle_y{0};

AZCoreFrameCallback g_frame_callback = nullptr;
void *g_frame_context = nullptr;

// Hardware rendering state.
AZVulkanHost *g_vulkan = nullptr;
retro_hw_render_callback *g_hw_render = nullptr;
void *g_metal_layer = nullptr;
bool g_want_vulkan = true;
std::string g_vulkan_error;
char g_renderer_status[256] = "Software (core rasteriser)";
unsigned g_source_width = 0;
unsigned g_source_height = 0;

AZCoreMessageCallback g_message_callback = nullptr;
void *g_message_context = nullptr;

// Core option values: the core's own defaults, with the app's overrides applied
// on top. std::map keeps the strings at stable addresses, which matters because
// the core may keep the pointer GET_VARIABLE hands it.
std::map<std::string, std::string> g_options;

void write_log(const char *level, const char *text) {
    std::fprintf(stderr, "[azahar:%s] %s", level, text);
    if (g_log_file != nullptr) {
        std::fprintf(g_log_file, "[%s] %s", level, text);
        std::fflush(g_log_file);
    }
}

void log_callback(enum retro_log_level level, const char *fmt, ...) {
    static const char *names[] = {"debug", "info", "warn", "error"};
    const char *name = (level <= RETRO_LOG_ERROR) ? names[level] : "log";
    char buffer[8192];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    write_log(name, buffer);
}

void record_message(const char *text) {
    if (text == nullptr) {
        return;
    }
    g_last_message = text;
    write_log("user", (std::string(text) + "\n").c_str());
    if (g_message_callback != nullptr) {
        g_message_callback(text, g_message_context);
    }
}

void store_option(const char *key, const char *value) {
    if (key == nullptr) {
        return;
    }
    if (value == nullptr) {
        g_options.erase(key);
        return;
    }
    g_options[key] = value;
}

void apply_option_definitions_v2(const retro_core_option_v2_definition *definitions) {
    if (definitions == nullptr) {
        return;
    }
    for (const retro_core_option_v2_definition *option = definitions;
         option->key != nullptr; ++option) {
        // An override set by the app wins over the core's default.
        if (g_options.find(option->key) != g_options.end()) {
            continue;
        }
        std::string value = (option->default_value != nullptr) ? option->default_value : "";
        bool known = false;
        for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX; ++i) {
            if (option->values[i].value == nullptr) {
                continue;
            }
            if (value == option->values[i].value) {
                known = true;
                break;
            }
        }
        if (!known) {
            for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX; ++i) {
                if (option->values[i].value == nullptr) {
                    continue;
                }
                value = option->values[i].value;
                break;
            }
        }
        g_options[option->key] = value;
    }
}

void apply_option_definitions_v1(const retro_core_option_definition *definitions) {
    if (definitions == nullptr) {
        return;
    }
    for (const retro_core_option_definition *option = definitions;
         option->key != nullptr; ++option) {
        if (g_options.find(option->key) != g_options.end()) {
            continue;
        }
        std::string value = (option->default_value != nullptr) ? option->default_value : "";
        if (value.empty()) {
            for (int i = 0; i < RETRO_NUM_CORE_OPTION_VALUES_MAX; ++i) {
                if (option->values[i].value == nullptr) {
                    continue;
                }
                value = option->values[i].value;
                break;
            }
        }
        g_options[option->key] = value;
    }
}

bool environment_callback(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        static_cast<retro_log_callback *>(data)->log = log_callback;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: {
        if (g_save_directory.empty()) {
            return false;
        }
        *static_cast<const char **>(data) = g_save_directory.c_str();
        return true;
    }
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: {
        if (g_system_directory.empty()) {
            return false;
        }
        *static_cast<const char **>(data) = g_system_directory.c_str();
        return true;
    }
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: {
        const auto format = *static_cast<const retro_pixel_format *>(data);
        const bool supported = format == RETRO_PIXEL_FORMAT_XRGB8888;
        write_log("info", supported ? "pixel format: XRGB8888\n"
                                    : "pixel format: requested format is not supported\n");
        return supported;
    }
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: {
        *static_cast<unsigned *>(data) = 2;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2: {
        const auto *options = static_cast<const retro_core_options_v2 *>(data);
        apply_option_definitions_v2(options->definitions);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
        const auto *options = static_cast<const retro_core_options_v2_intl *>(data);
        if (options->us != nullptr) {
            apply_option_definitions_v2(options->us->definitions);
        }
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS: {
        apply_option_definitions_v1(static_cast<const retro_core_option_definition *>(data));
        return true;
    }
    case RETRO_ENVIRONMENT_SET_VARIABLES:
        // Legacy registration; the core asks for version 2 of the API above.
        return true;
    case RETRO_ENVIRONMENT_SET_VARIABLE: {
        const auto *variable = static_cast<const retro_variable *>(data);
        if (variable->key != nullptr && variable->value != nullptr) {
            store_option(variable->key, variable->value);
        }
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        auto *variable = static_cast<retro_variable *>(data);
        const auto found = g_options.find(variable->key != nullptr ? variable->key : "");
        if (found == g_options.end()) {
            variable->value = nullptr;
            return false;
        }
        variable->value = found->second.c_str();
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
        *static_cast<bool *>(data) = false;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY: {
        const auto *display = static_cast<const retro_core_option_display *>(data);
        if (display->key != nullptr) {
            write_log("info", (std::string("core hides option ") + display->key + "\n").c_str());
        }
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
        return false;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
        *static_cast<bool *>(data) = true;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        const auto *av = static_cast<const retro_system_av_info *>(data);
        if (av->timing.fps > 1.0) {
            g_frame_rate.store(av->timing.fps);
        }
        g_source_width = av->geometry.base_width;
        g_source_height = av->geometry.base_height;
        AZVulkanHostSetSourceSize(g_vulkan, g_source_width, g_source_height);
        char buffer[192];
        std::snprintf(buffer, sizeof(buffer),
                      "content timing: %.3f fps, geometry %ux%u\n", av->timing.fps,
                      av->geometry.base_width, av->geometry.base_height);
        write_log("info", buffer);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY: {
        const auto *geometry = static_cast<const retro_game_geometry *>(data);
        g_source_width = geometry->base_width;
        g_source_height = geometry->base_height;
        AZVulkanHostSetSourceSize(g_vulkan, g_source_width, g_source_height);
        char buffer[128];
        std::snprintf(buffer, sizeof(buffer), "geometry: %ux%u\n", geometry->base_width,
                      geometry->base_height);
        write_log("info", buffer);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: {
        *static_cast<bool *>(data) = true;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_INPUT_MAX_USERS: {
        *static_cast<unsigned *>(data) = 1;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER: {
        if (!g_want_vulkan) {
            return false;
        }
        *static_cast<unsigned *>(data) = static_cast<unsigned>(RETRO_HW_CONTEXT_VULKAN);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_HW_RENDER: {
        auto *callback = static_cast<retro_hw_render_callback *>(data);
        if (callback->context_type == RETRO_HW_CONTEXT_VULKAN && g_want_vulkan) {
            g_hw_render = callback;
            write_log("info", "core set up a Vulkan hardware context\n");
            return true;
        }
        write_log("warn", "core asked for a hardware context this build cannot provide\n");
        return false;
    }
    case RETRO_ENVIRONMENT_SET_HW_RENDER_CONTEXT_NEGOTIATION_INTERFACE: {
        if (!g_want_vulkan) {
            return false;
        }
        char error[256] = {0};
        g_vulkan = AZVulkanHostCreate(g_metal_layer, data, error, sizeof(error));
        if (g_vulkan == nullptr) {
            g_vulkan_error = error;
            std::snprintf(g_renderer_status, sizeof(g_renderer_status),
                          "Software (Vulkan failed: %s)", error);
            write_log("error",
                      (std::string("Vulkan host creation failed: ") + error + "\n").c_str());
            return false;
        }
        std::snprintf(g_renderer_status, sizeof(g_renderer_status), "Vulkan (MoltenVK): %s",
                      AZVulkanHostDescription(g_vulkan));
        write_log("info", (std::string("renderer: ") + g_renderer_status + "\n").c_str());
        return true;
    }
    case RETRO_ENVIRONMENT_GET_HW_RENDER_INTERFACE: {
        static retro_hw_render_interface_vulkan interface {};
        if (g_vulkan == nullptr || !AZVulkanHostFillInterface(g_vulkan, &interface)) {
            return false;
        }
        *static_cast<retro_hw_render_interface **>(data) =
            reinterpret_cast<retro_hw_render_interface *>(&interface);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_MEMORY_MAPS:
        return true;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE: {
        *static_cast<int *>(data) = 3; // audio and video enabled
        return true;
    }
    case RETRO_ENVIRONMENT_GET_MICROPHONE_INTERFACE:
        return false;
    case RETRO_ENVIRONMENT_GET_LANGUAGE: {
        *static_cast<unsigned *>(data) = RETRO_LANGUAGE_ENGLISH;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_MESSAGE_INTERFACE_VERSION: {
        *static_cast<unsigned *>(data) = 1;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_MESSAGE_EXT:
        return true;
    case RETRO_ENVIRONMENT_SET_MESSAGE: {
        const auto *message = static_cast<const retro_message *>(data);
        record_message(message->msg);
        return true;
    }
    case RETRO_ENVIRONMENT_SHUTDOWN:
        return false;
    case RETRO_ENVIRONMENT_GET_OVERSCAN: {
        *static_cast<bool *>(data) = false;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_JIT_CAPABLE: {
        *static_cast<bool *>(data) = false;
        return true;
    }
    default:
        return false;
    }
}

void video_refresh(const void *data, unsigned width, unsigned height, size_t pitch) {
    if (data == RETRO_HW_FRAME_BUFFER_VALID) {
        // The frame lives on the GPU; set_image already told us which image.
        AZVulkanHostPresent(g_vulkan);
        return;
    }
    if (data == nullptr || g_frame_callback == nullptr || width == 0 || height == 0) {
        return;
    }

    // The core's buffer is only valid for this call: wrap it in a CGImage, which
    // copies nothing until the frontend needs the pixels.
    CFDataRef bytes = CFDataCreate(kCFAllocatorDefault, static_cast<const UInt8 *>(data),
                                   static_cast<CFIndex>(pitch * height));
    if (bytes == nullptr) {
        return;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CFRelease(bytes);
    if (provider == nullptr) {
        return;
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    // 0x00RRGGBB in host order, i.e. B, G, R, X in memory: little-endian 32-bit
    // with the skipped component first.
    const CGBitmapInfo bitmap_info =
        static_cast<CGBitmapInfo>(static_cast<uint32_t>(kCGImageAlphaNoneSkipFirst) |
                                  static_cast<uint32_t>(kCGBitmapByteOrder32Little));
    CGImageRef image = CGImageCreate(width, height, 8, 32, pitch, space, bitmap_info,
                                     provider, nullptr, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);

    if (image != nullptr) {
        g_frames_delivered.fetch_add(1);
        g_frame_callback(image, g_frame_context);
        CGImageRelease(image);
    }
}

void audio_sample(int16_t left, int16_t right) {
    (void)left;
    (void)right;
    g_audio_frames.fetch_add(1);
}

size_t audio_sample_batch(const int16_t *data, size_t frames) {
    (void)data;
    g_audio_frames.fetch_add(frames);
    return frames;
}

void input_poll(void) {}

int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0 || device != RETRO_DEVICE_JOYPAD) {
        return 0;
    }
    const unsigned buttons = g_buttons.load();
    if (id == RETRO_DEVICE_ID_JOYPAD_MASK) {
        return static_cast<int16_t>(buttons & 0xFFFF);
    }
    if (id < 16) {
        return ((buttons >> id) & 1u) != 0 ? 1 : 0;
    }
    return 0;
}

int16_t input_state_analog(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0 || device != RETRO_DEVICE_ANALOG) {
        return 0;
    }
    if (index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
        if (id == RETRO_DEVICE_ID_ANALOG_X) {
            return static_cast<int16_t>(g_circle_x.load());
        }
        if (id == RETRO_DEVICE_ID_ANALOG_Y) {
            return static_cast<int16_t>(g_circle_y.load());
        }
    }
    return 0;
}

int16_t input_state_combined(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (device == RETRO_DEVICE_ANALOG) {
        return input_state_analog(port, device, index, id);
    }
    return input_state(port, device, index, id);
}

void open_log_file() {
    if (g_log_file != nullptr || g_system_directory.empty()) {
        return;
    }
    const std::string directory = g_system_directory + "/log";
    NSString *log_directory = [NSString stringWithUTF8String:directory.c_str()];
    if (log_directory == nil) {
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:log_directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    const std::string path = directory + "/frontend.log";
    g_log_file = std::fopen(path.c_str(), "w");
    if (g_log_file != nullptr) {
        std::fprintf(g_log_file, "[info] frontend log started\n");
        std::fflush(g_log_file);
    }
}

} // namespace

unsigned AZCoreAPIVersion(void) {
    return retro_api_version();
}

static std::string core_name_and_version() {
    struct retro_system_info info {};
    retro_get_system_info(&info);
    std::string result;
    if (info.library_name != nullptr) {
        result += info.library_name;
    }
    if (info.library_version != nullptr && info.library_version[0] != '\0') {
        result += " ";
        result += info.library_version;
    }
    if (info.valid_extensions != nullptr) {
        result += "  ·  ";
        result += info.valid_extensions;
    }
    return result;
}

NSString *AZCoreDescribe(void) {
    const std::string text = core_name_and_version();
    return [NSString stringWithUTF8String:text.c_str()] ?: @"Azahar";
}

void AZCoreSetOption(NSString *key, NSString *value) {
    if (key.length == 0) {
        return;
    }
    store_option(key.UTF8String, value.UTF8String);
}

BOOL AZCoreInitialize(NSString *saveDirectory, NSString *systemDirectory) {
    if (g_initialised) {
        return YES;
    }

    g_last_error.clear();
    g_last_message.clear();
    g_frames_delivered.store(0);
    g_vulkan_error.clear();
    std::snprintf(g_renderer_status, sizeof(g_renderer_status), "%s",
                  g_want_vulkan ? "Vulkan (pending)" : "Software (core rasteriser)");
    g_save_directory = saveDirectory.fileSystemRepresentation ?: "";
    g_system_directory = systemDirectory.fileSystemRepresentation ?: "";

    for (const NSString *path in @[ saveDirectory, systemDirectory ]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:(NSString *)path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    open_log_file();
    write_log("info", (std::string("system directory: ") + g_system_directory + "\n").c_str());
    write_log("info", (std::string("save directory: ") + g_save_directory + "\n").c_str());

    retro_set_environment(environment_callback);
    retro_set_video_refresh(video_refresh);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_sample_batch);
    retro_set_input_poll(input_poll);
    retro_set_input_state(input_state_combined);

    try {
        retro_init();
    } catch (const std::exception &e) {
        g_last_error = e.what();
        return NO;
    } catch (...) {
        g_last_error = "core init failed";
        return NO;
    }

    g_initialised = true;
    write_log("info", "core initialised\n");
    return YES;
}

NSString *AZCoreLastError(void) {
    if (g_last_error.empty()) {
        return nil;
    }
    return [NSString stringWithUTF8String:g_last_error.c_str()];
}

void AZCoreShutdown(void) {
    if (!g_initialised) {
        return;
    }
    if (g_game_loaded) {
        retro_unload_game();
        g_game_loaded = false;
    }
    if (g_hw_render != nullptr) {
        if (g_hw_render->context_destroy != nullptr) {
            g_hw_render->context_destroy();
        }
        g_hw_render = nullptr;
    }
    if (g_vulkan != nullptr) {
        AZVulkanHostDestroy(g_vulkan);
        g_vulkan = nullptr;
    }
    retro_deinit();
    g_initialised = false;
    g_save_directory.clear();
    g_system_directory.clear();
    g_frame_callback = nullptr;
    g_frame_context = nullptr;
    g_message_callback = nullptr;
    g_message_context = nullptr;
    write_log("info", "core shut down\n");
    if (g_log_file != nullptr) {
        std::fclose(g_log_file);
        g_log_file = nullptr;
    }
}

void AZCoreSetFrameCallback(AZCoreFrameCallback callback, void *context) {
    g_frame_callback = callback;
    g_frame_context = context;
}

void AZCoreSetMessageCallback(AZCoreMessageCallback callback, void *context) {
    g_message_callback = callback;
    g_message_context = context;
}

BOOL AZCoreLoadGame(NSString *path) {
    if (!g_initialised) {
        g_last_error = "core is not initialised";
        return NO;
    }
    if (g_game_loaded) {
        retro_unload_game();
        g_game_loaded = false;
    }

    const std::string utf8 = path.UTF8String ?: "";
    if (utf8.empty()) {
        g_last_error = "no content path was given";
        return NO;
    }

    g_last_error.clear();
    g_last_message.clear();
    g_frames_delivered.store(0);

    retro_game_info info {};
    info.path = utf8.c_str();
    info.data = nullptr;
    info.size = 0;
    info.meta = nullptr;

    bool loaded = false;
    try {
        write_log("info", (std::string("loading content: ") + utf8 + "\n").c_str());
        loaded = retro_load_game(&info);
    } catch (const std::exception &e) {
        g_last_error = e.what();
        return NO;
    } catch (...) {
        g_last_error = "the core threw an exception while loading content";
        return NO;
    }

    if (!loaded) {
        // The core explains itself through its message interface; that text is far
        // more useful than anything this bridge could say about it.
        g_last_error = g_last_message.empty() ? "the core refused to load this file"
                                              : g_last_message;
        write_log("error", (std::string("content rejected: ") + g_last_error + "\n").c_str());
        return NO;
    }

    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);

    // With a hardware renderer the core deliberately does not load the content in
    // retro_load_game: it waits until the frontend has a context, then loads inside
    // context_reset. So this call is what actually starts the game.
    if (g_hw_render != nullptr && g_hw_render->context_reset != nullptr) {
        if (g_vulkan == nullptr) {
            g_last_error = g_vulkan_error.empty()
                               ? "the Vulkan context was not created"
                               : g_vulkan_error;
            write_log("error", (std::string("content not started: ") + g_last_error + "\n").c_str());
            retro_unload_game();
            return NO;
        }
        write_log("info", "calling context_reset: loading content with the Vulkan renderer\n");
        try {
            g_hw_render->context_reset();
        } catch (const std::exception &e) {
            g_last_error = e.what();
            return NO;
        } catch (...) {
            g_last_error = "the core threw an exception while creating the Vulkan context";
            return NO;
        }
    }

    struct retro_system_av_info av {};
    retro_get_system_av_info(&av);
    if (av.timing.fps > 1.0) {
        g_frame_rate.store(av.timing.fps);
    }
    g_source_width = av.geometry.base_width;
    g_source_height = av.geometry.base_height;
    AZVulkanHostSetSourceSize(g_vulkan, g_source_width, g_source_height);
    char buffer[192];
    std::snprintf(buffer, sizeof(buffer), "content loaded: %.3f fps, %ux%u\n", av.timing.fps,
                  av.geometry.base_width, av.geometry.base_height);
    write_log("info", buffer);

    g_game_loaded = true;
    return YES;
}

void AZCoreRunFrame(void) {
    if (!g_game_loaded) {
        return;
    }
    retro_run();
}

void AZCoreUnloadGame(void) {
    if (g_game_loaded) {
        retro_unload_game();
        g_game_loaded = false;
        write_log("info", "content unloaded\n");
    }
    if (g_hw_render != nullptr) {
        if (g_hw_render->context_destroy != nullptr) {
            g_hw_render->context_destroy();
        }
        g_hw_render = nullptr;
    }
    if (g_vulkan != nullptr) {
        AZVulkanHostDestroy(g_vulkan);
        g_vulkan = nullptr;
    }
}

double AZCoreFrameRate(void) {
    return g_frame_rate.load();
}

unsigned long long AZCoreFramesDelivered(void) {
    return g_frames_delivered.load();
}

void AZCoreSetButtons(unsigned mask) {
    g_buttons.store(mask);
}

void AZCoreSetCirclePad(int x, int y) {
    g_circle_x.store(x);
    g_circle_y.store(y);
}

NSString *AZCoreLastMessage(void) {
    if (g_last_message.empty()) {
        return nil;
    }
    return [NSString stringWithUTF8String:g_last_message.c_str()];
}

void AZCoreSetMetalLayer(void *layer) {
    g_metal_layer = layer;
}

void AZCoreSetRendererPreference(BOOL preferVulkan) {
    g_want_vulkan = preferVulkan != NO;
}

const char *AZCoreRendererName(void) {
    return g_renderer_status;
}

BOOL AZCoreUsesHardwareVideo(void) {
    return g_vulkan != nullptr ? YES : NO;
}
