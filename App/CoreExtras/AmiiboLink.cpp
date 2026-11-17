// The amiibo tag reader.
//
// This is the one thing in this app that is not reachable through libretro. The
// core's libretro frontend registers an image decoder for texture packs and
// nothing else: amiibo live only on the core's own HLE service, `nfc:u`, and the
// only way in is the C++ interface the desktop frontend uses (citra_qt.cpp,
// GMainWindow::LoadAmiibo at tag 2127.0-rc3). So this file is a frontend
// translation unit, compiled by scripts/build-core.sh with the core's own
// compiler and flags and merged into libazahar_core.a as one more member.
//
// vendor/azahar is not touched: the tag stays the source of every symbol below.
// What that buys is exactly what the desktop frontend gets:
//
//   - a tag is a file. `NfcDevice::LoadAmiibo` reads 0x21C bytes (one NTAG215
//     dump, plain or encrypted) from a path the frontend chooses, and takes it
//     only while the running game is scanning (`device_state == SearchingForTag`);
//   - the core writes back. `NfcDevice::Flush` writes the tag - a saved level, a
//     trained fighter - into the same path, so the app hands over a copy and the
//     user's own dump is only ever read;
//   - an encrypted dump without the console's NFC keys is loaded read-only
//     (`is_write_protected`), which is the core's decision, not this file's.
//
// Threading: these calls come from the app's main thread while the emulation
// thread is running frames, which is what the desktop frontend does too. The
// kernel's HLE lock is taken first and held across the whole call: the service
// lookup itself walks the service manager's map, which the emulated title is
// changing whenever it connects to a service, so the read has to be inside the
// lock as much as the tag does.

#include <memory>
#include <mutex>
#include <string>

#include "core/core.h"
#include "core/hle/kernel/kernel.h"
#include "core/hle/service/nfc/nfc.h"
#include "core/hle/service/sm/sm.h"

namespace {

using NfcInterface = Service::NFC::Module::Interface;

/// The reader for the running title, or null when there is none. A service is
/// only in the manager once the game has connected to it, so a title that never
/// touches amiibo answers null here - which is the "nothing to read a tag into"
/// state rather than an error.
std::shared_ptr<NfcInterface> nfc_interface() {
    auto& system = Core::System::GetInstance();
    return system.ServiceManager().GetService<NfcInterface>("nfc:u");
}

std::recursive_mutex& hle_lock() {
    return Core::System::GetInstance().Kernel().GetHLELock();
}

} // namespace

// The values here are the ones documented in App/Bridge/CoreBridge.h.
extern "C" int AZCoreAmiiboCurrentState(void) {
    std::scoped_lock lock{hle_lock()};
    auto nfc = nfc_interface();
    if (nfc == nullptr) {
        return 0;
    }
    if (nfc->IsTagActive()) {
        return 3;
    }
    if (nfc->IsSearchingForAmiibos()) {
        return 2;
    }
    return 1;
}

extern "C" int AZCoreAmiiboLoad(const char* path) {
    if (path == nullptr || path[0] == '\0') {
        return 0;
    }
    std::scoped_lock lock{hle_lock()};
    auto nfc = nfc_interface();
    if (nfc == nullptr) {
        return 0;
    }
    // The core refuses a second tag while one is mounted, and refuses any tag
    // while the game is not scanning; asking first keeps a refusal from looking
    // like a bad file.
    if (nfc->IsTagActive()) {
        return 0;
    }
    return nfc->LoadAmiibo(std::string(path)) ? 1 : 0;
}

extern "C" void AZCoreAmiiboRemove(void) {
    std::scoped_lock lock{hle_lock()};
    auto nfc = nfc_interface();
    if (nfc == nullptr) {
        return;
    }
    nfc->RemoveAmiibo();
}
