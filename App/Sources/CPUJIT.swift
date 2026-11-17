import Foundation

/// Whether this install can run the emulated CPU as compiled code, and why not
/// when it cannot.
///
/// The core can use Dynarmic — its ARM11 JIT — on every arm64 build, including
/// this one. What it will not do is use it on iOS: `core_settings.cpp` writes
/// `use_cpu_jit = false` under `#ifdef IOS` and does not even register the option.
/// This app overrides that refusal per load, but only after proving the process
/// can execute the code it generates (`App/Bridge/JITProbe.c`), because a JIT in a
/// process without that permission faults rather than falling back.
///
/// Who grants the permission is not the app's to decide, and there is no
/// entitlement here that pretends otherwise: TrollStore's own "Enable JIT" for a
/// process it launched, or a debugger attached to a build signed with
/// `get-task-allow`. Without either, the core interprets every instruction
/// (FastInterp), which is how this app has always played.
///
/// Nothing about this is stored. There is no choice to remember: the answer is a
/// property of the running process, and the app takes it every time.
enum CPUJIT {
    /// Proved by mapping a page executable and running an instruction written into
    /// it — the same four steps Dynarmic's code cache takes. Asked once per
    /// process.
    static let isAvailable: Bool = AZJITExecutableMemoryWorks()

    /// What the row reads. `On` is a promise each load keeps: while this is true,
    /// every load asks the core for Dynarmic.
    static var state: String { isAvailable ? "On" : "Off" }

    /// The row's subtitle: what is running, and what to do about it.
    static var explanation: String {
        if isAvailable {
            return "On: this process can run code it generates, so the emulated ARM11 is compiled as it runs (Dynarmic). Read at every load"
        }
        return "Off: this process cannot run code it generates, so every instruction is interpreted (FastInterp). Enable JIT for Azahar in TrollStore before launching it, or attach a debugger to a build signed with get-task-allow"
    }
}
