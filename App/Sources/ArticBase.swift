import Foundation

/// One Artic Base connection: the address a person types, and what the core is
/// handed for it.
///
/// The address *is* the content. At the pinned tag `src/core/loader/loader.cpp`
/// dispatches `articbase://<host>[:<port>]` to `Apploader_Artic`, which reads the
/// port (5543 when there is none) and then talks to the server itself, so this app
/// never opens a socket and never learns which title it is about to play: the
/// console reports that. A wrong address is therefore a failed load rather than a
/// spinner here, which is why the player's failure text is written for streams.
struct ArticAddress: Equatable {
    let host: String
    /// nil when the address had no port. The core's own default is left to the
    /// core rather than written down twice and allowed to drift.
    let port: UInt16?

    /// What the core falls back to; `loader.cpp` has the same number.
    static let defaultPort: UInt16 = 5543
    /// Where the address that worked last is kept. One address, not a list: the
    /// console is the thing that decides which title streams.
    static let storageKey = "azahar.articbase.address.v1"

    /// What `AZCoreLoadGame` is given.
    var coreLocation: String {
        "articbase://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    /// What the screen calls it: the port is spelled out, because the core's
    /// default is a detail of the core, not of the address.
    var display: String {
        "\(host):\(port ?? ArticAddress.defaultPort)"
    }

    /// A key that is safe as a file name. This address names the session's save
    /// state and its control nudges, the way a title id does for a local file.
    var id: String {
        let number = port.map { String($0) } ?? String(ArticAddress.defaultPort)
        let safe = "\(host)-\(number)".map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return "articbase-" + String(safe)
    }

    /// The entry the player is handed.
    var entry: GameEntry {
        GameEntry(id: id,
                  location: coreLocation,
                  url: nil,
                  title: "Artic Base",
                  icon: nil,
                  subtitle: "Streaming from \(display)")
    }

    /// Reads what a person types: `192.168.1.5`, `192.168.1.5:5543`, or the whole
    /// `articbase://` string pasted from a note.
    ///
    /// Anything else is refused here rather than sent to the core: the core's only
    /// answer to a bad address is a failed load ten seconds later. A host name is
    /// allowed because the core resolves one, but only to IPv4 (`getaddrinfo` with
    /// `AF_INET`, and nothing else is offered).
    static func parse(_ raw: String) -> ArticAddress? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = "articbase://"
        if text.lowercased().hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }

        let host = String(parts[0])
        guard !host.isEmpty,
              host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }

        var port: UInt16?
        if parts.count == 2 {
            guard let value = UInt16(parts[1]), value > 0 else { return nil }
            port = value
        }
        return ArticAddress(host: host, port: port)
    }

    /// The address used last, if what is stored still reads as one.
    static var remembered: ArticAddress? {
        guard let text = UserDefaults.standard.string(forKey: storageKey) else { return nil }
        return parse(text)
    }

    /// Keeps this address for the next launch. Stored in the core's own form, so
    /// what is remembered is exactly what was sent.
    func remember() {
        UserDefaults.standard.set(coreLocation, forKey: ArticAddress.storageKey)
    }
}
