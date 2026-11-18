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

/// Whether the next load may ask the core for the JIT.
///
/// The probe answers what the process allows; this answers what the user asked
/// for. Both have to be true, and they are read in the shim the frontend calls
/// while the core is loading (`App/CoreExtras/JitLink.cpp`) rather than here, so
/// that the answer to "may generated code run" stays a fact about the process.
void AZJITSetAllowed(bool allowed);
bool AZJITAllowed(void);

/// The breadcrumb a load leaves until its first frame, and the only way this app
/// can learn about a crash in generated code: the process that faulted is gone,
/// so the next launch finds the breadcrumb and plays interpreted instead. It
/// lives in the app's caches, next to nothing else that matters.
bool AZJITAttemptPending(void);
void AZJITNoteAttempt(void);
void AZJITClearAttempt(void);

#ifdef __cplusplus
}
#endif
