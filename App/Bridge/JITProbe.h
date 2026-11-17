#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Whether this process can run code it writes itself.
///
/// A CPU JIT needs writable-then-executable memory, and iOS refuses that to an
/// app by default. What it does not refuse is decided outside the app: TrollStore
/// can grant a process the right to JIT before launch, and a debugger attached to
/// a build signed with `get-task-allow` gives it the same thing. Which of those
/// applies is not something the app can read off its own entitlements, so it asks
/// the kernel instead, doing exactly what Dynarmic's code cache does — map a page
/// executable, make it writable, write an instruction, make it executable again,
/// and run it. A process that can do all of that can run the JIT; one that cannot
/// would fault inside Dynarmic, which is why the answer is proved rather than
/// assumed.
///
/// The probe runs once per process; later calls return the first answer.
bool AZJITExecutableMemoryWorks(void);

#ifdef __cplusplus
}
#endif
