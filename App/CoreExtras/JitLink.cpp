// The CPU JIT, asked for in the core's own terms.
//
// The libretro core refuses the JIT on iOS: `src/citra_libretro/core_settings.cpp`
// sets `use_cpu_jit = false` under `#ifdef IOS` and does not register the option
// at all, and it does that every time it reads its options — which is the start
// of every load (`retro_load_game` calls `UpdateSettings`, which calls
// `ParseCoreOptions`). The value it writes is the one `Core::System::Init` reads
// when it builds the CPU (`src/core/core.cpp`), so the window in which a
// different answer is possible is between those two: after the core has read its
// options and before it creates the CPU.
//
// The app is told about exactly that window. The first thing the core asks a
// frontend for inside `retro_load_game` is the pixel format, and it asks before
// it touches the renderer or the loader; the frontend answers that request from
// `App/Bridge/CoreBridge.mm`, and answers it with this call when — and only when
// — `App/Bridge/JITProbe.c` has proved that this process can execute code it
// generates.
//
// Nothing here decides what is possible. Compiling the ARM11 is a property of the
// process (TrollStore's JIT, or a debugger attached to a build that carries
// `get-task-allow`), and the core builds Dynarmic only when the CPU it creates is
// asked for it on arm64.
//
// What this does decide is whether to ask. The frontend calls it only after
// proving the process can execute generated code, and the row on the Emulation
// page can say no regardless: both have to agree. And because a fault inside
// generated code cannot be caught by the process that asked for it, the request
// leaves a breadcrumb (`App/Bridge/JITProbe.c`) that the load's first frame
// removes. A launch that finds it still there is a launch that died here, and it
// plays interpreted instead of dying again.

#include "common/logging/log.h"
#include "common/settings.h"

#include "../Bridge/JITProbe.h"

extern "C" {

void AZCoreRequestJIT(void) {
    if (!AZJITAllowed()) {
        LOG_INFO(Core, "CPU JIT: not requested for this load");
        return;
    }
    AZJITNoteAttempt();
    Settings::values.use_cpu_jit = true;
}

}
