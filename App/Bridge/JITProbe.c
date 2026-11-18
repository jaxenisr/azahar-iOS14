#include "JITProbe.h"

#include <libkern/OSCacheControl.h>
#include <limits.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// The four steps below are the ones oaknut's CodeBlock takes on iOS, at the
// oaknut commit the pinned core's Dynarmic uses (include/oaknut/code_block.hpp,
// `#if TARGET_OS_IPHONE`): an anonymous mapping created executable, made
// writable to write into, made executable again, and entered. Dynarmic uses the
// same class for its code cache, so a page that survives this is a page it can
// use.
//
// This build is arm64 only (project.yml pins ARCHS), so the two instructions are
// ARM64: `mov w0, #42` then `ret`.
static const uint32_t kAnswer = 0x52800540u; // mov w0, #42
static const uint32_t kReturn = 0xD65F03C0u; // ret

// A jump into memory the OS does not consider code traps rather than returning.
// That is exactly the situation the probe exists to tell apart, so the call is
// made inside a guard: the two signals a bad jump raises are caught, the probe
// answers "no", and the process keeps running. A fault that arrives while the
// guard is not armed is handed to the handler that was there before, so no other
// part of the app loses its crash handling because of this.
static sigjmp_buf g_fault_jump;
static volatile sig_atomic_t g_guard_armed = 0;
static struct sigaction g_previous_segv;
static struct sigaction g_previous_bus;

static void fault_handler(int number) {
    if (g_guard_armed) {
        g_guard_armed = 0;
        siglongjmp(g_fault_jump, 1);
    }
    sigaction(SIGSEGV, &g_previous_segv, NULL);
    sigaction(SIGBUS, &g_previous_bus, NULL);
    raise(number);
}

static bool guard_signals(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = fault_handler;
    sigemptyset(&action.sa_mask);
    action.sa_flags = 0;
    if (sigaction(SIGSEGV, &action, &g_previous_segv) != 0) {
        return false;
    }
    if (sigaction(SIGBUS, &action, &g_previous_bus) != 0) {
        sigaction(SIGSEGV, &g_previous_segv, NULL);
        return false;
    }
    return true;
}

static void unguard_signals(void) {
    sigaction(SIGSEGV, &g_previous_segv, NULL);
    sigaction(SIGBUS, &g_previous_bus, NULL);
}

static bool probe(void) {
    const size_t size = 16384;
    void *memory = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (memory == MAP_FAILED || memory == NULL) {
        return false;
    }

    bool works = false;
    if (mprotect(memory, size, PROT_READ | PROT_WRITE) == 0) {
        uint32_t *instructions = (uint32_t *)memory;
        instructions[0] = kAnswer;
        instructions[1] = kReturn;
        if (mprotect(memory, size, PROT_READ | PROT_EXEC) == 0) {
            // Written through a writable alias and executed through another one:
            // the instruction cache is not coherent with the data cache.
            sys_icache_invalidate(memory, size);
            // Without the guard the call is not made at all: an answer that could
            // only be learnt by dying is not worth having.
            if (guard_signals()) {
                int32_t (*answer)(void) = (int32_t (*)(void))memory;
                // savemask 1: a fault blocks signals while it is handled, and the
                // jump back has to put the mask the way it was.
                if (sigsetjmp(g_fault_jump, 1) == 0) {
                    g_guard_armed = 1;
                    works = answer() == 42;
                    g_guard_armed = 0;
                } else {
                    works = false;
                }
                unguard_signals();
            }
        }
    }

    munmap(memory, size);
    return works;
}

// -1: not asked yet. The result cannot change within a process, so a race
// between two callers only ever means the probe runs twice.
static int g_result = -1;

bool AZJITExecutableMemoryWorks(void) {
    if (g_result < 0) {
        g_result = probe() ? 1 : 0;
    }
    return g_result == 1;
}

// What the user asked for, as opposed to what the process allows. Read by the
// shim that talks to the core, never by the probe.
static int g_allowed = 0;

void AZJITSetAllowed(bool allowed) {
    g_allowed = allowed ? 1 : 0;
}

bool AZJITAllowed(void) {
    return g_allowed != 0;
}

// A load that asks for the JIT leaves this file behind and removes it at its
// first frame. A process that dies running generated code never reaches that
// frame, so the file outlives it and the next launch finds it. That is the only
// way to hear about such a crash: nothing inside the process that faulted gets to
// report it. HOME is this app's own container on iOS.
static char g_attempt_path[PATH_MAX];

static const char *attempt_path(void) {
    if (g_attempt_path[0] == '\0') {
        const char *home = getenv("HOME");
        snprintf(g_attempt_path, sizeof(g_attempt_path), "%s/Library/Caches/cpu-jit-attempt",
                 home != NULL ? home : "/tmp");
    }
    return g_attempt_path;
}

bool AZJITAttemptPending(void) {
    return access(attempt_path(), F_OK) == 0;
}

void AZJITNoteAttempt(void) {
    FILE *file = fopen(attempt_path(), "w");
    if (file != NULL) {
        fclose(file);
    }
}

void AZJITClearAttempt(void) {
    remove(attempt_path());
}
