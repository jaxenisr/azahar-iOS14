#import "CoreBridge.h"

#include <cstdarg>
#include <cstdio>
#include <exception>
#include <string>

#include "libretro.h"

// The core is a libretro core: it assumes a frontend has installed callbacks
// before retro_init(), and it calls back for a log interface and its directories
// during initialisation. Everything below is the minimum honest frontend needed
// to let it start; the video/audio/input callbacks are installed by the
// emulation frontend in the next step.

namespace {

std::string g_save_directory;
std::string g_system_directory;
std::string g_last_error;
bool g_initialised = false;

void log_callback(enum retro_log_level level, const char *fmt, ...) {
    static const char *names[] = {"debug", "info", "warn", "error"};
    const char *name = (level <= RETRO_LOG_ERROR) ? names[level] : "log";
    std::fprintf(stderr, "[azahar:%s] ", name);
    va_list args;
    va_start(args, fmt);
    std::vfprintf(stderr, fmt, args);
    va_end(args);
}

bool environment_callback(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: {
        auto *cb = static_cast<retro_log_callback *>(data);
        cb->log = log_callback;
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
        return format == RETRO_PIXEL_FORMAT_XRGB8888;
    }
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: {
        *static_cast<unsigned *>(data) = 2;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: {
        *static_cast<bool *>(data) = false;
        return true;
    }
    case RETRO_ENVIRONMENT_GET_CAN_DUPE: {
        *static_cast<bool *>(data) = true;
        return true;
    }
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS:
        return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE: {
        *static_cast<unsigned *>(data) = RETRO_LANGUAGE_ENGLISH;
        return true;
    }
    // Core options and variables are reported as not provided for now, so the
    // core runs on its own defaults. The settings pass replaces this.
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL:
    case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_UPDATE_DISPLAY_CALLBACK:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_GET_VARIABLE:
        return false;
    default:
        return false;
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
        result += "  .  ";
        result += info.valid_extensions;
    }
    return result;
}

NSString *AZCoreDescribe(void) {
    const std::string text = core_name_and_version();
    return [NSString stringWithUTF8String:text.c_str()] ?: @"Azahar";
}

BOOL AZCoreInitialize(NSString *saveDirectory, NSString *systemDirectory) {
    if (g_initialised) {
        return YES;
    }

    g_last_error.clear();
    g_save_directory = saveDirectory.fileSystemRepresentation ?: "";
    g_system_directory = systemDirectory.fileSystemRepresentation ?: "";

    for (NSString *path in @[ saveDirectory, systemDirectory ]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }

    retro_set_environment(environment_callback);

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
    retro_deinit();
    g_initialised = false;
    g_save_directory.clear();
    g_system_directory.clear();
}
