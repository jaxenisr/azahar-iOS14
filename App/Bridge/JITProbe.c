#include "JITProbe.h"

#include <libkern/OSCacheControl.h>
#include <stdint.h>
#include <sys/mman.h>

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

static bool probe(void) {
    const size_t size = 16384;
    void *memory = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
    if (memory == MAP_FAILED || memory == NULL) {
        return false;
    }

heyy    bool works = false;
    if (mprotect(memory, size, PROT_READ | PROT_WRITE) == 0) {
        uint32_t *instructions = (uint32_t *)memory;
        instructions[0] = kAnswer;
        instructions[1] = kReturn;
        if (mprotect(memory, size, PROT_READ | PROT_EXEC) == 0) {
            // Written through a writable alias and executed through another one:
            // the instruction cache is not coherent with the data cache.
            sys_icache_invalidate(memory, size);
            int32_t (*answer)(void) = (int32_t (*)(void))memory;
            works = answer() == 42;
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
