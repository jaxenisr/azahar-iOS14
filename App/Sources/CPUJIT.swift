import Foundation

/// What the Emulation page lets a user choose about the CPU JIT.
///
/// The row's third state is `nil` — nothing stored — and it is not the same as
/// either value: it means `Default`, which is also the only state an install has
/// before anyone presses the row.
enum CPUJITMode: String, Codable, CaseIterable, Hashable {
    case on
    case off

    var title: String {
        switch self {
        case .on: return "On"
        case .off: return "Off"
        }
    }
}

/// Whether this install can run the emulated CPU as compiled code, and whether it
/// should.
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
/// Permission is only half of it. Dynarmic has never been run on this device by
/// anyone, and a fault inside generated code cannot be caught by the process that
/// asked for it — so a load that asked for the JIT records that it did, and clears
/// the record when it produces its first frame. A launch that finds the record
/// still there knows the previous one died at load, and plays interpreted until
/// someone asks for the JIT again.
enum CPUJIT {
    /// Proved by mapping a page executable and running an instruction written into
    /// it — the same four steps Dynarmic's code cache takes. Asked once per
    /// process; the answer cannot change while it runs.
    static let isAvailable: Bool = AZJITExecutableMemoryWorks()

    /// Where the shim records that a load asked for Dynarmic and has not reached
    /// its first frame yet.
    private static let crashedKey = "azahar.cpuJIT.crashedLastLoad"

    /// The previous launch's evidence, read once. The shim writes the breadcrumb
    /// before it asks the core for the JIT and the first frame removes it, so a
    /// breadcrumb found at launch is a load that never got that far.
    private static let recovered: Bool = {
        guard AZJITAttemptPending() else { return false }
        AZJITClearAttempt()
        UserDefaults.standard.set(true, forKey: crashedKey)
        return true
    }()

    /// Whether the last load that used Dynarmic is known to have died before its
    /// first frame.
    static var lastLoadCrashed: Bool {
        _ = recovered
        return UserDefaults.standard.bool(forKey: crashedKey)
    }

    /// Called when a load that used Dynarmic reached its first frame and ended. It
    /// is the proof the JIT works here, so the memory of a load that did not is
    /// cleared.
    static func noteHealthyLoad() {
        guard UserDefaults.standard.bool(forKey: crashedKey) else { return }
        UserDefaults.standard.set(false, forKey: crashedKey)
    }

    /// Decides this load and tells the core-side shim, which is the only thing
    /// that asks the core. Returns what it decided, so the caller can report the
    /// outcome when the load ends.
    @discardableResult
    static func beginLoad(_ choice: CPUJITMode?) -> Bool {
        let use = shouldUse(choice)
        AZJITSetAllowed(use)
        return use
    }

    /// Whether the next load should ask the core for Dynarmic.
    ///
    /// The stored choice can only say "try" or "do not try"; permission belongs to
    /// the process, so `On` still means nothing on a process that cannot run
    /// generated code.
    static func shouldUse(_ choice: CPUJITMode?) -> Bool {
        guard isAvailable else { return false }
        if choice == .on { return true }
        if choice == .off { return false }
        return !lastLoadCrashed
    }

    /// What the row says this choice amounts to on this launch.
    static func state(for choice: CPUJITMode?) -> String {
        shouldUse(choice) ? "On" : "Off"
    }

    /// The row's subtitle: what is running, and what to do about it.
    static func explanation(for choice: CPUJITMode?) -> String {
        guard isAvailable else {
            return "Off: this process cannot run code it generates, so every instruction is interpreted (FastInterp). Enable JIT for Azahar in TrollStore before launching it, or attach a debugger to a build signed with get-task-allow"
        }
        if shouldUse(choice) {
            return "On: the emulated ARM11 is compiled as it runs (Dynarmic). This process can run code it generates"
        }
        if choice == .off {
            return "Off: every instruction is interpreted (FastInterp). This process could run generated code, but the choice here is not to"
        }
        return "Off for now: the last load with the JIT on died before its first frame, so this one interprets. Choose On to try Dynarmic again"
    }
}
