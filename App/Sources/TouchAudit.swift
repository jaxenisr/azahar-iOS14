import SwiftUI
import UIKit

/// One line per touch event, appended beside the logs the rest of the frontend
/// writes.
///
/// A tap that never reaches the emulator cannot be explained by a counter alone,
/// because the useful part is where it went instead.
enum TouchLog {
    static func write(_ line: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory,
                                                      in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent("Azahar/log", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("frontend-touch.log")
            let stamp = ISO8601DateFormatter().string(from: Date())
            guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: url)
            }
        } catch {
            NSLog("[Azahar] touch log unavailable: %@", error.localizedDescription)
        }
    }
}

/// Which view UIKit chose for the last touch, and whether that view was the
/// touchscreen or something above it.
enum TouchAudit {
    private(set) static var lastHit = "nothing yet"
    private(set) static var hitTests = 0

    /// True when the touchscreen itself took the last touch, rather than a layer
    /// over it.
    static var reachedSurface: Bool {
        lastHit.hasPrefix("TouchSurfaceView")
    }

    static func record(_ winner: UIView?) {
        hitTests += 1
        guard let winner = winner else {
            lastHit = "no view"
            return
        }
        // The winner first, then what it sits in: the layer at fault is usually
        // the one that is not the surface, and this names it.
        var names: [String] = []
        var view: UIView? = winner
        while let current = view, names.count < 3 {
            names.append(name(of: current))
            view = current.superview
        }
        lastHit = names.joined(separator: " ← ")
    }

    /// SwiftUI's hosting classes carry their whole generic signature in the type
    /// name, which is unreadable in a card and useless in a log.
    private static func name(of view: UIView) -> String {
        let full = String(describing: type(of: view))
        return String(full.split(separator: "<").first ?? Substring(full))
    }
}

/// Watches what hit testing does without taking part in it. A recogniser on the
/// window sees every touch whichever view won it, and this one never recognises,
/// so nothing is delayed, cancelled or routed differently.
private final class HitTestRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let window = view?.window {
            let point = touch.location(in: window)
            TouchAudit.record(window.hitTest(point, with: event))
            TouchLog.write("hit \(TouchAudit.lastHit) at \(Int(point.x)),\(Int(point.y))")
        }
        state = .failed
    }
}

final class TouchAuditHostView: UIView {
    private let recognizer = HitTestRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer.view?.removeGestureRecognizer(recognizer)
        window?.addGestureRecognizer(recognizer)
    }
}

/// Installs the audit on the window the playback screen lives in.
struct TouchAuditProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> TouchAuditHostView {
        TouchAuditHostView()
    }

    func updateUIView(_ view: TouchAuditHostView, context: Context) {}
}
